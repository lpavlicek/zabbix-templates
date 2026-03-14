# ICMP Ping to all IPs

Zabbix template that automatically discovers all IPv4/IPv6 addresses associated with a hostname via DNS and monitors each address independently using ICMP ping.

Tested with **Zabbix 7.4**.

---

## Overview

Standard Zabbix ICMP templates monitor only the primary interface address. This template resolves the hostname to **all its DNS addresses** and creates monitored items for each one dynamically. Useful for:

- Hosts with multiple A/AAAA records (round-robin DNS, dual-stack)
- CDN edge nodes or anycast addresses
- Any host where you want per-IP availability visibility

---

## Requirements

- Zabbix Server or Proxy **7.4+**
- External script `dns_ip_discovery.sh` must be placed in the Zabbix external scripts directory and made executable:

```bash
cp dns_ip_discovery.sh /usr/lib/zabbix/externalscripts/
chmod +x /usr/lib/zabbix/externalscripts/dns_ip_discovery.sh
```

> The default external scripts directory is `/usr/lib/zabbix/externalscripts/`. Check your `zabbix_server.conf` (`ExternalScripts` parameter) if you use a custom path.

---

## Setup

1. Import `ICMP_Ping_to_all_IPs.yaml` into Zabbix via **Data collection → Templates → Import**.
2. Assign the template to the desired host.
3. Adjust the threshold macros if the defaults do not suit your environment (see [Macros](#macros) below).

---

## What the template monitors

| Item | Type | Description |
|---|---|---|
| `icmpping[{#IP}]` | Simple check | Host reachability (0 = Down, 1 = Up) per discovered IP |
| `icmppingloss[{#IP}]` | Simple check | ICMP packet loss in % per discovered IP |
| `icmppingsec[{#IP}]` | Simple check | ICMP round-trip response time in seconds per discovered IP |
| `icmpping.overall_status` | Calculated | Average reachability across all discovered IPs (for dashboard use) |

Discovery runs every **1 hour**. Items for addresses no longer returned by DNS are removed after **7 days**.

---

## Triggers

| Trigger | Priority | Condition |
|---|---|---|
| `{#IP} ICMP: Unavailable by ICMP ping` | HIGH | Last 3 checks all timed out |
| `{#IP} ICMP: High ICMP ping loss` | WARNING | Packet loss > `{$ICMP_LOSS_WARN}` for 5 minutes (and host is not fully down) |
| `{#IP} ICMP: High ICMP ping response time` | WARNING | Average response time > `{$ICMP_RESPONSE_TIME_WARN}` for 5 minutes (and no loss/unavailability trigger is active) |

Trigger dependencies are configured so that higher-severity triggers suppress lower-severity ones for the same IP.

---

## Macros

| Macro | Default | Description |
|---|---|---|
| `{$ICMP_LOSS_WARN}` | `20` | Warning threshold for packet loss (%). Range: 0–100. |
| `{$ICMP_RESPONSE_TIME_WARN}` | `0.15` | Warning threshold for average ICMP response time (seconds). Min: 0. |

Macros can be overridden at the host or host-group level.

---

## Dashboard

The template includes a built-in **ICMP** dashboard with three graph prototype widgets:

- ICMP ping (reachability 0/1 per IP)
- ICMP response time
- ICMP loss

---

## Tags

| Tag | Value |
|---|---|
| `class` | `network` |
| `target` | `icmp` |
| `component` | `health`, `network` |
| `scope` | `availability`, `performance` |

---

## Author

**lpavlicek** — template version `7.4-1`
