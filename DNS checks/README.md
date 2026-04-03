# Zabbix Template: DNS Check

Zabbix 7.4 template for monitoring DNS record availability and transport protocol support.
Runs agentlessly from the Zabbix server or proxy using two external check scripts.

## Features

**DNS record checks**
- Verifies existence of DNS records (A, AAAA, MX, NS, SOA, TXT, PTR, CNAME, …)
- Returns 1 (OK) or 0 (FAIL) per query
- Aggregated overall status item for dashboard widgets

**DNS protocol checks**
- Tests DNS transport protocol support: UDP, TCP, DNS-over-TLS (DoT), DNS-over-HTTPS (DoH), DNS-over-QUIC (DoQ)
- Measures response time; the script returns milliseconds, stored in Zabbix as seconds (`×0.001`)
- Returns `-1` ms (stored as `-0.001` s, displayed as `<0`) on failure
- Aggregated overall status item for dashboard widgets

**Common**
- Both check types use LLD discovery driven by a single macro — no template modification needed
- LLD discovery uses a `CALCULATED` master item and JavaScript preprocessing — no separate discovery script required
- All queries go to the monitored host's address (`{HOST.CONN}`)
- HIGH priority trigger per failing check with explicit recovery expression

## Requirements

| Component | Details |
|---|---|
| Zabbix | 7.4 or later |
| `kdig` | Must be available on Zabbix server/proxy |
| Scripts | `dns_check.sh` and `dns_proto_check.sh` in the `ExternalScripts` directory |

### Installing kdig

```bash
# Debian / Ubuntu
apt install knot-dnsutils

# RHEL / CentOS / AlmaLinux
dnf install knot-utils
```

## Files

| File | Purpose |
|---|---|
| `DNS_checks_template.yaml` | Zabbix template — import into Zabbix UI |
| `dns_check.sh` | DNS record existence check script |
| `dns_proto_check.sh` | DNS protocol response time check script |

## Installation

### 1. Install the scripts

```bash
EXTDIR=/usr/lib/zabbix/externalscripts   # adjust to match ExternalScripts in zabbix_server.conf

cp dns_check.sh dns_proto_check.sh "$EXTDIR/"
chmod 750 "$EXTDIR/dns_check.sh" "$EXTDIR/dns_proto_check.sh"
chown root:zabbix "$EXTDIR/dns_check.sh" "$EXTDIR/dns_proto_check.sh"
```

### 2. Import the template

In Zabbix UI: **Data collection → Templates → Import** → select `DNS_checks_template.yaml`.

The template is placed in the `lpavlicek templates` group. If the group does not exist it will be created automatically on import.

### 3. Assign to a host

1. Create a host representing the DNS server to be monitored.
   Set the host **interface** to the DNS server's IP address or hostname — this is the address all checks will query.
2. Assign the template **DNS Check**.
3. Override macros on the host level as needed (see Configuration below).
4. Force a LLD discovery run if you don't want to wait for the first scheduled interval:
   **Data collection → Hosts → Discovery rules → Execute now** (for each of the two discovery rules).

## Configuration

All configuration is done via host-level macros.

| Macro | Default | Description |
|---|---|---|
| `{$DNS.QUERIES}` | `soa:vse.cz,soa:102.146.in-addr.arpa` | DNS record queries to check (see format below) |
| `{$DNS.PROTOCOLS}` | `udp:tcp` | DNS transport protocols to test (see format below) |
| `{$DNS.PROTO.QUERY}` | `www.vse.cz` | Domain name used as the A record query target for protocol checks |
| `{$DNS.TIMEOUT}` | `2` | Query timeout in seconds for both scripts |
| `{$DNS.CHECK.INTERVAL}` | `5m` | How often each DNS record is checked |
| `{$DNS.PROTO.CHECK.INTERVAL}` | `5m` | How often each DNS protocol is checked |
| `{$DNS.LLD.INTERVAL}` | `1h` | How often the query and protocol list macros are re-read |

### DNS record query format

The `{$DNS.QUERIES}` macro contains a **comma-separated** list of entries in the form `type:name`:

```
soa:vse.cz,soa:102.146.in-addr.arpa
soa:vse.cz,a:www.cms2.cz,a:ritici.cz,txt:txt1500.ue-prague.cz
```

Supported record types: `a`, `aaaa`, `mx`, `ns`, `soa`, `txt`, `ptr`, `cname` — and anything else `kdig` accepts.

For PTR records use the full reverse-zone name:
```
ptr:4.3.2.1.in-addr.arpa
```

### DNS protocol format

The `{$DNS.PROTOCOLS}` macro contains a **colon-separated** list of protocol names:

```
udp:tcp
udp:tcp:tls:https:quic
```

Supported protocols:

