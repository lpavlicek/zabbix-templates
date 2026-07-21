#!/usr/bin/env bash
#
# sslscan_check.sh
# Zabbix external check wrapper for sslscan.
#
# Arguments:
#   $1 = target           (format: host:port, or just host - defaults to port 443)
#   $2 = starttls option  (optional, e.g. --starttls-smtp)
#
# IMPORTANT: this script always prints a valid sslscan-style XML document
# to stdout and exits 0 - even when it rejects the input itself. This
# mirrors how sslscan reports its own connection errors (<error> node,
# exit 0) and lets the template's "SSL Scan Error" dependent item
# (XPath /document/error/text()) pick the message up normally. If we
# instead wrote to stderr and exited non-zero, the master item would
# become "Not supported" and none of the dependent items would receive
# a new value at all - they would keep showing stale, unrelated data.

set -u

readonly SSLSCAN_BIN="/usr/bin/sslscan"
readonly TIMEOUT=2

target="${1:-}"
starttls_param="${2:-}"

# Print a minimal, valid sslscan-style XML document carrying an error
# message on stdout, then exit successfully (0) so Zabbix treats this as
# a normal, supported check result.
emit_error() {
  local msg="$1"
  msg="${msg//&/&amp;}"
  msg="${msg//</&lt;}"
  msg="${msg//>/&gt;}"
  printf '<?xml version="1.0"?>\n<document title="SSLScan Results" version="0.0.0" web="https://github.com/rbsec/sslscan">\n<error>%s</error>\n</document>\n' "$msg"
  exit 0
}

# Refuse empty target
if [ -z "$target" ]; then
  emit_error "No target provided"
fi

# Validate target format: hostname/IP, with an optional ":port" suffix.
# The leading character must NOT be a dash, so the value can never be
# mistaken for an sslscan option (argument injection protection).
# If no port is given, default to 443 (standard HTTPS).
if [[ "$target" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*:[0-9]{1,5}$ ]]; then
  : # host:port already in the expected form
elif [[ "$target" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  target="${target}:443"
else
  emit_error "Invalid target format, expected host or host:port"
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
      emit_error "Unsupported starttls option: $starttls_param"
      ;;
  esac
fi

# Make sure the binary actually exists before trying to run it
if [ ! -x "$SSLSCAN_BIN" ]; then
  emit_error "sslscan binary not found or not executable at $SSLSCAN_BIN"
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

# Execute and forward stdout (XML). sslscan itself already emits a valid
# <error> node with exit 0 on its own connection failures (DNS, timeout,
# handshake), so this final call is left untouched.
"${cmd[@]}"
exit $?
