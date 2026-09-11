#!/bin/bash
# Runs the bind_stats_zabbix collector and pushes its output to Zabbix via
# zabbix_sender, using the Zabbix sender "bulk" stdin format the collector
# already emits (one "<host> <key> <value>" line per metric).
#
# Deployed via cron, e.g.:
#   */5 * * * *   cd zabbix; ./bind_stats_to_zabbix.sh
#
# Copy this script and the compiled bind_stats_zabbix binary into the same
# working directory on the BIND host (see ../README.md, section "Setup").
# Adjust the variables below per host — PSK identity/file are configured
# per Zabbix host under Host -> Encryption and differ between servers.
set -euo pipefail

ZABBIX_SERVER=fisadm.vse.cz
PSK_IDENTITY=vse.vse.cz_PSK
PSK_FILE=tls_psk_auto.secret

./bind_stats_zabbix | zabbix_sender -z "$ZABBIX_SERVER" --tls-connect psk \
    --tls-psk-identity "$PSK_IDENTITY" --tls-psk-file "$PSK_FILE" -i - > /dev/null

# On some hosts the PSK file lives under /etc/zabbix/ and is only readable
# by the zabbix system user, so zabbix_sender must run as that user instead
# of the cron job's own user. In that case replace the two lines above with:
#
#   ZABBIX_SERVER=fisadm.vse.cz
#   PSK_IDENTITY=ns-sign.vse.cz_Bb86
#   PSK_FILE=/etc/zabbix/tls_psk_auto.secret
#
#   ./bind_stats_zabbix | sudo -u zabbix zabbix_sender -z "$ZABBIX_SERVER" --tls-connect psk \
#       --tls-psk-identity "$PSK_IDENTITY" --tls-psk-file "$PSK_FILE" -i - > /dev/null
#
# (requires a sudoers rule allowing the cron job's user to run zabbix_sender
# as the zabbix user without a password)