| Value | Transport | Default port | kdig flag |
|---|---|---|---|
| `udp` | DNS over UDP | 53 | `+notcp` (disables TCP fallback) |
| `tcp` | DNS over TCP | 53 | `+tcp` |
| `tls` | DNS-over-TLS (DoT) | 853 | `+tls` |
| `https` | DNS-over-HTTPS (DoH) | 443 | `+https` |
| `quic` | DNS-over-QUIC (DoQ) | 853 | `+quic` |

Any unknown token in the macro is silently ignored by the JavaScript preprocessing step.

## How It Works

```
{$DNS.QUERIES} macro                        {$DNS.PROTOCOLS} macro
        │                                           │
        ▼                                           ▼
CALCULATED: dns.records.queries.list        CALCULATED: dns.proto.list
  params: concat("{$DNS.QUERIES}","")         params: concat("{$DNS.PROTOCOLS}","")
  delay: {$DNS.LLD.INTERVAL}, history: 0     delay: {$DNS.LLD.INTERVAL}, history: 0
        │                                           │
        ▼  DEPENDENT                               ▼  DEPENDENT
LLD: dns.queries.discovery                  LLD: dns.proto.discovery
  JS: "soa:vse.cz,a:www.cms2.cz"             JS: "udp:tcp:tls"
    → [{#DNS_TYPE}=soa, {#DNS_NAME}=vse.cz}]   → [{#DNS_PROTO}=udp}, ...]
        │                                           │
        ├─ Item prototype (EXTERNAL, UNSIGNED)      ├─ Item prototype (EXTERNAL, FLOAT, units: s)
        │    dns_check.sh[type,name,server,timeout]  │    dns_proto_check.sh[proto,server,query,timeout]
        │    Returns: 1 (OK) or 0 (FAIL)            │    Script returns ms → ×0.001 → stored as seconds
        │                                           │    <0 = FAIL (-1 ms → -0.001 s), >=0 = time in s
        │                                           │
        └─ Trigger: fires on =0, recovers on =1     └─ Trigger: fires on <0, recovers on >=0

CALCULATED: dns.records.overall.status      CALCULATED: dns.proto.overall.status
  min(last_foreach(//dns_check.sh[*]))        min(last_foreach(//dns_proto_check.sh[*]))
  1 = all OK, 0 = at least one FAIL          >=0 = all OK (seconds), <0 = at least one FAIL
```

## What Counts as a Failure

**dns_check.sh** returns `0` when:
- The DNS server does not respond (timeout)
- The server returns NXDOMAIN or SERVFAIL
- The server responds but returns no record of the requested type

**dns_proto_check.sh** returns `-1` ms (stored as `-0.001` s after the ×0.001 multiplier) when:
- The DNS server does not support the protocol (connection refused, TLS handshake error)
- The query times out
- kdig exits with a non-zero status for any other reason

The trigger fires on any value `<0` s, which covers the `-0.001` s sentinel as well as any other negative value that might result from an unexpected kdig output.

## Timeout Notes

The `{$DNS.TIMEOUT}` macro controls the `kdig +time=N` parameter for both scripts.
The default is 2 seconds, which fits within the Zabbix default external check execution timeout of 3 seconds.
If checks are still timing out, increase the
`Timeout` setting for external checks in **Administration → General → Timeouts**,
and raise `{$DNS.TIMEOUT}` accordingly.

## Manual Testing

```bash
DCHECK=/usr/lib/zabbix/externalscripts/dns_check.sh
PCHECK=/usr/lib/zabbix/externalscripts/dns_proto_check.sh
SERVER=192.0.2.1   # replace with actual DNS server IP

# Record checks — expected: 1 (found) or 0 (not found)
"$DCHECK" soa vse.cz          "$SERVER" 2
"$DCHECK" a   www.cms2.cz     "$SERVER" 2
"$DCHECK" txt txt1500.ue-prague.cz "$SERVER" 2
"$DCHECK" a   neexistuje.example.invalid "$SERVER" 2   # expected: 0

# Protocol checks — expected: response time in ms (script output), or -1 if not supported
# Zabbix stores the value in seconds after ×0.001 conversion
"$PCHECK" udp   "$SERVER" www.vse.cz 2
"$PCHECK" tcp   "$SERVER" www.vse.cz 2
"$PCHECK" tls   "$SERVER" www.vse.cz 2
"$PCHECK" https "$SERVER" www.vse.cz 2
"$PCHECK" quic  "$SERVER" www.vse.cz 2
```

## Notes

- **TLS certificate validation** is not performed — `+tls` uses opportunistic mode (RFC 7858 §4.1). The template tests protocol availability, not certificate validity.
- **DoH path** — `+https` uses the default `/dns-query` path. If the server uses a non-standard path, modify the script to add `+https=/custom-path`.
- **QUIC** requires a kdig build with QUIC support (available in knot-dnsutils ≥ 3.1 on most distributions).
- **Multiple DNS servers** — create one host per server. Each host uses its own interface address and can have independent `{$DNS.QUERIES}`, `{$DNS.PROTOCOLS}`, and `{$DNS.PROTO.QUERY}` macros.

## License

MIT
