# syslog-ng by Zabbix agent 2

Zabbix 7.4 template that monitors **TCP connection slots** (`max-connections()`) of syslog-ng network sources and detects **rejected connections**, i.e. the situation in which syslog-ng refuses new TCP clients and their logs are lost.

The template needs **no sudo and no UserParameter**. A systemd timer running as root writes syslog-ng statistics to a file every minute and the agent only reads files.

## Files

| File | Install to | Purpose |
|---|---|---|
| `syslog-ng by Zabbix agent 2.yaml` | Zabbix frontend | Template export (Zabbix 7.4) |
| `host/syslogng-stats-dump` | `/usr/local/sbin/syslogng-stats-dump` | Writes `syslog-ng-ctl stats prometheus` output to the stats file |
| `host/syslogng-stats-dump.service` | `/etc/systemd/system/syslogng-stats-dump.service` | Oneshot service running the dump script as root (hardened) |
| `host/syslogng-stats-dump.timer` | `/etc/systemd/system/syslogng-stats-dump.timer` | Starts the service every minute |
| `host/zabbix-maxconn.conf` | `/etc/syslog-ng/conf.d/zabbix-maxconn.conf` | Copies "connections reached" messages to a file readable by the `zabbix` group |
| `host/logrotate-syslog-ng-maxconn` | `/etc/logrotate.d/syslog-ng-maxconn` | Rotation of that file |

## Architecture

```
systemd timer (root, 1m) ─> syslog-ng-ctl stats prometheus ─> /var/lib/syslogng-stats/stats.prom (0644)
                                                          │
Zabbix agent ── vfs.file.contents[] (master, 1m) ─────────┘ ─> dependent items + LLD
             ── vfs.file.time[]  (freshness)

syslog-ng internal() ─> filter "Number of allowed concurrent connections reached"
                     ─> /var/log/syslog-ng-maxconn.log (root:zabbix 0640)
Zabbix agent (active) ── log[] ─> trigger "connections rejected"
```

## What is monitored

### Items

| Name | Key | Type | Notes |
|---|---|---|---|
| syslog-ng: Get stats | `vfs.file.contents[{$SYSLOGNG.STATS.FILE}]` | Zabbix agent | Master item, history not stored |
| syslog-ng: Statistics status | `syslogng.stats.status` | Dependent | 1 = file contains syslog-ng metrics, 0 = `syslog-ng-ctl` failed |
| syslog-ng: Stats file modification time | `vfs.file.time[{$SYSLOGNG.STATS.FILE},modify]` | Zabbix agent | Detects a stopped timer or failing dump service |
| syslog-ng: Rejected connections (internal log) | `log[{$SYSLOGNG.REJECT.LOG},"Number of allowed concurrent connections reached",,,skip]` | Zabbix agent (active) | One value per rejected connection |

### Discovery: TCP sources

Discovers every input driver with `transport="stream"` that has a `max-connections()` limit (metric `syslogng_socket_max_connections`). UDP drivers have no connection slots and are not discovered.

| LLD macro | Source | Example |
|---|---|---|
| `{#ID}` | label `id` | `s_net#1` (source name + driver index) |
| `{#ADDRESS}` | label `address` | `AF_INET(0.0.0.0:514)` |

| Item prototype | Key | Type |
|---|---|---|
| Active TCP connections | `syslogng.socket.connections["{#ID}"]` | Dependent (Prometheus pattern) |
| Max TCP connections | `syslogng.socket.max_connections["{#ID}"]` | Dependent (Prometheus pattern, discard unchanged 1h) |
| TCP connection slot utilization | `syslogng.socket.utilization["{#ID}"]` | Calculated, % |

Graph prototype: active connections vs. limit per source.

### Triggers

