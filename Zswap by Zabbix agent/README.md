# Zswap by Zabbix agent

Zabbix 7.4 template for monitoring Linux [zswap](https://www.kernel.org/doc/html/latest/admin-guide/mm/zswap.html)
(compressed swap cache) on Debian 13 / Ubuntu 24.04+ and other recent kernels.

Template group: `lpavlicek templates` · Template name: `Zswap by Zabbix agent` · Vendor version: `7.4-1`

## Files

- `zswap_by_zabbix_agent.yaml` - the Zabbix template (import via *Data collection → Templates → Import*)
- `scripts/zswap_stats.sh` - collector script, run as root via sudo, invoked from a Zabbix agent UserParameter

## What is monitored

### Items

| Item | Key | Source | Notes |
|---|---|---|---|
| Zswap: enabled | `vfs.file.contents[/sys/module/zswap/parameters/enabled]` | sysfs, direct | 0/1, value map |
| Zswap: max pool percent | `vfs.file.contents[/sys/module/zswap/parameters/max_pool_percent]` | sysfs, direct | % of RAM |
| Zswap: raw statistics | `zswap.stats` | UserParameter + sudo | master item, raw JSON, `history: 0` |
| Zswap: pool total size | `zswap.stats.pool_total_size` | dependent | bytes |
| Zswap: stored pages | `zswap.stats.stored_pages` | dependent | pages |
| Zswap: written back pages | `zswap.stats.written_back_pages` | dependent | cumulative counter since boot |
| Zswap: pool limit hit | `zswap.stats.pool_limit_hit` | dependent | cumulative counter since boot |
| Zswap: page size | `zswap.stats.page_size` | dependent | bytes, from `getconf PAGESIZE` |
| Zswap: stats collection error | `zswap.stats.error` | dependent | non-empty text on collector failure |
| Zswap: compression ratio | `zswap.compression_ratio` | calculated | uncompressed / compressed size |
| Zswap: pool usage (% of configured limit) | `zswap.pool_usage_percent` | calculated | see note below |

`Zswap: enabled` and `Zswap: max pool percent` read world-readable sysfs files directly - no elevated
privileges needed. Everything under `zswap.stats.*` comes from `/sys/kernel/debug/zswap/*`, which is not
readable by the `zabbix` user by default (the debugfs mount is typically `0700 root:root`), so those
values are collected by `scripts/zswap_stats.sh` running as root via sudo (see *Setup* below).

`Zswap: pool usage (% of configured limit)` additionally requires an existing `vm.memory.size[total]` item
on the host (normally provided by the official **Linux by Zabbix agent** template). If that item is not
present, this one calculated item shows as unsupported; nothing else in the template is affected.

### Triggers

| Trigger | Severity | Condition |
|---|---|---|
| Zswap: error collecting statistics | High | `zswap.stats.error` is non-empty |
| Zswap: pool size limit hit | Warning | `pool_limit_hit` increased within `{$ZSWAP.POOL_LIMIT_HIT.TIME}` |
| Zswap: writing back pages to swap | Warning | `written_back_pages` increased within `{$ZSWAP.WRITTEN_BACK.TIME}` |

The two Warning triggers depend on "Zswap: error collecting statistics" so a collector failure doesn't also
raise noisy "increase" alerts.

### Macros

| Macro | Default | Description |
|---|---|---|
| `{$ZSWAP.POOL_LIMIT_HIT.TIME}` | `15m` | Window used to detect an increase in `pool_limit_hit` |
| `{$ZSWAP.WRITTEN_BACK.TIME}` | `15m` | Window used to detect an increase in `written_back_pages` |

### Value maps

`Zswap: enabled state` - `0` → Disabled, `1` → Enabled

### Tags

- Template: `class:software`, `target:zswap`
- Items: `component:configuration` / `component:memory` / `component:health`
- Triggers: `scope:availability` / `scope:capacity` / `scope:performance`

## Requirements

- Debian 13, Ubuntu 24.04+, or any Linux with a zswap-capable kernel and debugfs mounted
- Zabbix agent or Zabbix agent 2
- `sudo`, `getconf` (part of `libc-bin`, normally already installed)
- Recommended: **Linux by Zabbix agent** (or any other template providing `vm.memory.size[total]`) linked
  to the same host, for the pool usage % item

## Setup

1. **Install the collector script.**

   ```bash
   install -o root -g root -m 0700 scripts/zswap_stats.sh /usr/local/bin/zswap_stats.sh
   ```

2. **Allow the `zabbix` user to run it as root without a password.**

   Create `/etc/sudoers.d/zabbix-zswap`:

   ```
   zabbix ALL=(root) NOPASSWD: /usr/local/bin/zswap_stats.sh
   ```

   ```bash
   chmod 0440 /etc/sudoers.d/zabbix-zswap
   visudo -c
   ```

3. **Add the UserParameter.**

   Create `/etc/zabbix/zabbix_agent2.d/userparameter_zswap.conf` (or the equivalent
   `zabbix_agentd.d` path if using Zabbix agent 1):

   ```
   UserParameter=zswap.stats,sudo /usr/local/bin/zswap_stats.sh
   ```

4. **Restart the agent.**

   ```bash
   systemctl restart zabbix-agent2   # or zabbix-agent
   ```

5. **Verify manually** (as the zabbix user):

   ```bash
   sudo -u zabbix sudo /usr/local/bin/zswap_stats.sh
   ```

   Should print a single line of JSON with an empty `"error"` field.

6. **Import the template** in *Data collection → Templates → Import* and link it to the host.

## Troubleshooting

- **`zswap.stats.error` is non-empty / "Zswap: error collecting statistics" fires** - re-run step 5 above.
  Most common causes: `visudo` rule missing/wrong path, `/sys/kernel/debug` not mounted, or the kernel was
  built without `CONFIG_ZSWAP`.
- **`Zswap: pool usage (% of configured limit)` is unsupported** - the host has no `vm.memory.size[total]`
  item; link a template that provides it, or ignore this one item.
- **`Zswap: enabled` always shows Disabled even though zswap is on** - check the raw file directly
  (`cat /sys/module/zswap/parameters/enabled`); very old kernels may return `1`/`0` instead of `Y`/`N`, in
  which case the JavaScript preprocessing step on that item needs adjusting.

## Changelog

- **2026-09-09** - Initial version (`7.4-1`).
