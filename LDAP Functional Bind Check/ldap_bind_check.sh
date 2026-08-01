#!/bin/bash
#
# ldap_bind_check.sh - Zabbix external check.
#
# Performs an authenticated LDAPS bind followed by a base-scope search of the
# rootDSE ("(objectClass=*)" against an empty base). This exercises both the
# bind path and the search path using real credentials, since anonymous bind
# is disabled on all monitored LDAP servers.
#
# Output: always a single line, either "OK" (success) or "FAILED: <reason>".
# Exit code: always 0, so the Zabbix item never becomes "Not supported" and
# the result reaches the trigger via the item's history instead.
#
# Usage:
#   ldap_bind_check.sh <host> <port> <binddn> <password> <timeout_seconds>
#
# The failure reason covers two different things, both surfaced in the same
# item value to make deployment problems easy to spot without SSH access to
# the Zabbix server:
#   - parameter validation errors (e.g. an empty {$LDAP.BIND.PASSWORD} macro
#     on a specific host) - reported directly by this script;
#   - actual ldapsearch failures (bad credentials, TLS/hostname mismatch,
#     network timeout, ...) - the relevant line from ldapsearch's own output
#     is extracted and reused instead of inventing a new message.
#
# Why the ldapsearch output is also checked for "# numEntries: N" rather
# than relying on the exit code alone: a successful bind followed by a
# search that (for whatever reason, e.g. an ACL issue) returns zero entries
# can still make ldapsearch exit 0. Requiring N >= 1 catches that case as a
# failure, not just "bind succeeded". This relies on ldapsearch's default
# LDIF comment output (no -L/-LL/-LLL flags), which always includes a
# "# numEntries: N" summary line after a successful search.

set -u

HOST="${1:-}"
PORT="${2:-}"
BINDDN="${3:-}"
PASSWORD="${4:-}"
LDAP_TIMEOUT="${5:-}"

fail() {
    echo "FAILED: $(sanitize_line "$1")"
    exit 0
}

# Collapses the input to a single line and strips characters that could
# corrupt or misrender a Zabbix text value (embedded newlines/carriage
# returns, other control characters), then caps the length. Applied to
# every piece of text that ends up in the item's output, even where
# today's inputs are known-safe (fail() is currently only ever called
# with fixed literal messages, and extract_reason() already returns a
# single grep-matched line) - so this doesn't silently break if that ever
# changes, and it also guards against an unexpectedly huge or malformed
# line from ldapsearch itself.
sanitize_line() {
    local max_len=300
    local clean
    clean=$(printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | tr '\n\r' '  ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ ${#clean} -gt $max_len ]]; then
        clean="${clean:0:$max_len}...(truncated)"
    fi
    printf '%s' "$clean"
}

# Picks out the single most useful line from ldapsearch's stdout+stderr
# output to use as the failure reason, without reformatting or guessing at
# a category - ldapsearch's own wording is normally clear enough.
extract_reason() {
    local out="$1"
    local reason

    # OpenLDAP puts the real underlying cause here (e.g. a TLS hostname
    # mismatch), when present it is more useful than the generic line above it.
    reason=$(printf '%s\n' "$out" | grep -m1 'additional info:' | sed 's/^[[:space:]]*//')
    [[ -n "$reason" ]] && { printf '%s\n' "$reason"; return; }

    # Otherwise the first ldap_*/TLS error line.
    reason=$(printf '%s\n' "$out" | grep -m1 -E '^(ldap_|TLS:)')
    [[ -n "$reason" ]] && { printf '%s\n' "$reason"; return; }

    # Fall back to the last non-comment, non-empty line of output.
    reason=$(printf '%s\n' "$out" | grep -v '^#' | grep -v '^[[:space:]]*$' | tail -n1)
    [[ -n "$reason" ]] && { printf '%s\n' "$reason"; return; }

    printf 'ldapsearch exited with code %s\n' "$RC"
}

# --- input validation (fail closed on anything unexpected) ---

# Hostname or IPv4/IPv6 address only.
[[ -n "$HOST" && "$HOST" =~ ^[A-Za-z0-9.:-]+$ ]] || fail "invalid or missing host parameter"

# TCP port, 1-65535.
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] || fail "invalid port parameter"
(( PORT >= 1 && PORT <= 65535 )) || fail "port out of range"

# Bind DN and password just need to be non-empty; they are passed to
# ldapsearch as single argv elements (no shell involved in that hand-off),
# so there is no command-injection risk here - only a sanity check.
[[ -n "$BINDDN" ]] || fail "bind DN parameter is empty (check {\$LDAP.BIND.DN})"
[[ -n "$PASSWORD" ]] || fail "bind password parameter is empty (check {\$LDAP.BIND.PASSWORD} for this host)"

# Timeout in seconds, small positive integer.
[[ "$LDAP_TIMEOUT" =~ ^[1-9][0-9]{0,2}$ ]] || fail "invalid timeout parameter"

# --- ensure required binary is present and executable ---

command -v ldapsearch >/dev/null 2>&1 || fail "ldapsearch binary not found on Zabbix server/proxy (install package ldap-utils)"

# --- functional test: authenticated bind + rootDSE search ---

OUTPUT=$(ldapsearch -x -H "ldaps://${HOST}:${PORT}" \
    -D "$BINDDN" -w "$PASSWORD" \
    -b "" -s base \
    -o "nettimeout=${LDAP_TIMEOUT}" \
    -l "$LDAP_TIMEOUT" \
    "(objectClass=*)" 2>&1)
RC=$?

if [[ "$RC" -eq 0 ]] && printf '%s\n' "$OUTPUT" | grep -qE '^# numEntries: [1-9][0-9]*$'; then
    echo "OK"
    exit 0
fi

if [[ "$RC" -eq 0 ]]; then
    echo "FAILED: search returned zero entries (unexpected for an authenticated rootDSE search)"
    exit 0
fi

echo "FAILED: $(sanitize_line "$(extract_reason "$OUTPUT")")"
exit 0
