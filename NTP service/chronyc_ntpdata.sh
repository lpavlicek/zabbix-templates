#!/usr/bin/env bash
# chronyc_ntpdata.sh
# args: $1 = target (host:port)
# prints chronyc ntpdata to stdout

target="$1"

# path to sudo, adjust if needed
SUDO_BIN="/usr/bin/sudo"
# path to chronyc, adjust if needed
CHRONYC_BIN="/usr/bin/chronyc"

# Basic safety: refuse empty target
if [ -z "$target" ]; then
  echo "Error: no target provided" >&2
  exit 2
fi

# Build command
cmd=( "$SUDO_BIN" "$CHRONYC_BIN" "ntpdata" "$target" )

# Execute and forward stdout
"${cmd[@]}"
exit $?
