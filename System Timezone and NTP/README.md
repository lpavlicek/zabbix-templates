# System Timezone and NTP – Zabbix Template

Zabbix template for monitoring system time configuration on Linux hosts.
The template verifies that the system timezone is configured correctly
and that system time is synchronized via NTP.

Data is collected using Zabbix agent UserParameters based on the
`timedatectl` command.

---

## Features

- Monitors configured system timezone
- Verifies NTP synchronization status
- Configurable expected timezone using a macro
- Lightweight implementation using standard system tools
- Suitable for servers, VMs, and appliances

---

## Requirements

- Zabbix Agent (tested with Zabbix 7.4)
- Linux system using `systemd`
- `timedatectl` command available
- Zabbix agent running with permissions to execute `timedatectl`

---

## Zabbix Agent Configuration

Add the following UserParameters to the Zabbix agent configuration
(e.g. `/etc/zabbix/zabbix_agentd.d/userparameter_timedatectl.conf`):

```ini
UserParameter=timedatectl.timezone,timedatectl show -p Timezone --value
UserParameter=timedatectl.ntp,timedatectl show -p NTPSynchronized --value
```

Restart the Zabbix agent after applying the configuration:

```bash
systemctl restart zabbix-agent
```

---

## Template Details

### Items

| Name                       | Key                  | Type    |
|----------------------------|----------------------|---------|
| System timezone            | timedatectl.timezone | Text    |
| NTP synchronization status | timedatectl.ntp      | Numeric |

---

### Triggers

| Name                                        | Severity | Description |
|---------------------------------------------|----------|-------------|
| System timezone differs from expected value | AVERAGE  | Fired when the configured timezone does not match the expected value |
| System time is not synchronized via NTP     | AVERAGE  | Fired when NTP synchronization is disabled or not active |

---

### Macros

| Macro               | Default        | Description |
|---------------------|----------------|-------------|
| {$TIME.EXPECTED.TZ} | Europe/Prague  | Expected system timezone |

---

## Installation

1. Import the template YAML file into Zabbix:
   - *Configuration → Templates → Import*
2. Link the template to the target host
3. Configure the required UserParameters on the host
4. Adjust the macro `{$TIME.EXPECTED.TZ}` as needed

---

## Notes and Limitations

- The template relies on `systemd`; it is not suitable for systems
  without `timedatectl`.
- A correctly synchronized system time is critical for:
  - TLS certificate validation
  - Log correlation
  - Kerberos authentication
  - Distributed systems
- Consider combining this template with NTP service checks
  for deeper diagnostics.

---

## License

This template is provided as-is, without warranty of any kind.
You are free to use, modify, and distribute it.
