#!/bin/bash
#
# ldap_repl_lag.sh - Zabbix external check.
#
# Measures OpenLDAP syncrepl replication lag by comparing the contextCSN of
# a consumer (this replica) against the contextCSN of the provider.
#
# contextCSN only exists as an attribute of a database's own suffix entry -
# not at an arbitrary replicated subtree - so the replica and provider are
# queried at their own respective database suffixes, which may differ (as
# they do here: the provider's database suffix is dc=cz, of which
# dc=vse,dc=cz - the replicas' own suffix - is the only subtree and the
# only thing that ever changes there, confirmed with the LDAP administrator;
# without that guarantee, comparing across two different suffixes would not
# be a reliable lag measurement, since contextCSN reflects the latest
# change anywhere in the whole database, not just within a search filter).
#
# The replica is queried FIRST and the provider SECOND, deliberately: a
# consumer's contextCSN can never be newer than what the provider had
# already committed at some earlier point in time, so querying the
# provider strictly after the replica guarantees lag_seconds >= 0 - it
# cannot go negative purely from the two queries' timing/ordering.
#
# Output: {"lag_seconds": N, "replica_csn_time": "...", "provider_csn_time": "..."}
# or {"error": "<reason>"} if either query or CSN parsing fails. There is
# no partial-success case here (unlike ldap_stats.sh) - a lag value needs
# both endpoints, so any failure is total. Exit code is always 0, so the
# Zabbix master item never becomes "Not supported".
#
# Usage:
#   ldap_repl_lag.sh <replica_host> <port> <provider_host> <replica_base> <provider_base> <binddn> <password> <timeout_seconds>

set -u

REPLICA_HOST="${1:-}"
PORT="${2:-}"
PROVIDER_HOST="${3:-}"
REPLICA_BASE="${4:-}"
PROVIDER_BASE="${5:-}"
BINDDN="${6:-}"
PASSWORD="${7:-}"
LDAP_TIMEOUT="${8:-}"

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

fail() {
    printf '{"error":"%s"}\n' "$(json_escape "$1")"
    exit 0
}

# --- input validation (fail closed on anything unexpected) ---

[[ -n "$REPLICA_HOST" && "$REPLICA_HOST" =~ ^[A-Za-z0-9.:-]+$ ]] || fail "invalid or missing replica host parameter"
[[ -n "$PROVIDER_HOST" && "$PROVIDER_HOST" =~ ^[A-Za-z0-9.:-]+$ ]] || fail "invalid or missing provider host parameter"
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] || fail "invalid port parameter"
(( PORT >= 1 && PORT <= 65535 )) || fail "port out of range"
[[ -n "$REPLICA_BASE" ]] || fail "replica base DN parameter is empty (check {\$LDAP.BASE.DN})"
[[ -n "$PROVIDER_BASE" ]] || fail "provider base DN parameter is empty (check {\$LDAP.REPL.PROVIDER.BASE})"
[[ -n "$BINDDN" ]] || fail "bind DN parameter is empty (check {\$LDAP.BIND.DN})"
[[ -n "$PASSWORD" ]] || fail "bind password parameter is empty (check {\$LDAP.BIND.PASSWORD} for this host)"
[[ "$LDAP_TIMEOUT" =~ ^[1-9][0-9]{0,2}$ ]] || fail "invalid timeout parameter"
command -v ldapsearch >/dev/null 2>&1 || fail "ldapsearch binary not found on Zabbix server/proxy (install package ldap-utils)"
command -v date >/dev/null 2>&1 || fail "date binary not found on Zabbix server/proxy"

# Extracts the epoch seconds encoded in a contextCSN value
# ("YYYYMMDDHHMMSS.ffffffZ#count#sid#mod"). Prints nothing if the value is
# missing or not in the expected format. Requires GNU date (-d "@epoch"),
# which is standard on Debian/Ubuntu.
csn_to_epoch() {
    local csn="$1"
    local ts formatted
    ts=$(printf '%s\n' "$csn" | sed -nE 's/^([0-9]{14})\.[0-9]+Z#.*$/\1/p')
    [[ -z "$ts" ]] && return
    formatted=$(printf '%s\n' "$ts" | sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})$/\1-\2-\3 \4:\5:\6/')
    date -u -d "$formatted" +%s 2>/dev/null
}

LDAP_OPTS_COMMON=(-x -D "$BINDDN" -w "$PASSWORD" -o "nettimeout=${LDAP_TIMEOUT}" -l "$LDAP_TIMEOUT")

# --- replica's own contextCSN (queried first, see comment above) ---

REPLICA_OUTPUT=$(ldapsearch "${LDAP_OPTS_COMMON[@]}" \
    -H "ldaps://${REPLICA_HOST}:${PORT}" \
    -b "$REPLICA_BASE" -s base \
    "(objectClass=*)" contextCSN 2>/dev/null)
[[ $? -eq 0 ]] || fail "could not read contextCSN from replica ${REPLICA_HOST}"

REPLICA_CSN=$(printf '%s\n' "$REPLICA_OUTPUT" | grep -m1 '^contextCSN: ' | awk '{print $2}')
[[ -n "$REPLICA_CSN" ]] || fail "contextCSN attribute missing on replica ${REPLICA_HOST} (base ${REPLICA_BASE})"

REPLICA_EPOCH=$(csn_to_epoch "$REPLICA_CSN")
[[ -n "$REPLICA_EPOCH" ]] || fail "could not parse replica contextCSN value"

# --- provider's contextCSN (queried second, deliberately) ---

PROVIDER_OUTPUT=$(ldapsearch "${LDAP_OPTS_COMMON[@]}" \
    -H "ldaps://${PROVIDER_HOST}:${PORT}" \
    -b "$PROVIDER_BASE" -s base \
    "(objectClass=*)" contextCSN 2>/dev/null)
[[ $? -eq 0 ]] || fail "could not read contextCSN from provider ${PROVIDER_HOST}"

PROVIDER_CSN=$(printf '%s\n' "$PROVIDER_OUTPUT" | grep -m1 '^contextCSN: ' | awk '{print $2}')
[[ -n "$PROVIDER_CSN" ]] || fail "contextCSN attribute missing on provider ${PROVIDER_HOST} (base ${PROVIDER_BASE})"

PROVIDER_EPOCH=$(csn_to_epoch "$PROVIDER_CSN")
[[ -n "$PROVIDER_EPOCH" ]] || fail "could not parse provider contextCSN value"

LAG=$(( PROVIDER_EPOCH - REPLICA_EPOCH ))
(( LAG < 0 )) && LAG=0

printf '{"lag_seconds":%d,"replica_csn_time":"%s","provider_csn_time":"%s"}\n' \
    "$LAG" \
    "$(json_escape "$(date -u -d "@$REPLICA_EPOCH" '+%Y-%m-%d %H:%M:%S')")" \
    "$(json_escape "$(date -u -d "@$PROVIDER_EPOCH" '+%Y-%m-%d %H:%M:%S')")"
exit 0
