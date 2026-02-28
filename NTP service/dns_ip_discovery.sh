#!/usr/bin/env bash
set -euo pipefail

INPUT="$1"

if [[ -z "$INPUT" ]]; then
  echo '{"data":[]}'
  exit 0
fi

# --- funkce pro detekci IP ---
is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<< "$1"
  for o in $a $b $c $d; do
    (( o >= 0 && o <= 255 )) || return 1
  done
  return 0
}

is_ipv6() {
  [[ "$1" =~ : ]]
}

# --- pokud je vstup IP, vrátíme přímo ---
if is_ipv4 "$INPUT"; then
  cat <<EOF
{
  "data": [
    { "{#IP}": "$INPUT", "{#IPVER}": "4" }
  ]
}
EOF
  exit 0
fi

if is_ipv6 "$INPUT"; then
  cat <<EOF
{
  "data": [
    { "{#IP}": "$INPUT", "{#IPVER}": "6" }
  ]
}
EOF
  exit 0
fi

# --- jinak DNS lookup + validace výsledků přes is_ipv4 / is_ipv6 ---
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

while IFS= read -r line; do
  is_ipv4 "$line" && echo "{\"{#IP}\":\"$line\",\"{#IPVER}\":\"4\"}" >> "$TMP"
done < <(dig +short A "$INPUT")

while IFS= read -r line; do
  is_ipv6 "$line" && echo "{\"{#IP}\":\"$line\",\"{#IPVER}\":\"6\"}" >> "$TMP"
done < <(dig +short AAAA "$INPUT")

if [[ ! -s "$TMP" ]]; then
  echo '{"data":[]}'
  exit 0
fi

echo '{ "data": ['
paste -sd, "$TMP"
echo '] }'
