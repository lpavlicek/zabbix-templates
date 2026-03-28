# Zabbix Template: DNS Records Check

Zabbix 7.4 template for monitoring DNS record availability. Runs agentlessly from the Zabbix server or proxy using an external check script.

## Features

- Monitors arbitrary DNS record types (A, AAAA, MX, NS, SOA, TXT, PTR, CNAME, …)
- Query list configured via a single macro — no template modification needed
- LLD discovery via a `CALCULATED` master item and JavaScript preprocessing — no separate discovery script required
- Queries are sent directly to the monitored host's address (`{HOST.CONN}`)
- Aggregated overall status item for dashboard widgets
- HIGH priority trigger per failed query with explicit recovery expression

## Requirements

| Component | Details |
|---|---|
| Zabbix | 7.4 or later |
| `dig` | Must be available on Zabbix server/proxy (`dnsutils` / `bind-utils`) |
| Script | `dns_check.sh` in the `ExternalScripts` directory |

## Files

| File | Purpose |
|---|---|
| `DNS Records Check.yaml` | Zabbix template — import into Zabbix UI |
| `dns_check.sh` | External check script — install on Zabbix server/proxy |

## Installation

### 1. Install the script

```bash
EXTDIR=/usr/lib/zabbix/externalscripts   # adjust to match your ExternalScripts setting

cp dns_check.sh "$EXTDIR/"
chmod 750 "$EXTDIR/dns_check.sh"
chown root:zabbix "$EXTDIR/dns_check.sh"
```

Verify `dig` is available:

```bash
which dig
# Debian/Ubuntu:  apt install dnsutils
# RHEL/CentOS:    dnf install bind-utils
```

### 2. Import the template

In Zabbix UI: **Data collection → Templates → Import** → select `DNS Records Check.yaml`.

The template is placed in the `lpavlicek templates` group. If the group does not exist it will be created automatically on import.

### 3. Assign to a host

1. Create a host representing the DNS server to be monitored.
   Set the host **interface** to the DNS server's IP address or hostname.
2. Assign the template **DNS Records Check**.
3. Set the `{$DNS.QUERIES}` macro on the host level (see below).
4. Force a LLD discovery run if you don't want to wait for the first scheduled interval:
   **Data collection → Hosts → Discovery → Execute now**.

## Configuration

All configuration is done via host-level macros.

| Macro | Default | Description |
|---|---|---|
| `{$DNS.QUERIES}` | `soa:vse.cz,soa:102.146.in-addr.arpa` | Comma-separated list of queries to check (see format below) |
| `{$DNS.TIMEOUT}` | `2` | Query timeout in seconds (keep below the Zabbix external check timeout of 3 s) |
| `{$DNS.CHECK.INTERVAL}` | `5m` | How often each DNS record is checked |
| `{$DNS.LLD.INTERVAL}` | `1h` | How often the query list macro is re-read and discovery re-runs |

### Query list format

The `{$DNS.QUERIES}` macro contains a comma-separated list of entries in the form `type:name`:

```
soa:vse.cz,soa:102.146.in-addr.arpa
soa:vse.cz,a:www.cms2.cz,a:ritici.cz,txt:txt1500.ue-prague.cz,a:eman.dev
```

Supported record types: `a`, `aaaa`, `mx`, `ns`, `soa`, `txt`, `ptr`, `cname` — and anything else `dig` accepts.

For PTR records use the full reverse-zone name:

```
ptr:4.3.2.1.in-addr.arpa
```

## How It Works

```
{$DNS.QUERIES} macro
        │
        ▼
CALCULATED: dns.records.queries.list        (every {$DNS.LLD.INTERVAL}, history disabled)
  params: concat("{$DNS.QUERIES}","")
        │
        ▼  DEPENDENT
LLD discovery: dns.queries.discovery
  JavaScript preprocessing:
    "soa:vse.cz,a:www.cms2.cz"
      → [{"{#DNS_TYPE}":"soa", "{#DNS_NAME}":"vse.cz"},
         {"{#DNS_TYPE}":"a",   "{#DNS_NAME}":"www.cms2.cz"}]
        │
        ├─ Item prototype (EXTERNAL, every {$DNS.CHECK.INTERVAL}):
        │    dns_check.sh["{#DNS_TYPE}", "{#DNS_NAME}", "{HOST.CONN}", "{$DNS.TIMEOUT}"]
        │    Returns: 1 (record found) or 0 (not found / error)
        │
        └─ Trigger prototype (HIGH):
             fires when value = 0, recovers when value = 1

CALCULATED: dns.records.overall.status      (every {$DNS.CHECK.INTERVAL})
  params: min(last_foreach(//dns_check.sh[*,*,*,*]))
  Returns: 1 = all OK, 0 = at least one failure
```

## What Counts as a Failure

The check returns `0` (FAIL) in any of the following cases:

- The DNS server does not respond (timeout)
- The server returns `NXDOMAIN`
- The server returns `SERVFAIL` or any other error
- The server responds but returns no record of the requested type

## dns_check.sh

The script calls `dig +short +time=N +tries=1 @{HOST.CONN} name type`.

`+short` outputs only the record data, one entry per line. An empty response means no record was found or the server reported an error — the script returns `0`. Any non-empty response means at least one record was returned — the script returns `1`.

### Manual testing

```bash
SCRIPT=/usr/lib/zabbix/externalscripts/dns_check.sh

# Expected: 1
"$SCRIPT" soa vse.cz 192.0.2.1 2
"$SCRIPT" a   www.cms2.cz 192.0.2.1 2

# Expected: 0  (non-existent domain)
"$SCRIPT" a neexistuje.example.invalid 192.0.2.1 2
```

## Multiple DNS Servers

To monitor multiple DNS servers, create one host per server. Each host gets the same template and its own `{$DNS.QUERIES}` macro. Queries automatically go to each host's interface address.

## License

MIT
