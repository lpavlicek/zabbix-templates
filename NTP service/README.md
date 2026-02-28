# Zabbix Template: NTP Services

Zabbix 7.4 template for monitoring NTP server availability and synchronization quality using [chrony](https://chrony-project.org/) running on the Zabbix server or proxy.

## Overview

The template resolves the monitored NTP server's hostname to its IPv4 and IPv6 addresses (via low-level discovery), performs UDP availability checks on each address, and collects detailed NTP metrics using `chronyc ntpdata`. All metric collection is done from the Zabbix server/proxy side — no agent is required on the monitored NTP server.

## Features

- **UDP availability check** for each resolved IPv4/IPv6 address
- **chrony-based metrics**: offset, peer delay, peer dispersion, response time, root delay, root dispersion, stratum, leap status
- **Configurable thresholds** via macros (offset, peer dispersion, expected stratum)
- **Built-in dashboard** with graphs and status widgets
- **Value maps** for stratum, leap status and service availability
- **Dependency-aware triggers** — lower-priority triggers are suppressed when a root cause is active

## Requirements

| Component | Version |
|-----------|---------|
| Zabbix server/proxy | 7.4+ |
| chrony | any (see [Permissions](#permissions) for version differences) |
| `dig` (bind-utils / dnsutils) | any |

## Files

| File | Description |
|------|-------------|
| `zbx_export_ntp_services.yaml` | Zabbix template export (XML/YAML format, Zabbix 7.4) |
| `dns_ip_discovery.sh` | External script — resolves hostname to IPv4/IPv6 addresses for LLD |
| `chronyc_ntpdata.sh` | External script — retrieves `chronyc ntpdata` output for a given host |

## Installation

### 1. External scripts

Copy both scripts to the Zabbix `ExternalScripts` directory (default: `/usr/lib/zabbix/externalscripts`) and make them executable:

```bash
cp dns_ip_discovery.sh chronyc_ntpdata.sh /usr/lib/zabbix/externalscripts/
chmod +x /usr/lib/zabbix/externalscripts/dns_ip_discovery.sh
chmod +x /usr/lib/zabbix/externalscripts/chronyc_ntpdata.sh
```

### 2. Permissions for chronyc

#### chrony ≤ 4.6

`chronyc ntpdata` requires root. Grant sudo access to the `zabbix` user:

```
# /etc/sudoers.d/zabbix-chronyc
zabbix ALL=(root) NOPASSWD: /usr/bin/chronyc ntpdata *
```

#### chrony ≥ 4.7

Enable socket access by adding the following to `/etc/chrony.conf`:

```
opencommands activity authdata clients manual ntpdata rtcdata selectdata serverstats smoothing sourcename sources sourcestats tracking
```

At minimum, `ntpdata` must be listed. Reload chrony after the change:

```bash
systemctl reload chronyd
```

### 3. Configure chrony peers

The monitored NTP server must be configured as a peer in `/etc/chrony.conf` on the Zabbix server/proxy, using the **exact same value** as the `{$NTP_HOST}` macro. For example:

```
server ntp.example.com iburst
```

Reload chrony after making changes:

```bash
systemctl reload chronyd
```

### 4. Import the template

In the Zabbix web UI: **Configuration → Templates → Import** → select `zbx_export_ntp_services.yaml`.

### 5. Assign the template and set macros

Assign the template to a host and configure at minimum:

| Macro | Required | Description |
|-------|----------|-------------|
| `{$NTP_HOST}` | **Yes** | DNS name or IP address of the NTP server to monitor (e.g. `ntp.example.com`) |
| `{$NTP_HOST_EXPECTED_STRATUM}` | No | Maximum expected stratum (default: `2`) |
| `{$NTP_OFFSET_WARN}` | No | Offset warning threshold in seconds (default: `0.005`) |
| `{$NTP_PEER_DISPERSION_WARN}` | No | Peer dispersion warning threshold in seconds (default: `0.01`) |
| `{$NTP_PORT}` | No | NTP UDP port (default: `123`) |

## Collected Items

| Item | Type | Description |
|------|------|-------------|
| `NTP: chronyc ntpdata raw` | External | Raw output of `chronyc ntpdata {$NTP_HOST}` — master item, history disabled |
| `NTP: Offset` | Dependent | Difference between local clock and peer time (seconds) |
| `NTP: Peer delay` | Dependent | RTT of the NTP exchange between Zabbix server/proxy and the peer |
| `NTP: Peer dispersion` | Dependent | Uncertainty of the offset estimate for the peer |
| `NTP: Response time` | Dependent | Time between NTP request sent and response received |
| `NTP: Root delay` | Dependent | Total network path delay from peer back to stratum-1 |
| `NTP: Root dispersion` | Dependent | Total dispersion accumulated through all hops to stratum-1 |
| `NTP: Stratum` | Dependent | Stratum reported by the peer (16 = unsynchronized, 17 = missing) |
| `NTP: Leap status` | Dependent | Leap second indicator (0=Normal, 1=Insert, 2=Delete, 3=Not synchronised) |
| `NTP: {#IP} available` | Simple (LLD) | UDP availability check on each discovered IP address |

## Triggers

| Trigger | Severity | Description |
|---------|----------|-------------|
| NTP: No data from chronyc | WARNING | External script returned no data for 10 minutes |
| NTP: Service not available via {#IP} | AVERAGE | UDP check on discovered IP failed |
| NTP: Missing stratum value | AVERAGE | chronyc returned no stratum — peer unreachable or misconfigured |
| NTP: Not synchronized | AVERAGE | Peer reports stratum 16 (unsynchronized) |
| NTP: Leap status is Not synchronized | AVERAGE | Leap indicator = Not synchronised |
| NTP: Leap status is not Normal | WARNING | Any non-zero leap indicator (suppressed if Not synchronized) |
| NTP: Time offset greater than threshold | WARNING | \|offset\| > `{$NTP_OFFSET_WARN}` |
| NTP: Peer dispersion greater than threshold | WARNING | Peer dispersion > `{$NTP_PEER_DISPERSION_WARN}` |
| NTP: Stratum too high | WARNING | Stratum > `{$NTP_HOST_EXPECTED_STRATUM}` |

## Dashboard

The template includes a built-in dashboard with the following widgets:

- Time series graphs: Offset, Peer delay, Root dispersion, Peer dispersion, Root delay
- Status widgets (item): Stratum, Leap status
- Honeycomb: NTP service availability per IP address

## Troubleshooting

**No data / trigger "No data from chronyc" fires**
- Check that chrony is running: `systemctl status chronyd`
- Verify that `{$NTP_HOST}` is listed as a peer in `chrony.conf`
- For chrony ≤ 4.6: verify sudo is configured correctly — run `sudo -u zabbix sudo /usr/bin/chronyc ntpdata <host>` manually
- Check that both scripts exist and are executable in `ExternalScripts`

**No IP addresses discovered**
- Check that `dig` is installed on the Zabbix server/proxy
- Run `dns_ip_discovery.sh <hostname>` manually to verify output

**Stratum = 17 (missing)**
- chronyc has not yet exchanged NTP packets with the peer — wait for the next polling interval, or check that the server is reachable

## License

MIT

## Author

lpavlicek
