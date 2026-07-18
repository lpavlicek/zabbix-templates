#!/bin/bash
#
# freeradius_stats.sh
#
# Queries the FreeRADIUS status server (server status { listen { type = status ... } })
# via radclient and returns the raw "Attribute = value" lines from the reply.
# Used as a master item by the "FreeRADIUS Statistics by Zabbix agent" template;
# individual counters are extracted from the raw text by dependent items using
# regular-expression preprocessing (so radclient is invoked only once per poll,
# not once per metric).
#
# Usage:
#   freeradius_stats.sh global <host> <port> <type>
#   freeradius_stats.sh client <host> <port> <type> <client_ip>
#   freeradius_stats.sh client_discovery "<RADIUS.CLIENTS macro value>"
#
# {$RADIUS.CLIENTS} macro format (comma-separated list of NAS definitions):
#   ip1:label1,ip2:label2
# (labels are for display only, e.g. item/trigger names; keep them short and
# avoid characters outside [A-Za-z0-9._-], see sanitize())
#
# The shared secret is intentionally NOT passed as a Zabbix macro (it would be
# visible in `ps` output and in the Zabbix frontend) and NOT passed as a
# radclient command-line argument either - it's passed via radclient's own
# "-S <file>" option, so radclient reads it directly from the file and it
# never appears as a process argument at all. The path to that file is given
# by {$RADIUS.STATUS.SECRETFILE}.
#
# Security: {$RADIUS.STATS.TYPE.*} and the client IP (from {$RADIUS.CLIENTS}
# or passed directly to "client") are validated (is_valid_type / is_valid_ip)
# before being interpolated into the attribute/value list sent to radclient,
# so a malformed macro value can never inject extra RADIUS attributes into
# the request (e.g. an IP of "1.2.3.4, FreeRADIUS-Statistics-Type = 0xff").
#
# Dependencies: bash, radclient (freeradius-utils package).

set -u
set -f
LC_ALL=C
export LC_ALL

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

sanitize() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9 ._-' '_'
}

# Restrict to characters that can appear in a real IPv4/IPv6 address. This is
# not a full address validator, but it is enough to guarantee the value can
# never be used to inject extra attribute/value pairs into the request sent
# to radclient (e.g. a comma or "=" in {$RADIUS.CLIENTS} smuggling in a fake
# "FreeRADIUS-Statistics-Type = ..." pair), and can never break the LLD JSON.
is_valid_ip() {
    case "$1" in
        '') return 1 ;;
        *[!0-9A-Fa-f.:]*) return 1 ;;
        *) return 0 ;;
    esac
}

# {$RADIUS.STATS.TYPE.*} should be a plain hex (0x1f) or decimal number.
is_valid_type() {
    case "$1" in
        ''|*[!0-9A-Fa-fXx]*) return 1 ;;
        *) return 0 ;;
    esac
}

usage() {
    echo "Usage: $0 global <host> <port> <type> | client <host> <port> <type> <client_ip> | client_discovery <macro_value>" >&2
    exit 1
}

# Run radclient and print only the reply attribute lines ("Name = value"),
# discarding the "Sent .../Received ..." status lines that -x also prints.
# NOTE: on any failure this prints "ZBX_NOTSUPPORTED: ..." to STDOUT (not
# stderr) - Zabbix agent only reads stdout as the item value, so an error
# message on stderr would result in an empty value rather than a clearly
# unsupported item.
#
# The secret is passed to radclient via "-S <file>" (read by radclient
# itself from the file) rather than as a command-line argument, so it never
# appears in `ps` output for the duration of the call.
run_query() {
    local host="$1" port="$2" avps="$3" secret_file="$4"
    local out stats_error

    if [ ! -r "$secret_file" ]; then
        echo "ZBX_NOTSUPPORTED: secret file $secret_file not readable"
        return 1
    fi

    out=$(printf '%s\n' "$avps" | radclient -x -r 2 -t 2 -S "$secret_file" "${host}:${port}" status 2>&1)

    if ! printf '%s\n' "$out" | grep -q '^Received'; then
        echo "ZBX_NOTSUPPORTED: no valid reply from status server ${host}:${port}"
        return 1
    fi

    # FreeRADIUS returns a normal-looking reply containing this attribute instead
    # of the expected counters when the target isn't recognised for stats - e.g.
    # an unknown IP, or (observed in practice) a RadSec/TLS client that shows up
    # fine in "radmin show client list" but has no per-client stats available.
    stats_error=$(printf '%s\n' "$out" | sed -n 's/.*FreeRADIUS-Stats-Error = "\(.*\)".*/\1/p' | head -n1)
    if [ -n "$stats_error" ]; then
        echo "ZBX_NOTSUPPORTED: FreeRADIUS-Stats-Error: $stats_error"
        return 1
    fi

    printf '%s\n' "$out" | grep ' = ' | sed 's/^[[:space:]]*//'
}

do_global() {
    local host="$1" port="$2" type="$3" secret_file="$4"
    if ! is_valid_type "$type"; then
        echo "ZBX_NOTSUPPORTED: invalid {\$RADIUS.STATS.TYPE.GLOBAL} value: $type"
        return 1
    fi
    run_query "$host" "$port" "Message-Authenticator = 0x00, FreeRADIUS-Statistics-Type = ${type}" "$secret_file"
}

do_client() {
    local host="$1" port="$2" type="$3" client_ip="$4" secret_file="$5"
    if ! is_valid_type "$type"; then
        echo "ZBX_NOTSUPPORTED: invalid {\$RADIUS.STATS.TYPE.CLIENT} value: $type"
        return 1
    fi
    if ! is_valid_ip "$client_ip"; then
        echo "ZBX_NOTSUPPORTED: invalid client IP: $client_ip"
        return 1
    fi
    run_query "$host" "$port" "Message-Authenticator = 0x00, FreeRADIUS-Statistics-Type = ${type}, FreeRADIUS-Stats-Client-IP-Address = ${client_ip}" "$secret_file"
}

do_client_discovery() {
    local macro="$1"
    local entry ip label first=1
    local old_ifs="$IFS"

    printf '{\n  "data": [\n'
    IFS=','
    for entry in $macro; do
        IFS="$old_ifs"
        entry="$(trim "$entry")"
        [ -z "$entry" ] && continue

        IFS=':' read -r ip label <<< "$entry"
        IFS="$old_ifs"
        ip="$(trim "$ip")"; label="$(sanitize "$(trim "$label")")"
        [ -z "$ip" ] && continue
        is_valid_ip "$ip" || continue
        [ -z "$label" ] && label="$ip"

        [ "$first" -eq 0 ] && printf ',\n'
        first=0
        printf '    {"{#CLIENTIP}":"%s","{#CLIENTLABEL}":"%s"}' "$ip" "$label"
    done
    printf '\n  ]\n}\n'
}

case "${1:-}" in
    global)           do_global "${2:-}" "${3:-}" "${4:-}" "${5:-}" ;;
    client)           do_client "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" ;;
    client_discovery) do_client_discovery "${2:-}" ;;
    *) usage ;;
esac
