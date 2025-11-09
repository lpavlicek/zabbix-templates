#!/usr/bin/env bash
# sslscan_run.sh
# args: $1 = target (host:port)
#       $2 = starttls param (maybe empty)
# prints SSLScan XML to stdout

target="$1"
starttls_param="$2"

# path to sslscan, adjust if needed
SSLSCAN_BIN="/usr/bin/sslscan"
TIMEOUT=2

# Basic safety: refuse empty target
if [ -z "$target" ]; then
  echo "Error: no target provided" >&2
  exit 2
fi

# Build command
cmd=( "$SSLSCAN_BIN" "--xml=-" "--timeout=${TIMEOUT}" "--connect-timeout=${TIMEOUT}" "--no-renegotiation" "--no-heartbleed" "--no-groups" "--no-compression" "--no-ciphersuites" "--tlsall" "--no-cipher-details" )

# append starttls param if provided and not empty
if [ -n "$starttls_param" ]; then
  cmd+=( "$starttls_param" )
fi

# append target
cmd+=( "$target" )

# Execute and forward stdout (XML)
"${cmd[@]}"
exit $?