| Severity | Name | Condition |
|---|---|---|
| High | syslog-ng: Cannot read statistics | status = 0, or no data for 5m |
| High | syslog-ng: Stats file is not updated | `fuzzytime(file mtime, {$SYSLOGNG.STATS.MAXAGE})=0` |
| High | syslog-ng: TCP connections rejected (max-connections reached) | `nodata(log item, {$SYSLOGNG.REJECT.PERIOD})=0`, i.e. at least one message within the period; manual close allowed |
| High | [{#ID}] {#ADDRESS}: TCP connection slots nearly exhausted | utilization ≥ `{$SYSLOGNG.CONN.HIGH}` |
| Warning | [{#ID}] {#ADDRESS}: High TCP connection slot utilization | 5m minimum ≥ `{$SYSLOGNG.CONN.WARN}`; depends on the High trigger |

### Macros

| Macro | Default | Description |
|---|---|---|
| `{$SYSLOGNG.CONN.HIGH}` | `95` | High threshold (%), supports context `{$SYSLOGNG.CONN.HIGH:"<id>"}` |
| `{$SYSLOGNG.CONN.WARN}` | `80` | Warning threshold (%), supports context |
| `{$SYSLOGNG.STATS.FILE}` | `/var/lib/syslogng-stats/stats.prom` | Stats file written by the dump service |
| `{$SYSLOGNG.STATS.MAXAGE}` | `300` | Maximum age of the stats file (seconds) |
| `{$SYSLOGNG.REJECT.LOG}` | `/var/log/syslog-ng-maxconn.log` | Dedicated file with rejection messages |
| `{$SYSLOGNG.REJECT.PERIOD}` | `15m` | How long the rejection problem stays open after the last message |

## Requirements

- syslog-ng **≥ 4.2** (introduced `syslogng_socket_connections` / `syslogng_socket_max_connections`). Tested with syslog-ng 4.6.0 on SUSE Linux Enterprise Server 15.
- Zabbix agent 2 with **passive** checks and **active** checks (`ServerActive`, for the log item).
- systemd on the monitored host (`StateDirectory=` and `LogLevelMax=` need systemd ≥ 236; SLES 15 ships a newer version).
- The source used in `zabbix-maxconn.conf` (default `src`) must contain `internal()`.
- Time synchronisation (NTP) between the host and the Zabbix server/proxy (`fuzzytime()`).

## Setup

1. **Stats dump**
   ```bash
   install -m 0755 -o root -g root host/syslogng-stats-dump /usr/local/sbin/syslogng-stats-dump
   install -m 0644 -o root -g root host/syslogng-stats-dump.service host/syslogng-stats-dump.timer /etc/systemd/system/
   systemctl daemon-reload
   systemctl start syslogng-stats-dump.service      # one run now, creates /var/lib/syslogng-stats
   grep syslogng_socket_ /var/lib/syslogng-stats/stats.prom
   systemctl enable --now syslogng-stats-dump.timer
   systemctl list-timers syslogng-stats-dump.timer
   ```
   Adjust `CTL=` in the script if `command -v syslog-ng-ctl` is not `/usr/sbin/syslog-ng-ctl`.

   The service creates `/var/lib/syslogng-stats` itself (`StateDirectory=`, root:root 0755). Only the timer is enabled, the service has no `[Install]` section.

   **Migration from the cron job (7.4-2/7.4-3):**
   ```bash
   rm /etc/cron.d/syslogng-stats
   # then the steps above; the template itself needs no change on the host
   ```
   Remove the cron entry before enabling the timer, otherwise both write the same file (harmless thanks to the atomic `mv`, but redundant).

2. **Rejection log**
   ```bash
   id zabbix            # the zabbix group must exist
   install -m 0644 host/zabbix-maxconn.conf /etc/syslog-ng/conf.d/zabbix-maxconn.conf
   syslog-ng --syntax-only
   systemctl reload syslog-ng
   install -m 0644 host/logrotate-syslog-ng-maxconn /etc/logrotate.d/syslog-ng-maxconn
   ```
   The file is created by syslog-ng with the first matching message. Until then the log item is unsupported ("file does not exist"), which is expected.

3. **Verify from the Zabbix server/proxy**
   ```bash
   zabbix_get -s <host> -k 'vfs.file.contents[/var/lib/syslogng-stats/stats.prom]' | grep syslogng_socket_
   ```

4. **Import** the template (Data collection → Templates → Import) and link it to the host.

## Known limitations

- **Data is up to 2 minutes old.** The timer runs once per minute and the agent polls once per minute independently. Short bursts that fill the slots between two dumps are not visible in utilization (they are caught by the log item if a connection was rejected).
- **No rejected-connections counter.** syslog-ng 4.2 release notes show `syslogng_socket_rejected_connections_total`, but syslog-ng 4.6.0 with the default stats level did not expose it. It is unverified whether a higher `stats(level())` enables it. Rejections are therefore detected from the internal message.
- **The rejection log item is unsupported until the first rejection** (file does not exist yet). This also means a broken `zabbix-maxconn.conf` is not detected by the template. Test it once, e.g. temporarily lower `max-connections()` on a test source.
- **`{#ID}` is not stable across configuration changes.** The `#N` suffix is the index of the driver inside the source. Adding, removing or reordering drivers in a `source {}` block changes the id: LLD creates new items and the old ones (with their history) are deleted after the lost-resource period.
- **The stats file is world-readable.** It contains only counters and source names/addresses, no log content. Restrict it to group `zabbix` (`chgrp zabbix` + `chmod 0640` in the script) if source names are considered sensitive.
- **Per-run journal messages are suppressed by `LogLevelMax=notice`.** Without it, every run logs "Starting/Finished" lines (thousands per day) into the journal and, via syslog-ng `system()`, into `/var/log/messages`. As a side effect, info-level messages of the dump script itself are not logged either; failures (exit code ≠ 0, timeout) still are. Whether systemd's own per-run messages are filtered depends on the systemd version; check with `journalctl -u syslogng-stats-dump.service -f`.
- **Hardening may need adjustment.** `ProtectSystem=full`, `RestrictAddressFamilies=AF_UNIX` etc. were chosen so that `syslog-ng-ctl` only needs the control socket under `/run`. If the service fails with permission errors, check `journalctl -u syslogng-stats-dump.service` and relax the corresponding option.
- **Source names can be misleading.** The template reports the driver id as configured; a source named `*_udp` may contain TCP drivers. Use `{#ADDRESS}` to identify the port.

## Tuning notes

When the utilization is permanently high and the connections are legitimate (one or few per client), increase `max-connections()` of the source. Before that check:

- the open-files limit of the process: `grep 'open files' /proc/$(pidof syslog-ng)/limits` (every connection uses one file descriptor, plus open destination files); raise `LimitNOFILE` via `systemctl edit syslog-ng` if needed,
- `log-iw-size()` of the source: the initial window is divided by `max-connections()`, so raising the limit without raising `log-iw-size()` shrinks the per-connection window.

If connections remain open after clients disappear (NAT timeouts, rebooted devices), enable `so-keepalive(yes)` on the source and review `net.ipv4.tcp_keepalive_time` instead of raising the limit.

## Troubleshooting

| Symptom | Check |
|---|---|
| "Cannot read statistics" | `cat /var/lib/syslogng-stats/stats.prom` contains the `syslog-ng-ctl` error |
| "Stats file is not updated" | `systemctl list-timers syslogng-stats-dump.timer`, `systemctl status syslogng-stats-dump.service`, `journalctl -u syslogng-stats-dump.service` |
| Discovery finds nothing | stats file contains no `syslogng_socket_max_connections{...transport="stream"...direction="input"}` (syslog-ng < 4.2 or no TCP source) |
| Log item unsupported | no rejection has happened yet (file missing), or `ServerActive`/`Hostname` in agent config, or group permissions |

## Changelog

| Version | Date | Change |
|---|---|---|
| 7.4-4 | 2026-10-17 | Stats dump runs from a systemd timer instead of cron (hardened oneshot service, `StateDirectory=`, timeout, suppressed per-run journal messages); template changed in descriptions only |
| 7.4-3 | 2026-10-15 | Rejection trigger uses `nodata()=0` instead of `count()>0`: `count()` is re-evaluated only when a new value arrives, so the problem never resolved; `nodata()` is evaluated periodically |
| 7.4-2 | 2026-10-12 | Replaced sudo/UserParameter with root cron job + `vfs.file.contents[]`; added stats file freshness check; rejection messages read from a dedicated file written by syslog-ng |
| 7.4-1 | 2026-10-12 | Initial version (not deployed) |
