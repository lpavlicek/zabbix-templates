# FreeRADIUS Service Base & Statistics — Zabbix templates

Two related Zabbix templates for monitoring a FreeRADIUS 3.2 server, kept
together in this README because they are normally deployed on the same
hosts and share some setup steps.

| Template | What it covers |
|---|---|
| **FreeRADIUS Service Base by Zabbix agent 2** | systemd service state, UDP/TCP listener availability, `radiusd` process CPU/memory, and functional RADIUS/EAPOL response tests. |
| **FreeRADIUS Statistics by Zabbix agent** | Live traffic counters and internal state from the FreeRADIUS status server (`radclient status`), both server-wide and per RADIUS client (NAS). |

Unlike the [Certificate Expiry](../certificate-expiry/README.md) template,
both of these are FreeRADIUS-specific.

## Files

| File | Purpose |
|---|---|
| `FreeRADIUS Service Base by Zabbix agent 2 template.yaml` | Template: service/process/network + functional tests. |
| `FreeRADIUS Statistics by Zabbix agent template.yaml` | Template: live statistics, global and per-client. |
| `scripts/freeradius_stats.sh` | Helper for the Statistics template (queries the FreeRADIUS status server). |
| `scripts/radius_test_check.sh` | Helper for the functional-test part of the Service Base template. |

## Requirements

- Zabbix 7.4 (Statistics template's `timeout` field on individual items
  requires Zabbix 6.4+; not tested on older versions).
- Zabbix agent 2 for the Service Base template (uses the native
  `systemd.unit.info` item key, which is agent-2-only). Zabbix agent
  (classic or 2) is sufficient for the Statistics template.
- Debian 12+ / Ubuntu 24.04+ (or similar) with `bash`, `awk`, `sed`, `grep`,
  `timeout`, and:
  - `radclient` (package `freeradius-utils`) for the Statistics template.
  - `sudo` configured to let the Zabbix agent run the functional test
    script as a separate, non-privileged user, for the Service Base
    template's functional tests.
- FreeRADIUS's **status virtual server** enabled (`server status { listen {
  type = status ... } }` linked in `sites-enabled`), for the Statistics
  template.
- An existing functional test script (`check_fast.sh`) that prints one
  `OK:`/`BAD:` line per test, for the Service Base template's functional
  tests. See the [Functional tests](#functional-tests) section below for
  the expected output format.

## Installation

1. Copy both scripts to the host, e.g. `/etc/zabbix/scripts/`:
   ```
   chown root:zabbix /etc/zabbix/scripts/freeradius_stats.sh /etc/zabbix/scripts/radius_test_check.sh
   chmod 750 /etc/zabbix/scripts/freeradius_stats.sh /etc/zabbix/scripts/radius_test_check.sh
   ```
2. **Statistics template**: create the secret file for `radclient` (must
   match the `secret` configured for this client in FreeRADIUS's status
   `server` block):
   ```
   echo -n 'your-status-server-secret' > /etc/zabbix/scripts/freeradius_stats.secret
   chown zabbix:zabbix /etc/zabbix/scripts/freeradius_stats.secret
   chmod 600 /etc/zabbix/scripts/freeradius_stats.secret
   ```
3. **Service Base template**: add a sudoers rule allowing the `zabbix` user
   to run your test script as its dedicated user, without a password —
   e.g. `/etc/sudoers.d/zabbix-radius-test` (mode `0440`):
   ```
   zabbix ALL=(pavlicek) NOPASSWD: /home/pavlicek/radius-test/check_fast.sh
   ```
   Adjust the username and path in `radius_test_check.sh` (`RUN_AS_USER`,
   `TEST_SCRIPT`) to match your setup.
4. Register the UserParameters, e.g. in
   `/etc/zabbix/zabbix_agent2.d/userparams/freeradius.conf`:
   ```
   UserParameter=radiusstats.global[*],/etc/zabbix/scripts/freeradius_stats.sh global "$1" "$2" "$3" /etc/zabbix/scripts/freeradius_stats.secret
   UserParameter=radiusstats.client[*],/etc/zabbix/scripts/freeradius_stats.sh client "$1" "$2" "$3" "$4" /etc/zabbix/scripts/freeradius_stats.secret
   UserParameter=radiusclient.discovery[*],/etc/zabbix/scripts/freeradius_stats.sh client_discovery "$1"
   UserParameter=radiustest.raw,/etc/zabbix/scripts/radius_test_check.sh raw
   UserParameter=radiustest.discovery,/etc/zabbix/scripts/radius_test_check.sh discovery
   ```
5. Restart the agent: `systemctl restart zabbix-agent2`
6. Import both templates (Data collection → Templates → Import) and link
   them to the host(s).
7. Set the macros described below.
8. Test directly on the host before waiting for the first Zabbix poll:
   ```
   zabbix_agent2 -t 'radiusstats.global[127.0.0.1,18121,0x1f]'
   zabbix_agent2 -t radiustest.raw
   zabbix_agent2 -t radiustest.discovery
   ```

## Configuration

### FreeRADIUS Service Base

| Macro | Meaning |
|---|---|
| `{$RADIUSD.SERVICE.NAME}` | systemd unit name (default `freeradius.service`). |
| `{$RADIUSD.PROCESS.NAME}` | process name for `proc.*` checks (default `freeradius`). |
| `{$RADIUS.AUTH.PORT}` / `{$RADIUS.ACCT.PORT}` | UDP auth/accounting ports. |
| `{$RADSEC.ENABLED}` / `{$RADSEC.PORT}` | set `{$RADSEC.ENABLED}=1` on hosts that actually run RadSec. |
| `{$RADIUSD.CPU.MAX.WARN}` / `{$RADIUSD.MEM.MAX.WARN}` | resource usage thresholds (%). |

### FreeRADIUS Statistics

| Macro | Meaning |
|---|---|
| `{$RADIUS.STATUS.HOST}` / `{$RADIUS.STATUS.PORT}` | status server address (default `127.0.0.1`/`18121` — override per host if different). |
| `{$RADIUS.STATS.TYPE.GLOBAL}` / `{$RADIUS.STATS.TYPE.CLIENT}` | `FreeRADIUS-Statistics-Type` bitmask (default `0x1f` / `0x2f` — includes proxy stats; drop bits 4+8 if this server doesn't proxy). |
| `{$RADIUS.CLIENTS}` | comma-separated list of NAS clients to monitor individually: `ip1:label1,ip2:label2`. **Do not include RadSec/TLS clients** — FreeRADIUS has no per-client stats for them (`FreeRADIUS-Stats-Error = "No such client"`), the item would stay permanently "not supported". |
| `{$RADIUS.REJECT.RATE.WARN}` / `{$RADIUS.CLIENT.REJECT.WARN}` | Access-Reject rate thresholds (rejects/s) — starting defaults, tune to your baseline. |
| `{$RADIUS.QUEUE.AUTH.WARN}` / `{$RADIUS.THREADS.NEARMAX.WARN}` | internal backlog / thread-pool thresholds. |

## Functional tests

The Service Base template's discovery rule (`radiustest.discovery`) expects
a script that prints one line per test, e.g.:

```
OK:    Access-Accept    vpn/accept_test99_p:18122.conf
OK:    SUCCESS 101      eduroam/accept-test-cesnet-cz-peap-mschapv2_cui.conf
   CUI 'p/HeKPrjDtRy9a6yNnE8E5WiyYk' == 'p/HeKPrjDtRy9a6yNnE8E5WiyYk'
