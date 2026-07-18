#!/bin/bash
#
# cert_check.sh
#
# Certificate discovery, expiry-check and configuration-check helper for
# the Zabbix template "Certificate Expiry by Zabbix agent".
#
# Usage:
#   cert_check.sh discovery  "<CERTFILES macro value>"
#   cert_check.sh value      "<file path>" "<certificate CN, sanitized>"
#   cert_check.sh filecheck  "<CERTFILES macro value>"
#
# {$CERTFILES} macro format (comma-separated list of file definitions):
#   /path/to/file1:WARN_DAYS:HIGH_DAYS,/path/to/file2:WARN_DAYS:HIGH_DAYS
#
# NOTE: file paths must not themselves contain a comma character, as comma
# is used as the top-level separator between file definitions.
#
# A referenced file may hold a single certificate or a bundle of several
# PEM certificates (e.g. a CA/RadSec bundle). Every certificate found in
# every file is discovered individually and identified by its Common Name
# (CN), NOT the full subject. Reasons:
#   - the full subject (which may include emailAddress, O, OU, ...) can
#     contain characters that Zabbix's UserParameter mechanism rejects
#     outright as a security precaution against shell injection, namely:
#     \ ' " ` * ? [ ] { } ~ $ ! & ; ( ) < > | # @ and newline.
#   - CN alone is very unlikely to contain any of these.
# As defense in depth, the extracted CN is additionally sanitized: any
# character outside [A-Za-z0-9 ._-] is replaced with an underscore before
# it is ever used as an item key / LLD macro value.
#
# Security: every file path (from {$CERTFILES} or passed directly to the
# "value" mode) must be absolute and must not contain a ".." path segment,
# so a macro value can never be used to read files outside of what was
# explicitly configured (see is_safe_path()).
#
# Deliberately not using `set -e` / `set -o pipefail`: this script relies
# on explicit checks (`... || continue`, empty-result checks) to skip a
# single bad certificate/entry and keep processing the rest, e.g. one
# corrupt certificate in a bundle should not abort discovery of the other,
# valid ones in the same file. `pipefail` would make an internal openssl
# failure (inside get_cn()/get_enddate_epoch(), which run at the end of a
# pipeline) abort the whole script immediately and silently instead of
# being handled by the explicit checks already in place.
#
# Dependencies: bash, awk, sed, tr, openssl, GNU date (all present by
# default on Debian 12+ / Ubuntu 24.04+).

set -u
set -f          # disable globbing - certificate paths must be taken literally
LC_ALL=C
export LC_ALL

# --- helpers ----------------------------------------------------------

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

is_int() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# Path must be absolute and must not contain a ".." segment, so a macro
# value (or a manually crafted item key) can never be used to read files
# outside of what was explicitly configured, e.g. via
# "/etc/freeradius/certs/../../../../etc/shadow".
is_safe_path() {
    case "$1" in
        /*) : ;;
        *) return 1 ;;
    esac
    case "$1" in
        */../*|*/..) return 1 ;;
    esac
    return 0
}

# Split a PEM file into individual certificate blocks and print each one,
# followed by a boundary marker line.
split_certs() {
    awk '
        /-----BEGIN CERTIFICATE-----/ { incert=1 }
        incert { print }
        /-----END CERTIFICATE-----/   { incert=0; print "-----CERT-BOUNDARY-----" }
    ' "$1" 2>/dev/null
}

# Reads one PEM certificate block from stdin, prints only its commonName
# (CN), using the "multiline" nameopt so we don't have to deal with
# RFC2253 comma/escaping rules at all.
get_cn() {
    openssl x509 -noout -subject -nameopt multiline 2>/dev/null | \
        sed -n 's/^ *commonName  *= //p' | head -n1
}

# Replace anything outside [A-Za-z0-9 ._-] with underscore. Guarantees the
# result never contains a character forbidden by Zabbix's UserParameter
# parameter sanitizer, regardless of what appears in the certificate.
sanitize() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9 ._-' '_'
}

