#!/usr/bin/env bash
# http_headers_curl.sh
# External check for Zabbix (curl-based) - returns response headers + metadata lines
#
# Usage:
#   http_headers_curl.sh <url> [<method>] [<follow>]
#   <method> : HEAD (default) or GET
#   <follow> : 1 (follow redirects - default) or 0 (no follow)
#
# Output:
#   - response headers (one per řádek)
#   - ZBX-HTTP-VERSION: <http_version>
#   - ZBX-HTTP-CODE: <http_status_code>
#   - ZBX-ERROR: <description>    (jen pokud nastala chyba)
#
set -uo pipefail

CURL_BIN=/usr/bin/curl
TIMEOUT=3
CONNECT_TIMEOUT=2

if [[ ! -x "$CURL_BIN" ]]; then
  echo "ZBX-ERROR: curl not found at $CURL_BIN"
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "ZBX-ERROR: missing URL"
  exit 0
fi

URL="$1"
MODE="${2:-HEAD}"
FOLLOW="${3:-1}"

# sanity
if [[ -z "$URL" ]]; then
  echo "ZBX-ERROR: empty URL"
  exit 0
fi

# Prepare curl options
CURL_OPTS=( "--max-time" "$TIMEOUT" "--silent" "--show-error" "--connect-timeout" "$CONNECT_TIMEOUT" )
if [[ "$FOLLOW" == "1" || "$FOLLOW" == "true" ]]; then
  CURL_OPTS+=( "--location" "--max-redirs" "3" )
fi
if [[ "$MODE" == "HEAD" ]]; then
  CURL_OPTS+=( "--head" )
fi

# Temporary files
TMPH=$(mktemp) || { echo "ZBX-ERROR: cannot create tmp file"; exit 0; }
ERRF=$(mktemp) || { rm -f "$TMPH"; echo "ZBX-ERROR: cannot create tmp file"; exit 0; }
trap 'rm -f "$TMPH" "$ERRF"' EXIT

# Run curl: capture headers to $TMPH, capture short status string to STATUS, stderr to ERRF
# We use -D to save headers, -o /dev/null to discard body, -X to set method.
STATUS=$("$CURL_BIN" "${CURL_OPTS[@]}" -D "$TMPH" -o /dev/null -w '%{http_version} %{http_code} %{url_effective}' "$URL" 2> "$ERRF")
CURL_EXIT=$?

# Read possible stderr content
ERRMSG=$(cat "$ERRF" | tr '\n' ' ' | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Parse STATUS into HTTP_VER and HTTP_CODE (if available)
HTTP_VER=""
HTTP_CODE="0"
HTTP_URL_EFFECTIVE=""
if [[ -n "$STATUS" ]]; then
  # STATUS expected like: "2 200" or "1.1 200"
  HTTP_VER=$(echo "$STATUS" | awk '{print $1}')
  HTTP_CODE=$(echo "$STATUS" | awk '{print $2}')
  HTTP_URL_EFFECTIVE=$(echo "$STATUS" | awk '{print $3}')
fi

# Output headers (if any)
if [[ -s "$TMPH" ]]; then
  # curl writes status-line and header lines to the -D file; output them as-is
  cat "$TMPH" | awk '
    /^HTTP\// {block_index++}
    {blocks[block_index] = blocks[block_index] $0 "\n"}
    END {print blocks[block_index]} '
fi

# Metadata lines
echo "ZBX-HTTP-VERSION: ${HTTP_VER}"
echo "ZBX-HTTP-CODE: ${HTTP_CODE}"
echo "ZBX-HTTP-URL-EFFECTIVE: ${HTTP_URL_EFFECTIVE}"

# Report any curl-level error (non-zero exit) or stderr content
if [[ $CURL_EXIT -ne 0 ]]; then
  echo "ZBX-ERROR: curl exited with code ${CURL_EXIT}"
  if [[ -n "$ERRMSG" ]]; then
    echo "ZBX-ERROR-DETAIL: ${ERRMSG}"
  fi
else
  # Even if curl exit code = 0, there can be stderr content - show it as detail
  if [[ -n "$ERRMSG" ]]; then
    echo "ZBX-ERROR-DETAIL: ${ERRMSG}"
  fi
fi

# Always exit 0 so Zabbix stores the returned text
exit 0
