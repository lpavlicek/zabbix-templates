# Postfix Mail Queue – Zabbix Template

Zabbix template for monitoring the size of the Postfix mail queue using the `mailq` command.
The template collects data via a Zabbix agent UserParameter and raises a trigger when the
number of queued messages exceeds a defined limit.

---

## Features

- Monitors the current number of messages in the Postfix mail queue
- Configurable threshold using a user macro
- Lightweight implementation using standard Postfix tools
- Suitable for both standalone Postfix servers and mail gateways

---

## Requirements

- Zabbix Agent (tested with Zabbix 6.x / 7.x)
- Postfix installed on the monitored host
- `mailq` command available in PATH
- Zabbix agent running with sufficient privileges to execute `mailq`

---

## Zabbix Agent Configuration

Add the following UserParameter to the Zabbix agent configuration
(e.g. `/etc/zabbix/zabbix_agentd.d/postfix.conf`):

```ini
UserParameter=postfix.queue,mailq | grep -c '^[0-9A-F]'
```

After adding the parameter, restart the Zabbix agent:

```bash
systemctl restart zabbix-agent
```

---

## Template Details

### Items

| Name                     | Key           | Type    | Unit     |
|--------------------------|---------------|---------|----------|
| Postfix: Mail queue size | postfix.queue | Numeric | messages |

---

### Triggers

| Name                                   | Severity | Description |
|----------------------------------------|----------|-------------|
| Postfix: Mail queue size is above limit | AVERAGE  | Fired when the number of queued messages exceeds the configured limit |

---

### Macros

| Macro                  | Default | Description |
|------------------------|---------|-------------|
| {$POSTFIX.MAILQ.LIMIT} | 20      | Maximum allowed number of messages in the mail queue |

---

## Installation

1. Import the template YAML file into Zabbix:
   - *Configuration → Templates → Import*
2. Link the template to the target host
3. Configure the UserParameter on the host
4. Adjust the macro `{$POSTFIX.MAILQ.LIMIT}` as needed

---

## Notes and Limitations

- The `mailq` output format may vary slightly between Postfix versions,
  but counting message IDs is generally reliable.
- Very large queues may indicate delivery problems, blocked outbound traffic,
  or remote server issues.
- Consider combining this template with SMTP service checks or log monitoring
  for better diagnostics.

---

## License

This template is provided as-is, without warranty of any kind.
You are free to use, modify, and distribute it.
