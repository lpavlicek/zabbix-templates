#!/bin/bash

# External script pro Zabbix - monitoring S3 �lo�i�t�
# Um�stit do: /usr/lib/zabbix/externalscripts/
# Nastavit opr�vn�n�: chmod +x s3_usage_check.sh

CONFIG_FILE="$1"

# Kontrola parametru
if [ -z "$CONFIG_FILE" ]; then
    echo "ERROR: Chyb� parametr konfigura�n�ho souboru"
    exit 1
fi

# Kontrola existence konfigura�n�ho souboru
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Konfigura�n� soubor $CONFIG_FILE neexistuje"
    exit 1
fi

# Spu�t�n� s3cmd du s konfigura�n�m souborem
s3cmd du -c "$CONFIG_FILE" 2>/dev/null || {
    echo "ERROR: Chyba p�i spou�t�n� s3cmd"
    exit 1
}

