#!/bin/bash
#
# zswap_stats.sh
#
# Reads zswap statistics from debugfs and the kernel page size, and prints
# them as a single JSON object on stdout for the "Zswap by Zabbix agent"
# Zabbix template (item key: zswap.stats).
#
# /sys/kernel/debug/zswap/* is not readable by an unprivileged user (the
# debugfs mount itself is typically 0700 root:root), so this script must
# run as root. It is invoked via sudo from a Zabbix agent UserParameter -
# see README.md for the sudoers rule and UserParameter configuration.
#
# On any read failure, the script still prints valid JSON with a non-empty
# "error" field and exits 0, so the Zabbix master item stays "supported"
# and the failure propagates to the dependent "Zswap: stats collection
# error" item / "Zswap: error collecting statistics" trigger instead of
# just making the item go stale.

set -u

DEBUGFS_DIR="/sys/kernel/debug/zswap"
ERROR=""

read_stat() {
    local file="$1"
    local path="${DEBUGFS_DIR}/${file}"
    if [[ -r "$path" ]]; then
        tr -d '\n' < "$path" 2>/dev/null
    fi
}

POOL_TOTAL_SIZE=$(read_stat "pool_total_size")
STORED_PAGES=$(read_stat "stored_pages")
WRITTEN_BACK_PAGES=$(read_stat "written_back_pages")
POOL_LIMIT_HIT=$(read_stat "pool_limit_hit")
PAGE_SIZE=$(getconf PAGESIZE 2>/dev/null)

for name in POOL_TOTAL_SIZE STORED_PAGES WRITTEN_BACK_PAGES POOL_LIMIT_HIT PAGE_SIZE; do
    val="${!name}"
    if [[ -z "$val" || ! "$val" =~ ^[0-9]+$ ]]; then
        ERROR="Failed to read or parse ${name} from ${DEBUGFS_DIR} (check debugfs mount, kernel zswap support, and sudo permissions)"
        POOL_TOTAL_SIZE=0
        STORED_PAGES=0
        WRITTEN_BACK_PAGES=0
        POOL_LIMIT_HIT=0
        PAGE_SIZE=${PAGE_SIZE:-4096}
        break
    fi
done

printf '{"pool_total_size":%s,"stored_pages":%s,"written_back_pages":%s,"pool_limit_hit":%s,"page_size":%s,"error":"%s"}\n' \
    "$POOL_TOTAL_SIZE" "$STORED_PAGES" "$WRITTEN_BACK_PAGES" "$POOL_LIMIT_HIT" "$PAGE_SIZE" "$ERROR"

exit 0
