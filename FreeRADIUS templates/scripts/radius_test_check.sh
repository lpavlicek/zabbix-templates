#!/bin/bash
#
# radius_test_check.sh
#
# Wraps the existing RADIUS/EAPOL functional test script (check_fast.sh) for
# Zabbix. check_fast.sh is run as another user via sudo and prints one result
# line per test, e.g.:
#
#   OK:    Access-Accept    vpn/accept_test99_p:18122.conf
#   OK:    SUCCESS 101      eduroam/accept-test-cesnet-cz-peap-mschapv2_cui.conf
#      CUI 'p/HeKPrjDtRy9a6yNnE8E5WiyYk' == 'p/HeKPrjDtRy9a6yNnE8E5WiyYk'
#
# Lines starting with "OK:" or "BAD:" are results (test name = last
# whitespace-separated token); indented "CUI ..." lines are ignored.
#
# Usage:
#   radius_test_check.sh raw         - run the tests, print raw output
#   radius_test_check.sh discovery   - run the tests, print Zabbix LLD JSON
#
# Dependencies: bash, sudo configured to allow the zabbix user to run
# check_fast.sh as RUN_AS_USER without a password, e.g. in
# /etc/sudoers.d/zabbix-radius-test:
#   zabbix ALL=(pavlicek) NOPASSWD: /home/pavlicek/radius-test/check_fast.sh

set -u
LC_ALL=C
export LC_ALL

RUN_AS_USER="pavlicek"
TEST_SCRIPT="/home/pavlicek/radius-test/check_fast.sh"
TIMEOUT_SEC=15

run_tests() {
    local out rc
    out=$(timeout "$TIMEOUT_SEC" sudo -A -u "$RUN_AS_USER" "$TEST_SCRIPT" 2>&1)
    rc=$?

    if [ $rc -eq 124 ]; then
        echo "ZBX_NOTSUPPORTED: check_fast.sh timed out after ${TIMEOUT_SEC}s"
        return 1
    fi

    # If the output contains at least one real result line, treat it as valid
    # test data regardless of the exit code (some versions of check_fast.sh may
    # exit non-zero when a test fails, which is not itself a monitoring error).
    if printf '%s\n' "$out" | grep -qE '^(OK|BAD):'; then
        printf '%s\n' "$out"
        return 0
    fi

    # No parseable result lines - sudo or the script itself failed outright
    # (e.g. "sudo: ...: command not found", "sudo: no askpass program
    # specified, try setting SUDO_ASKPASS"). Surface the literal error text so
    # it's possible to tell the failure modes apart, flattened to one line.
    local flat
    flat=$(printf '%s' "$out" | tr '\n' ' ' | sed 's/ *$//')
    if [ -z "$flat" ]; then
        echo "ZBX_NOTSUPPORTED: check_fast.sh produced no output (exit code $rc)"
    else
        echo "ZBX_NOTSUPPORTED: sudo/check_fast.sh failed (exit code $rc): $flat"
    fi
    return 1
}

do_raw() {
    run_tests
}

# Escape a string for safe embedding as a JSON string value.
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

do_discovery() {
    local out
    out=$(run_tests) || { printf '%s\n' "$out"; return 1; }

    printf '{\n  "data": [\n'
    local first=1 line testname
    while IFS= read -r line; do
        case "$line" in
            OK:*|BAD:*)
                testname=$(printf '%s\n' "$line" | awk '{print $NF}')
                [ -z "$testname" ] && continue
                [ "$first" -eq 0 ] && printf ',\n'
                first=0
                printf '    {"{#TESTNAME}":"%s"}' "$(json_escape "$testname")"
                ;;
            *) : ;;  # ignore CUI lines and anything else
        esac
    done <<< "$out"
    printf '\n  ]\n}\n'
}

case "${1:-}" in
    raw)       do_raw ;;
    discovery) do_discovery ;;
    *) echo "Usage: $0 raw | discovery" >&2; exit 1 ;;
esac
