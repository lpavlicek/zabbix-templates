#!/bin/bash
#
# External check pro Zabbix - monitoring využití S3 úložiště (s3cmd du)
# Umístit do: /usr/lib/zabbix/externalscripts/   (chmod 755)
#
# Použití: s3_usage_check.sh <konfigurace s3cmd> [timeout položky, např. 60s | 1m | 60]
#
# s3cmd nemá parametr --timeout, proto se omezuje přes coreutils `timeout`,
# a to o MARGIN sekund kratší dobou, než je timeout položky v Zabbixu.
# Díky tomu skript stihne vrátit "ERROR: ..." dřív, než ho Zabbix zabije
# a položka se stane unsupported.
#
# Při chybě skript vypíše jeden řádek "ERROR: <popis>" a skončí s kódem 0,
# aby text chyby dorazil do Zabbixu jako hodnota položky (trigger find(),
# preprocessing "Check for error using regular expression" u závislých položek).

CONFIG_FILE="$1"
ZBX_TIMEOUT="${2:-30s}"
MARGIN=5        # rezerva vůči timeoutu Zabbixu (s); zahrnuje KILL_AFTER
KILL_AFTER=2    # když s3cmd nereaguje na SIGTERM, SIGKILL po N s

fail() {
    printf 'ERROR: %s\n' "$*"
    exit 0
}

[ -n "$CONFIG_FILE" ]  || fail "chybí parametr konfiguračního souboru"
[ -r "$CONFIG_FILE" ]  || fail "konfigurační soubor $CONFIG_FILE neexistuje nebo není čitelný"
command -v s3cmd   >/dev/null 2>&1 || fail "s3cmd nenalezen v PATH"
command -v timeout >/dev/null 2>&1 || fail "příkaz timeout (coreutils) nenalezen"

# Převod timeoutu Zabbixu (Ns / Nm / N) na sekundy
if [[ "$ZBX_TIMEOUT" =~ ^([0-9]+)([sm]?)$ ]]; then
    secs=${BASH_REMATCH[1]}
    [ "${BASH_REMATCH[2]}" = "m" ] && secs=$(( secs * 60 ))
else
    fail "neplatný formát timeoutu '$ZBX_TIMEOUT' (očekáváno Ns, Nm nebo N)"
fi

limit=$(( secs - MARGIN - KILL_AFTER ))
[ "$limit" -ge 3 ] || fail "timeout položky $ZBX_TIMEOUT je příliš krátký (minimum $(( MARGIN + KILL_AFTER + 3 ))s)"

errfile=$(mktemp) || fail "mktemp selhal"
trap 'rm -f "$errfile"' EXIT

output=$(timeout -k "$KILL_AFTER" "$limit" s3cmd du -c "$CONFIG_FILE" 2>"$errfile")
rc=$?

case $rc in
    0)
        ;;
    124|137)
        fail "s3cmd neodpověděl do ${limit}s (timeout, úložiště nedostupné nebo příliš pomalé)"
        ;;
    *)
        msg=$(grep -m1 -v '^[[:space:]]*$' "$errfile" | sed -e 's/^ERROR:[[:space:]]*//')
        fail "s3cmd skončil s kódem $rc${msg:+: $msg}"
        ;;
esac

# Kontrola, že výstup má očekávaný formát (řádek "<bytes> Total")
grep -Eq '^[[:space:]]*[0-9]+[[:space:]]+Total[[:space:]]*$' <<<"$output" \
    || fail "neočekávaný výstup s3cmd du (chybí řádek Total)"

printf '%s\n' "$output"