```

- Lines starting with `OK:` or `BAD:` are results; the **last
  whitespace-separated token** is used as the test name.
- Indented `CUI ...` lines (and anything else) are ignored.
- One Zabbix item + trigger is created per discovered test
  (`radiustest.result["{#TESTNAME}"]`), all as dependent items off a single
  `radiustest.raw` poll — the test script itself only runs once per polling
  interval (`10m` for values, `2h` for discovery), not once per test.
- A dedicated trigger (`FreeRADIUS functional tests non-standard response`)
  catches the case where the script ran but its output doesn't contain any
  `OK:`/`BAD:` line at all (e.g. its output format changed).

## Security notes

- **`freeradius_stats.sh`**: the status-server secret is passed to
  `radclient` via `-S <file>` (radclient reads it itself), never as a
  command-line argument — it is therefore never visible in `ps` output.
  `{$RADIUS.STATS.TYPE.*}` and every client IP (from `{$RADIUS.CLIENTS}` or
  passed directly) are validated before being placed into the
  attribute/value text sent to `radclient`, so a malformed macro value
  cannot inject extra RADIUS attributes into the request (e.g. an "IP" of
  `1.2.3.4, FreeRADIUS-Statistics-Type = 0xff`).
- **`radius_test_check.sh`**: `sudo -A` is used so that a misconfigured
  sudoers rule fails immediately with a clear error instead of the agent
  hanging while `sudo` waits for a password on a non-existent terminal.
  Any non-zero exit code from `sudo`/the test script that doesn't come with
  parseable `OK:`/`BAD:` output is surfaced verbatim via `ZBX_NOTSUPPORTED`
  (e.g. `command not found`, `no askpass program specified`), so the
  specific failure is visible in Zabbix instead of silently producing an
  empty or misleading item value.
- Both scripts use the same `ZBX_NOTSUPPORTED: <reason>` convention as the
  Certificate Expiry template's script, and deliberately avoid `set -e` /
  `set -o pipefail` for the same reason described there: explicit checks
  are used instead, so one bad entry (an unreachable NAS, an unrecognised
  status-server target) doesn't abort the whole run.
- `radiustest.raw` and the per-client statistics master items deliberately
  do **not** use `discard_unchanged_heartbeat` preprocessing where a
  `nodata()` trigger depends on them (or on a related item) — that
  combination causes false "no data" alerts if a heartbeat interval is
  ever shorter than the monitoring window. Where you see
  `discard_unchanged_heartbeat` on other items, it's intentional and safe.

## Troubleshooting

- Item shows "Not supported" → check its error message in Zabbix (Latest
  data); both scripts always return a specific `ZBX_NOTSUPPORTED: reason`
  rather than an empty value.
- `FreeRADIUS-Stats-Error: No such client` → the IP in `{$RADIUS.CLIENTS}`
  isn't recognised for per-client stats by FreeRADIUS (commonly a RadSec
  client — see [Configuration](#configuration) above).
- Functional test item never gets discovered → run
  `zabbix_agent2 -t radiustest.discovery` on the host and check the JSON
  output; confirm the sudoers rule works with
  `sudo -A -u <user> <test_script>` run manually as the `zabbix` user.

## Version

Part of the same FreeRADIUS monitoring project as the
[Certificate Expiry](../certificate-expiry/README.md) template. See the
project's top-level README for the full picture (certificates, service
health, statistics, functional tests).
