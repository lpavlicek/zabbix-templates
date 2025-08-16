#!/bin/bash

# External script pro Zabbix - monitoring S3 úložištì
# Umístit do: /usr/lib/zabbix/externalscripts/
# Nastavit oprávnìní: chmod +x s3_usage_check.sh

CONFIG_FILE="$1"

# Kontrola parametru
if [ -z "$CONFIG_FILE" ]; then
    echo "ERROR: Chybí parametr konfiguraèního souboru"
    exit 1
fi

# Kontrola existence konfiguraèního souboru
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Konfiguraèní soubor $CONFIG_FILE neexistuje"
    exit 1
fi

# Spuštìní s3cmd du s konfiguraèním souborem
s3cmd du -c "$CONFIG_FILE" 2>/dev/null || {
    echo "ERROR: Chyba pøi spouštìní s3cmd"
    exit 1
}

