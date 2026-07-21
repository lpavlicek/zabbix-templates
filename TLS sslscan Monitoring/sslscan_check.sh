#!/usr/bin/env bash
#
# sslscan_check.sh
# Zabbix external check wrapper for sslscan.
#
# Arguments:
#   $1 = target          (format: host:port)
#   $2 = starttls option  (optional, e.g. --starttls-smtp)
#
# Prints sslscan XML output to stdout.

set -u

readonly SSLSCAN_BIN="/usr/bin/sslscan"
readonly TIMEOUT=2

target="${1:-}"
starttls_param="${2:-}"

# Refuse empty target
if [ -z "$target" ]; then
  echo "Error: no target provided" >&2
  exit 2
fi

# Validate target format: hostname/IP + mandatory port.
# The leading character must NOT be a dash, so the value can never be
# mistaken for an sslscan option (argument injection protection).
if ! [[ "$target" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*:[0-9]{1,5}$ ]]; then
  echo "Error: invalid target format, expected host:port" >&2
  exit 2
fi

# Validate starttls option against a fixed allow-list. Without this check
# an attacker-controlled macro value could inject arbitrary sslscan flags
# (e.g. overriding --xml=- to write to a file instead of stdout).
if [ -n "$starttls_param" ]; then
  case "$starttls_param" in
    --starttls-ftp|--starttls-imap|--starttls-irc|--starttls-ldap|\
    --starttls-mysql|--starttls-pop3|--starttls-psql|--starttls-smtp|--starttls-xmpp)
      ;;
    *)
      echo "Error: unsupported starttls option: $starttls_param" >&2
      exit 2
      ;;
  esac
fi

# Make sure the binary actually exists before trying to run it
if [ ! -x "$SSLSCAN_BIN" ]; then
  echo "Error: sslscan binary not found or not executable at $SSLSCAN_BIN" >&2
  exit 3
fi

# Build command as an array - arguments are passed to exec() directly,
# never through a shell, so shell metacharacters in $target cannot be
# interpreted (no injection via ;, |, $(), backticks, etc.)
cmd=( "$SSLSCAN_BIN" "--xml=-" "--timeout=${TIMEOUT}" "--connect-timeout=${TIMEOUT}" \
      "--no-renegotiation" "--no-heartbleed" "--no-groups" "--no-compression" \
      "--no-ciphersuites" "--tlsall" "--no-cipher-details" )

if [ -n "$starttls_param" ]; then
  cmd+=( "$starttls_param" )
fi

cmd+=( "$target" )

# Execute and forward stdout (XML)
"${cmd[@]}"
exit $?
