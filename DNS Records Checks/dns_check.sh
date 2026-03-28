#!/bin/bash
# =============================================================================
# dns_check.sh — Zabbix external check: does a DNS record exist?
# =============================================================================
# Location: ExternalScripts directory on Zabbix server/proxy
#           (as configured by ExternalScripts in zabbix_server.conf / zabbix_proxy.conf)
#
# Parameters:
#   $1  record type (a, aaaa, mx, ns, soa, txt, ptr, cname, ...)
#   $2  domain name / query target
#   $3  DNS server IP or hostname (optional; defaults to system resolver if empty)
#   $4  query timeout in seconds (optional; default: 2)
#
# Returns:
#   1   DNS server responded and returned at least one record of the requested type (OK)
#   0   DNS server did not respond, returned NXDOMAIN/SERVFAIL, or no record found (FAIL)
#
# Usage in Zabbix: dns_check.sh["{#DNS_TYPE}","{#DNS_NAME}","{$DNS.SERVER}","{$DNS.TIMEOUT}"]
# =============================================================================

DNS_TYPE="${1,,}"   # normalize to lowercase
DNS_NAME="$2"
DNS_SERVER="$3"
TIMEOUT="${4:-2}"

if [ -z "$DNS_TYPE" ] || [ -z "$DNS_NAME" ]; then
    echo 0
    exit 1
fi

# Build dig arguments:
#   +short   — output only record data, one entry per line; empty output = nothing found
#   +time    — per-query timeout in seconds
#   +tries=1 — single attempt, no retransmissions
DIG_ARGS=("+short" "+time=${TIMEOUT}" "+tries=1")

DNS_SERVER_CLEAN=$(echo "$DNS_SERVER" | tr -d '[:space:]')
[ -n "$DNS_SERVER_CLEAN" ] && DIG_ARGS+=("@${DNS_SERVER_CLEAN}")

DIG_ARGS+=("$DNS_NAME" "$DNS_TYPE")

# Run dig; capture both stdout and stderr
DIG_OUTPUT=$(dig "${DIG_ARGS[@]}" 2>&1)
DIG_RC=$?

# Non-zero exit code = timeout, network error or other fatal dig error
if [ $DIG_RC -ne 0 ]; then
    echo 0
    exit 0
fi

# With +short:
#   non-empty output = at least one record found → OK
#   empty output     = NXDOMAIN, no record of this type, or server error → FAIL
if [ -n "$(echo "$DIG_OUTPUT" | tr -d '[:space:]')" ]; then
    echo 1
else
    echo 0
fi

exit 0
