#!/bin/bash
# =============================================================================
# zabbix_ollama.sh - Zabbix UserParameter wrapper for Ollama monitoring
# =============================================================================
# Version: 1.1
# Usage:   zabbix_ollama.sh <action> [port] [model] [keep_alive]
#
# Actions:
#   version      - Get Ollama version (JSON)
#   models       - List available models (JSON)
#   loaded       - List loaded models (JSON)
#   probe        - Run inference probe and return response (JSON)
#
# Examples:
#   zabbix_ollama.sh version 11434
#   zabbix_ollama.sh models  11434
#   zabbix_ollama.sh loaded  11434
#   zabbix_ollama.sh probe   11434 gemma3:270m 30m
#
# HTTP error handling:
#   On non-200 responses the script returns a JSON object, e.g.:
#     {"error":"http_error","http_status":503}
#   This allows Zabbix to detect and trigger on HTTP-level errors separately
#   from network-level errors (curl_failed) and application errors from Ollama.
#
#   Known Ollama HTTP status codes:
#     200  OK
#     400  Bad request (malformed JSON payload)
#     404  Model not found (probe only)
#     500  Internal server error
#     503  Service unavailable / overloaded
# =============================================================================

# --- Configuration ---
readonly CURL_TIMEOUT=3           # max seconds for curl (connect + transfer)
readonly CURL_CONNECT_TIMEOUT=2   # max seconds for TCP connect
readonly OLLAMA_HOST="localhost"

# --- Input validation ---

# Action: only allow known values
ACTION="${1}"
case "${ACTION}" in
    version|models|loaded|probe) ;;
    *)
        echo '{"error":"invalid_action"}'
        exit 1
        ;;
esac

# Port: digits only, range 1-65535
PORT="${2:-11434}"
if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
    echo '{"error":"invalid_port"}'
    exit 1
fi

# Model (only needed for probe): allow alphanumeric, colon, dot, dash, underscore, slash
# Examples: gemma3:270m, llama3.2:latest, mistral, nomic-embed-text, namespace/model:tag
MODEL="${3:-}"
if [[ "${ACTION}" == "probe" ]]; then
    if [[ -z "${MODEL}" ]]; then
        echo '{"error":"missing_model"}'
        exit 1
    fi
    if ! [[ "${MODEL}" =~ ^[a-zA-Z0-9:._/-]+$ ]]; then
        echo '{"error":"invalid_model"}'
        exit 1
    fi
fi

# Keep-alive: digits optionally followed by m/h/s, or -1 (permanent)
KEEP_ALIVE="${4:-30m}"
if ! [[ "${KEEP_ALIVE}" =~ ^(-1|[0-9]+(s|m|h)?)$ ]]; then
    echo '{"error":"invalid_keep_alive"}'
    exit 1
fi

# --- Build base URL ---
BASE_URL="http://${OLLAMA_HOST}:${PORT}"

# --- Temporary file for response body ---
# curl writes the body here; we read HTTP status code separately via --write-out.
# mktemp ensures a unique file per invocation (Zabbix may run checks in parallel).
TMPFILE=$(mktemp /tmp/zabbix_ollama_XXXXXX)
# shellcheck disable=SC2064
trap "rm -f '${TMPFILE}'" EXIT

# --- Common curl options ---
# --silent          suppress progress meter and error messages
# --output TMPFILE  write response body to temp file, not stdout
# --write-out       print only the HTTP status code to stdout
CURL_OPTS=(
    --silent
    --max-time        "${CURL_TIMEOUT}"
    --connect-timeout "${CURL_CONNECT_TIMEOUT}"
    --header          "Content-Type: application/json"
    --output          "${TMPFILE}"
    --write-out       "%{http_code}"
)

# --- Execute action ---
case "${ACTION}" in

    version)
        HTTP_STATUS=$(curl "${CURL_OPTS[@]}" "${BASE_URL}/api/version")
        CURL_RC=$?
        ;;

    models)
        HTTP_STATUS=$(curl "${CURL_OPTS[@]}" "${BASE_URL}/api/tags")
        CURL_RC=$?
        ;;

    loaded)
        HTTP_STATUS=$(curl "${CURL_OPTS[@]}" "${BASE_URL}/api/ps")
        CURL_RC=$?
        ;;

    probe)
        PAYLOAD=$(printf '{"model":"%s","prompt":"1+1","stream":false,"keep_alive":"%s"}' \
                  "${MODEL}" "${KEEP_ALIVE}")
        HTTP_STATUS=$(curl "${CURL_OPTS[@]}" \
                           --request POST \
                           --data   "${PAYLOAD}" \
                           "${BASE_URL}/api/generate")
        CURL_RC=$?
        ;;

esac

# --- Handle curl errors (timeout, connection refused, etc.) ---
# curl exit codes: 6=cannot resolve, 7=failed to connect, 28=timeout
# On curl error, HTTP_STATUS may be empty or "000"; we do not trust it.
if [[ ${CURL_RC} -ne 0 ]]; then
    echo "{\"error\":\"curl_failed\",\"curl_exit_code\":${CURL_RC}}"
    exit 0   # exit 0 so Zabbix receives the value and can trigger on it
fi

# --- Handle non-200 HTTP status codes ---
# curl succeeded at the transport level but Ollama returned an error status.
# We include the response body when available because Ollama often puts a
# human-readable reason in the body even on error responses.
if [[ "${HTTP_STATUS}" != "200" ]]; then
    BODY=$(cat "${TMPFILE}")
    # Keep the body only if it looks like JSON (starts with { or [),
    # otherwise omit it to avoid injecting unexpected content into the output.
    FIRST_CHAR="${BODY:0:1}"
    if [[ "${FIRST_CHAR}" == "{" || "${FIRST_CHAR}" == "[" ]]; then
        echo "{\"error\":\"http_error\",\"http_status\":${HTTP_STATUS},\"body\":${BODY}}"
    else
        echo "{\"error\":\"http_error\",\"http_status\":${HTTP_STATUS}}"
    fi
    exit 0
fi

# --- Read body from temp file ---
RESPONSE=$(cat "${TMPFILE}")

# --- Handle empty response body (HTTP 200 but no content) ---
if [[ -z "${RESPONSE}" ]]; then
    echo '{"error":"empty_response"}'
    exit 0
fi

# --- Validate that response body is JSON (basic check: starts with { or [) ---
FIRST_CHAR="${RESPONSE:0:1}"
if [[ "${FIRST_CHAR}" != "{" && "${FIRST_CHAR}" != "[" ]]; then
    echo '{"error":"invalid_json"}'
    exit 0
fi

echo "${RESPONSE}"
exit 0