get_enddate_epoch() {
    local enddate
    enddate=$(openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
    [ -z "$enddate" ] && return 1
    date -d "$enddate" +%s 2>/dev/null
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# --- modes --------------------------------------------------------------

do_discovery() {
    local macro="$1"
    local entry path warn high buf line cn first=1
    local old_ifs="$IFS"

    printf '{\n  "data": [\n'

    IFS=','
    for entry in $macro; do
        IFS="$old_ifs"
        entry="$(trim "$entry")"
        [ -z "$entry" ] && continue

        IFS=':' read -r path warn high <<< "$entry"
        IFS="$old_ifs"
        path="$(trim "$path")"; warn="$(trim "$warn")"; high="$(trim "$high")"
        [ -z "$path" ] && continue
        is_safe_path "$path" || continue
        [ -r "$path" ] || continue
        is_int "$warn" || continue
        is_int "$high" || continue

        buf=""
        while IFS= read -r line; do
            if [ "$line" = "-----CERT-BOUNDARY-----" ]; then
                cn=$(printf '%s\n' "$buf" | get_cn)
                cn=$(sanitize "$cn")
                if [ -n "$cn" ]; then
                    [ "$first" -eq 0 ] && printf ',\n'
                    first=0
                    printf '    {"{#CERTFILE}":"%s","{#CERTCN}":"%s","{#WARNDAYS}":"%s","{#HIGHDAYS}":"%s"}' \
                        "$(json_escape "$path")" "$(json_escape "$cn")" "$warn" "$high"
                fi
                buf=""
            else
                buf="${buf}${line}
"
            fi
        done < <(split_certs "$path")
    done

    printf '\n  ]\n}\n'
}

do_value() {
    local path="$1"
    local wanted_cn="$2"
    local buf line cn epoch now

    if [ -z "$path" ]; then
        echo "ZBX_NOTSUPPORTED: no certificate file path given"
        exit 1
    fi
    if [ -z "$wanted_cn" ]; then
        echo "ZBX_NOTSUPPORTED: no certificate CN given"
        exit 1
    fi
    if ! is_safe_path "$path"; then
        echo "ZBX_NOTSUPPORTED: certificate file path must be absolute and must not contain '..': $path"
        exit 1
    fi

    if [ ! -r "$path" ]; then
        echo "ZBX_NOTSUPPORTED: cannot read file $path"
        exit 1
    fi

    buf=""
    while IFS= read -r line; do
        if [ "$line" = "-----CERT-BOUNDARY-----" ]; then
            cn=$(printf '%s\n' "$buf" | get_cn)
            cn=$(sanitize "$cn")
            if [ "$cn" = "$wanted_cn" ]; then
                epoch=$(printf '%s\n' "$buf" | get_enddate_epoch)
                if [ -z "$epoch" ]; then
                    echo "ZBX_NOTSUPPORTED: cannot parse certificate end date in $path"
                    exit 1
                fi
                now=$(date +%s)
                echo $(( (epoch - now) / 86400 ))
                exit 0
            fi
            buf=""
        else
            buf="${buf}${line}
"
        fi
    done < <(split_certs "$path")

    echo "ZBX_NOTSUPPORTED: certificate with CN '$wanted_cn' not found in $path"
    exit 1
}

do_filecheck() {
    local macro="$1"
    local entry path warn high
    local old_ifs="$IFS"
    local problems=()

    IFS=','
    for entry in $macro; do
        IFS="$old_ifs"
        entry="$(trim "$entry")"
        [ -z "$entry" ] && continue

        IFS=':' read -r path warn high <<< "$entry"
        IFS="$old_ifs"
        path="$(trim "$path")"; warn="$(trim "$warn")"; high="$(trim "$high")"
        [ -z "$path" ] && continue

        if ! is_safe_path "$path"; then
            problems+=("unsafe path (must be absolute, no '..' segments): $path")
            continue
        fi

        if [ ! -r "$path" ]; then
            problems+=("file not readable: $path")
            continue
        fi
        if ! is_int "$warn" || ! is_int "$high"; then
            problems+=("invalid thresholds for $path (warn='$warn' high='$high')")
        fi
    done

    if [ "${#problems[@]}" -eq 0 ]; then
        echo "OK"
    else
        local msg="" p
        for p in "${problems[@]}"; do
            if [ -z "$msg" ]; then msg="$p"; else msg="$msg; $p"; fi
        done
        echo "PROBLEMS: $msg"
    fi
}

case "${1:-}" in
    discovery)
        do_discovery "${2:-}"
        ;;
    value)
        do_value "${2:-}" "${3:-}"
        ;;
    filecheck)
        do_filecheck "${2:-}"
        ;;
    *)
        echo "Usage: $0 discovery <macro_value> | value <file> <cn> | filecheck <macro_value>" >&2
        exit 1
        ;;
esac
