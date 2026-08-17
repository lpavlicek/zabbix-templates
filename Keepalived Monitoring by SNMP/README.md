# Keepalived Monitoring by SNMP

Zabbix 7.4 template for monitoring [Keepalived](https://www.keepalived.org/) VRRP instances via SNMP (KEEPALIVED-MIB).

No Zabbix agent is required on the monitored host — everything is collected by the Zabbix server/proxy directly over SNMP.

## Files

- `Keepalived Monitoring by SNMP.yaml` — the template, ready to import (Data collection → Templates → Import).
- `README.md` — this file.

## What is monitored

### Fixed items

| Item | Key | Description |
|---|---|---|
| `Keepalived: version` | `keepalived.version` | Installed Keepalived version string (e.g. `v2.2.8`). Polled every hour; a change fires an informational trigger — useful for catching version drift between HA pair members. |

### VRRP instance discovery (LLD)

`VRRP Instance Discovery` walks the SNMP `vrrpInstanceTable` (OID `1.3.6.1.4.1.9586.100.5.2.3.1.2`, `vrrpInstanceName`) once an hour and creates the following per discovered instance ({#VRRP_NAME}, with {#SNMPINDEX} as the SNMP table index):

| Item prototype | Key | Description |
|---|---|---|
| `VRRP Instance {#VRRP_NAME}: State` | `vrrp.state[{#SNMPINDEX}]` | Current VRRP state (`vrrpInstanceState`, OID `...5.2.3.1.4`): 0=INIT, 1=BACKUP, 2=MASTER, 3=FAULT, 4=UNKNOWN. An SNMP error (Not supported / value `-1`) is mapped to 4 (UNKNOWN) instead of leaving the item unsupported. |
| `VRRP Instance {#VRRP_NAME}: WantedState` | `vrrp.wantedstate[{#SNMPINDEX}]` | Administrator-configured target state (`vrrpInstanceWantedState`, OID `...5.2.3.1.6`): 1=BACKUP, 2=MASTER. Same not-supported handling as above. |
| `VRRP Instance {#VRRP_NAME}: State mismatch` | `vrrp.state.mismatch[{#SNMPINDEX}]` | Calculated item: `1` when the actual state differs from the wanted state, `0` otherwise. |

### Triggers

| Trigger | Severity | Condition |
|---|---|---|
| `VRRP Instance {#VRRP_NAME}: Reporting FAULT state` | High | Actual state = FAULT (3). |
| `VRRP Instance {#VRRP_NAME}: Reporting INIT state for more than 2 minutes` | Average | State stays INIT (0) for over 170s — normal startup should leave INIT within 30-60s. |
| `VRRP Instance {#VRRP_NAME}: Reporting UNKNOWN state` | Warning | State could not be determined (SNMP error, see [Troubleshooting](#troubleshooting)). |
| `VRRP Instance {#VRRP_NAME}: State changed` | Info | Any state change (manual close, informational only). |
| `VRRP Instance {#VRRP_NAME}: State mismatch` | Warning | Actual state differs from wanted state for more than ~5 minutes. Depends on the three triggers above, so it doesn't fire redundantly when a more specific state problem is already raised. |
| `Keepalived: changed version` | Info | Installed version changed since the last check (manual close, informational only). |

There are intentionally no "no data" triggers.

### Value mapping

- `VrrpState`: `0`→init, `1`→backup, `2`→master, `3`→fault, `4`→unknown.
- `state mismatch`: `0`→no, `1`→yes.

## Requirements

- **Keepalived built with SNMP support** and started with the SNMP subsystem enabled (`-x` / `--snmp`, or `-A` if using a non-default AgentX socket).
- **`snmpd`** running on the monitored host, configured as an AgentX master (`master agentx` in `/etc/snmp/snmpd.conf`), with an SNMPv1/v2c community accessible from the Zabbix server/proxy (default assumed: `public`).
- **Start order matters**: `snmpd` must be (re)started *before* `keepalived`, otherwise Keepalived's SNMP AgentX subagent won't attach and all SNMP items will report as unsupported/UNKNOWN until Keepalived is restarted.
- Network/firewall access from the Zabbix server (or the proxy monitoring the host) to UDP/161 on the host.

## Setup (Debian 13)

The template is currently used on two Debian 13 servers forming a Keepalived VRRP pair (see [Deployment notes](#deployment-notes)).

1. Install the packages if not already present:
   ```
   apt install keepalived snmpd
   ```
   The Debian `keepalived` package ships with SNMP support compiled in (`-x`/`--snmp` and `-A` are listed in `keepalived(8)`), so no rebuild from source is needed.
2. Configure `snmpd` as an AgentX master — add to `/etc/snmp/snmpd.conf`:
   ```
   master agentx
   ```
   Make sure the community used there (`rocommunity public ...` or similar) matches what you configure in the Zabbix host's SNMP interface.
3. Enable the SNMP subsystem in Keepalived by adding `-x` to its startup options. On Debian this is done via a systemd override rather than editing the packaged unit directly:
   ```
   systemctl edit keepalived
   ```
   and add:
   ```
   [Service]
   ExecStart=
   ExecStart=/usr/sbin/keepalived --dont-fork --log-console -x $DAEMON_ARGS
   ```
   Run `systemctl cat keepalived` first to see the exact `ExecStart` line shipped by the installed package version and adjust the override to match it plus `-x`, rather than assuming the line above verbatim.
4. Restart in the correct order:
   ```
   systemctl restart snmpd
   systemctl restart keepalived
   ```
5. Verify locally on the host before touching Zabbix:
   ```
   snmpwalk -v2c -c public localhost 1.3.6.1.4.1.9586.100.5.2.3.1.2
   ```
   This should list the configured VRRP instance name(s). If it times out or returns nothing, see [Troubleshooting](#troubleshooting).
6. In Zabbix, add an **SNMP interface** (SNMPv2, port 161, matching community) to both hosts, then **import** `Keepalived Monitoring by SNMP.yaml` and **link** the template to both hosts. The template group `lpavlicek templates` is created automatically if it doesn't exist yet.
7. Wait for the discovery rule to run (up to 1 hour, or trigger it manually from Data collection → Hosts → Discovery) and confirm the per-instance items appear.

## Deployment notes

Used on two Debian 13 servers forming a single VRRP HA pair. In normal operation exactly one node reports `MASTER` and the other `BACKUP`:

- Both nodes reporting `MASTER` at the same time = split-brain — investigate immediately.
- Both nodes reporting `BACKUP` = the VIP is not being served by anyone — service outage.
- Frequent `MASTER` ↔ `BACKUP` transitions on the `State changed` trigger indicate flapping, usually a sign of network instability or an unstable health-check script.

## Troubleshooting

- **Items unsupported / stuck on UNKNOWN (state 4)** — check, in this order: is `snmpd` running (`systemctl status snmpd`), is it configured with `master agentx`, was `keepalived` (re)started *after* `snmpd`, and does the SNMP community on the host match the one configured on the Zabbix SNMP interface. `journalctl -u keepalived` will show `Failed to register AgentX` or similar if the subagent couldn't attach.
- **Discovery finds no VRRP instances** — confirm `snmpwalk -v2c -c public localhost 1.3.6.1.4.1.9586.100.5.2.3.1.2` returns instance names on the host itself first; if that's empty, it's a Keepalived/SNMP problem, not a Zabbix one.
- **`Keepalived: version` item is empty/unsupported** — same checks as above; this item uses a separate scalar OID (`...5.1.1.0`) so a working `vrrpInstanceTable` walk doesn't guarantee this one also works if SNMP was only partially reconfigured.

## Reference

- Keepalived SNMP support: https://www.keepalived.org/doc/snmp_support.html
- KEEPALIVED-MIB OID base: `1.3.6.1.4.1.9586.100.5`

## Changelog

### 7.4-1 (2026-08-17)
- Initial version imported into this repository.
- Added `vendor` block (author, version) and template-level `class`/`target` tags to match this repo's other templates.
- Cleaned up a formatting issue in the `VRRP Instance {#VRRP_NAME}: State` item description (whitespace had collapsed several paragraphs onto single lines).
