# Debian APT Updates by Zabbix Agent

This repository provides a **Zabbix template** for monitoring available APT updates on
Debian and Ubuntu systems using the **Zabbix agent** and **UserParameters**.

The template monitors:
- total number of available APT updates,
- number of **security** updates,
- number of **non-security** updates,
- time of the last successful `apt update`,
- long-pending security updates with escalation.

Designed and tested with **Zabbix 7.4**.

---

## Requirements

- Debian / Ubuntu (APT-based distributions)
- Zabbix agent (passive or active)
- Ability to execute:
  - `apt list --upgradable`
  - read access to APT state files under `/var/lib/apt` and `/var/cache/apt`

---

## Installation

### 1. Configure UserParameters on the host

Create the following file on the monitored host:

```
/etc/zabbix/zabbix_agentd.d/apt.conf
```

Insert the UserParameters below:

```ini
# Total number of available APT updates
UserParameter=apt.updates.total,apt list --upgradable 2>/dev/null | grep -c /

# Number of available security updates (packages from *-security repositories)
UserParameter=apt.updates.security,apt list --upgradable 2>/dev/null | grep -i -c "/.*-security"

# Timestamp of the last successful apt update
UserParameter=apt.updates.last,stat -c %Y  /var/lib/apt/periodic/update-success-stamp  /var/lib/apt/periodic/update-stamp  /var/lib/apt/lists  /var/lib/apt/lists/partial  /var/cache/apt/pkgcache.bin  2>/dev/null | sort -n | tail -1
```

Restart the Zabbix agent:

```bash
systemctl restart zabbix-agent
```

---

### 2. Import the template into Zabbix

1. Go to **Configuration → Templates → Import**
2. Import the file:

```
Debian APT Updates by Zabbix agent.yaml
```

3. Link the template to the desired hosts

---

## Monitored Items

| Item name | Description |
|----------|-------------|
| **APT: Available package updates** | Total number of available APT updates |
| **APT: Available security updates** | Number of available security updates |
| **APT: Last apt update time** | Timestamp of the last successful `apt update` |

---

## Template Macros

| Macro | Default | Description |
|------|---------|-------------|
| `{$APT.UPDATE.MAX.AGE}` | `36h` | Maximum allowed age of the last `apt update` |

Macros can be overridden at:
- host level,
- host group level.

---

## Triggers

### APT: apt update not executed for too long
- **Severity:** Warning  
- **Description:**  
  The APT package index has not been updated within the configured time limit.

---

### APT: Security updates are available
- **Severity:** Average  
- **Description:**  
  Security updates are detected repeatedly and were not installed.

---

### APT: Security updates pending for 7 days
- **Severity:** High  
- **Description:**  
  Security updates have been continuously available for at least 7 days.  
- **Depends on:**  
  *APT: Security updates are available*

---

### APT: Non-security updates are available
- **Severity:** Warning  
- **Description:**  
  Non-security updates are detected repeatedly.

---

## Repeated Detection Logic

Triggers for available updates are intentionally **not fired on the first detection**.
Time-based functions are used to ensure that:
- short-lived states do not raise alerts,
- only persistent, unresolved update conditions are reported.

---

## Operational Recommendations

- Run `apt update` regularly (cron or systemd timer or install package `unattended-upgrades`).
- Install updates during defined maintenance windows.
- Treat security updates with priority; a High severity alert indicates increased risk.

---

## Compatibility

- Zabbix: **7.4**
- Operating systems: Debian 10+, Ubuntu 20.04+
- Agent: Zabbix agent / Zabbix agent 2

---

## License

MIT License
