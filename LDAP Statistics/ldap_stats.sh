#!/bin/bash
#
# ldap_stats.sh - Zabbix external check.
#
# Queries the OpenLDAP (slapd) cn=Monitor tree (back-monitor overlay) for
# basic traffic and health statistics and prints a single JSON object on
# stdout, consumed by dependent items via JSONPath preprocessing:
#
#   {
#     "operations": {"bind": N, "unbind": N, "search": N, "compare": N,
#                     "modify": N, "modrdn": N, "add": N, "delete": N,
#                     "abandon": N, "extended": N},
#     "connections_current": N,
#     "start_time": "YYYY-MM-DD HH:MM:SS"
#   }
#
# Each of the three sections comes from its own ldapsearch call and is
# included in the output only if that call succeeded and returned usable
# data - a key is simply omitted rather than set to null when its section
# is unavailable. This means a single slow/failing query does not blank out
# the others, and the corresponding dependent items' JSONPath preprocessing
# step (error handler: "Discard value") just keeps its last known value
# instead of erroring out.
#
# If parameter validation fails, ldapsearch itself is missing, or all three
# queries fail, the script prints {"error": "<reason>"} instead. Exit code
# is always 0, so the Zabbix master item never becomes "Not supported".
#
# There are no triggers on this template, so silently keeping stale values
# on a transient failure is the right tradeoff here - unlike the LDAP
# Functional Bind Check template, where a failure must be visible.
#
# Usage:
#   ldap_stats.sh <host> <port> <binddn> <password> <timeout_seconds>

set -u

HOST="${1:-}"
PORT="${2:-}"
BINDDN="${3:-}"
PASSWORD="${4:-}"
LDAP_TIMEOUT="${5:-}"

# Escapes backslashes and double quotes so a string can be safely embedded
# as a JSON string value. Applied defensively to every piece of dynamic
# text that ends up inside the JSON output, even where today's inputs are
# known-safe (e.g. fail() is currently only ever called with fixed literal
# messages) - so this doesn't silently break if that ever changes.
json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

fail() {
    printf '{"error":"%s"}\n' "$(json_escape "$1")"
    exit 0
}

# --- input validation (fail closed on anything unexpected) ---

[[ -n "$HOST" && "$HOST" =~ ^[A-Za-z0-9.:-]+$ ]] || fail "invalid or missing host parameter"
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] || fail "invalid port parameter"
(( PORT >= 1 && PORT <= 65535 )) || fail "port out of range"
[[ -n "$BINDDN" ]] || fail "bind DN parameter is empty (check {\$LDAP.BIND.DN})"
[[ -n "$PASSWORD" ]] || fail "bind password parameter is empty (check {\$LDAP.BIND.PASSWORD} for this host)"
[[ "$LDAP_TIMEOUT" =~ ^[1-9][0-9]{0,2}$ ]] || fail "invalid timeout parameter"
command -v ldapsearch >/dev/null 2>&1 || fail "ldapsearch binary not found on Zabbix server/proxy (install package ldap-utils)"

LDAP_OPTS=(-x -H "ldaps://${HOST}:${PORT}" -D "$BINDDN" -w "$PASSWORD" \
    -o "nettimeout=${LDAP_TIMEOUT}" -l "$LDAP_TIMEOUT")

PARTS=()

# --- operations per type: cn=Operations,cn=Monitor, one level down ---

OPS_OUTPUT=$(ldapsearch "${LDAP_OPTS[@]}" \
    -b "cn=Operations,cn=Monitor" -s one \
    "(objectClass=monitorOperation)" cn monitorOpCompleted 2>/dev/null)
if [[ $? -eq 0 ]]; then
    # name is only ever accepted as [A-Za-z]+ (it becomes a JSON object key)
    # and val only as [0-9]+ (it is embedded as a raw, unquoted JSON
    # number) - anything else is a record we don't recognize, so it is
    # dropped rather than risking malformed JSON. In normal operation
    # every record matches; this only ever triggers on unexpected slapd
    # output.
    OPS_JSON=$(printf '%s\n' "$OPS_OUTPUT" | awk '
        BEGIN { name=""; val=""; first=1; printf "{" }
        /^cn: / { name=$0; sub(/^cn: /,"",name) }
        /^monitorOpCompleted: / { val=$0; sub(/^monitorOpCompleted: /,"",val) }
        /^$/ {
            if (name ~ /^[A-Za-z]+$/ && val ~ /^[0-9]+$/) {
                key=tolower(name)
                if (!first) printf ","
                printf "\"%s\":%s", key, val
                first=0
            }
            name=""; val=""
        }
        END {
            if (name ~ /^[A-Za-z]+$/ && val ~ /^[0-9]+$/) {
                key=tolower(name)
                if (!first) printf ","
                printf "\"%s\":%s", key, val
            }
            printf "}"
        }
    ')
    [[ "$OPS_JSON" != "{}" ]] && PARTS+=("\"operations\":${OPS_JSON}")
fi

# --- current connection count: cn=Current,cn=Connections,cn=Monitor ---

CONN_OUTPUT=$(ldapsearch "${LDAP_OPTS[@]}" \
    -b "cn=Current,cn=Connections,cn=Monitor" -s base \
    "(objectClass=*)" monitorCounter 2>/dev/null)
if [[ $? -eq 0 ]]; then
    CONN_VAL=$(printf '%s\n' "$CONN_OUTPUT" | grep -m1 '^monitorCounter: ' | awk '{print $2}')
    [[ "$CONN_VAL" =~ ^[0-9]+$ ]] && PARTS+=("\"connections_current\":${CONN_VAL}")
fi

# --- server start time: cn=Start,cn=Time,cn=Monitor ---

TIME_OUTPUT=$(ldapsearch "${LDAP_OPTS[@]}" \
    -b "cn=Start,cn=Time,cn=Monitor" -s base \
    "(objectClass=*)" monitorTimestamp 2>/dev/null)
if [[ $? -eq 0 ]]; then
    RAW_TS=$(printf '%s\n' "$TIME_OUTPUT" | grep -m1 '^monitorTimestamp: ' | awk '{print $2}')
    FORMATTED_TS=$(printf '%s\n' "$RAW_TS" | sed -nE 's/^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})Z$/\1-\2-\3 \4:\5:\6/p')
    [[ -n "$FORMATTED_TS" ]] && PARTS+=("\"start_time\":\"${FORMATTED_TS}\"")
fi

if [[ ${#PARTS[@]} -eq 0 ]]; then
    fail "all cn=Monitor queries failed (bind, network, or timeout error)"
fi

(IFS=,; printf '{%s}\n' "${PARTS[*]}")
exit 0
