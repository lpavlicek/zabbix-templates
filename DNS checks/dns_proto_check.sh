#!/bin/bash
# =============================================================================
# dns_proto_check.sh — Zabbix external check: DNS protocol response time
# =============================================================================
# Location: ExternalScripts directory on Zabbix server/proxy
#           (as configured by ExternalScripts in zabbix_server.conf / zabbix_proxy.conf)
#
# Parameters:
#   $1  protocol: udp | tcp | tls | https | quic
#   $2  DNS server IP or hostname (host interface address, {HOST.CONN})
#   $3  query name (domain to resolve, e.g. www.vse.cz)
#   $4  query timeout in seconds (optional; default: 2)
#
# Returns:
#   >=0   response time in milliseconds (FLOAT) — protocol supported, query succeeded
#   -1    query failed or protocol not supported (no timing line in kdig output)
#
# Usage in Zabbix:
#   dns_proto_check.sh["{#DNS_PROTO}","{HOST.CONN}","{$DNS.PROTO.QUERY}","{$DNS.TIMEOUT}"]
#
# Requires: kdig (knot-dnsutils / knot-utils package)
# =============================================================================

PROTO="${1,,}"    # normalize to lowercase
SERVER="$2"
QUERY="${3:-www.vse.cz}"
TIMEOUT="${4:-2}"

if [ -z "$PROTO" ] || [ -z "$SERVER" ]; then
    echo -1
    exit 1
fi

# Map protocol name to kdig argument.
# udp: +notcp explicitly disables TCP fallback on truncated responses.
# All other protocolss use the matching +<proto> flag.
case "$PROTO" in
    udp)   PROTO_ARG="+notcp" ;;
    tcp)   PROTO_ARG="+tcp" ;;
    tls)   PROTO_ARG="+tls" ;;
    https) PROTO_ARG="+https" ;;
    quic)  PROTO_ARG="+quic" ;;
    *)
        echo -1
        exit 1
        ;;
esac

# Build kdig command.
# +time    — query timeout in seconds (integer; minimum 1)
# +retry=0 — single attempt, no retransmissions
# +norec   — no recursion flag; we test transport, not resolver behaviour
# -t A     — query type A (fixed; we test protocol, not record type)
KDIG_ARGS=("+time=${TIMEOUT}" "+retry=0" "-t" "A" "@${SERVER}" "${QUERY}")
[ -n "$PROTO_ARG" ] && KDIG_ARGS=("$PROTO_ARG" "${KDIG_ARGS[@]}")

OUTPUT=$(kdig "${KDIG_ARGS[@]}" 2>&1)
RC=$?

# kdig prints a timing line on success:
#   ;; From 146.102.42.121@53(TCP) in 1.2 ms
#   ;; From 2001:718:1e02:41::11@53(UDP) in 0.5 ms
#
# This line is absent when the protocol is not supported,
# the connection is refused, or a timeout occurs.
#
# Extract the numeric value (integer or decimal) before " ms"
TIME_MS=$(echo "$OUTPUT" | grep -oP '(?<=\bin )\d+(\.\d+)?(?= ms)')

if [ -z "$TIME_MS" ]; then
    echo -1
else
    echo "$TIME_MS"
fi

exit 0

