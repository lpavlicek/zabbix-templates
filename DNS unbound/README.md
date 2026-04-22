# Zabbix Template: DNS unbound

A Zabbix 7.4 template for monitoring the [unbound](https://nlnetlabs.nl/projects/unbound/about/) recursive DNS resolver. Statistics are collected via `unbound-control stats_noreset` and converted to JSON by a Perl helper script, enabling efficient dependent-item collection with a single external call every 5 minutes.

---

## Contents

| File | Description |
|------|-------------|
| `DNS_unbound_template.yaml` | Zabbix template (export format 7.4) |
| `userparameter_unbound.conf` | Zabbix Agent UserParameter definitions |
| `unbound-stats_to_json.pl` | Perl script: converts `unbound-control` output to JSON |

---

## Requirements

- **Zabbix** 7.4 or later
- **Zabbix Agent** (classic or Agent 2) installed on the monitored host
- **unbound** with `unbound-control` configured and accessible
- **Perl** 5.26+ with the `JSON` module (`libjson-perl` on Debian/Ubuntu, `perl-JSON` on RHEL/Fedora)
- The Zabbix Agent process must have permission to run `unbound-control` (see [Permissions](#permissions))

---

## Installation

### 1. Deploy the Perl script

```bash
mkdir -p /etc/zabbix/scripts/unbound
cp unbound-stats_to_json.pl /etc/zabbix/scripts/unbound/
chmod 755 /etc/zabbix/scripts/unbound/unbound-stats_to_json.pl
```

### 2. Install the UserParameter file

```bash
cp userparameter_unbound.conf /etc/zabbix/zabbix_agentd.d/
# or for Agent 2:
cp userparameter_unbound.conf /etc/zabbix/zabbix_agent2.d/
```

Restart the Zabbix Agent afterwards:

```bash
systemctl restart zabbix-agent   # or zabbix-agent2
```

### 3. Import the template into Zabbix

In the Zabbix web UI go to **Data collection → Templates → Import** and upload `DNS_unbound_template.yaml`.

### 4. Assign the template to a host

Navigate to the host configuration, open the **Templates** tab, and link **DNS unbound**.

---

## Permissions

`unbound-control` requires access to the control socket and TLS keys. The Zabbix Agent typically runs as user `zabbix`. Grant access using one of the following approaches:

**Option A – sudo (recommended)**

Add to `/etc/sudoers.d/zabbix-unbound`:

```
zabbix ALL=(root) NOPASSWD: /usr/sbin/unbound-control stats_noreset
zabbix ALL=(root) NOPASSWD: /usr/sbin/unbound-control get_option *
zabbix ALL=(root) NOPASSWD: /usr/sbin/unbound-control status
```

Then update the UserParameter commands to use `sudo`:

```
UserParameter=unbound.stats_noreset,sudo /usr/sbin/unbound-control stats_noreset 2>&1 | ...
```

**Option B – unbound-control-setup / group membership**

Add the `zabbix` user to the group that owns the unbound control socket, or re-run `unbound-control-setup` to generate keys accessible to the agent user.

---

## How It Works

```
Zabbix Agent
  └─ UserParameter: unbound.stats_noreset
       └─ unbound-control stats_noreset
            └─ unbound-stats_to_json.pl   →  JSON blob  →  Zabbix master item
                                                              └─ ~80 dependent items
                                                                   (JSONPath + CHANGE_PER_SECOND)
```

The master item `unbound.stats_noreset` runs every **5 minutes** and stores the raw JSON (history disabled). All metric items are `DEPENDENT` and extract their value from this single JSON blob using a JSONPath preprocessing step, avoiding repeated calls to `unbound-control`.

### What the Perl script does

- Reads `unbound-control stats_noreset` output from stdin
- Normalises keys: periods are replaced with underscores (`mem.cache.message` → `mem_cache_message`)
- Collapses the 38-bucket response-time histogram into 10 human-readable buckets (`0ms.16ms`, `16ms.32ms`, …, `4s.512s`)
- Guarantees a **fixed set of keys** regardless of unbound version: missing counters are emitted as `0`, preventing JSONPath errors in Zabbix
- Groups uncommon DNS RR types into a single `num_query_type_other` counter
- If `unbound-control` returns an error, emits `{"error_msg": "..."}` so the dedicated error-message item and trigger fire

---

## Collected Metrics

### Response-time histogram (10 buckets, `qps`)
Queries answered with recursive resolution time in each bucket: `0–16 ms`, `16–32 ms`, `32–64 ms`, `64–128 ms`, `128–256 ms`, `256–512 ms`, `512 ms–1 s`, `1–2 s`, `2–4 s`, `4–512 s`.

### Cache
`infra_cache_count`, `key_cache_count`, `mem_cache_message`, `mem_cache_rrset`, `msg_cache_count`, `rrset_cache_count` — entry counts and memory usage of all cache subsystems.

### Memory
Per-module memory: `iterator`, `respip` (RPZ), `subnet` (ECS), `validator` (DNSSEC), `streamwait` (TCP), plus DNS-over-HTTPS buffers.

### Query counts (`qps`)
Total, cache hits/misses, prefetch, expired (stale), recursive replies, and various drop counters (rate-limited, timed-out, request-list exceeded, discard-timeout, wait-limit).

### DNS cookies (`qps`)
Client-only, valid, and invalid DNS cookies per second.

### DNSSEC (`qps`)
Secure answers, bogus answers, bogus RRsets, aggressive NOERROR/NXDOMAIN synthesis.

### Query types (`qps`)
A, AAAA, HTTPS, MX, NS, PTR, SOA, SRV, SSHFP, SVCB, TXT, other.

### Query flags (`qps`)
AA, AD, CD, QR, RA, RD, TC, Z.

### Transport (`qps`)
Incoming: TCP, TLS (DoT), HTTPS (DoH), IPv6. Outgoing: UDP, TCP.

### EDNS (`qps`)
Queries with EDNS present, with DO bit set, with ECS option.

### Performance
`total.recursion.time.avg`, `total.recursion.time.median`, `total.requestlist.avg`, `total.requestlist.max`, `total.requestlist.exceeded`, `total.requestlist.overwritten`.

### Security (`qps`)
`unwanted.queries`, `unwanted.replies` — refused/dropped or unsolicited traffic.

### General
`time.up` (uptime in seconds), `version` (unbound version string), `option.num-queries-per-thread` (config value, polled every 30 minutes).

---

## Triggers

| Name | Severity | Description |
|------|----------|-------------|
| Unbound: Error message | Average | `unbound-control` returned an error (e.g. unbound not running) |
| Unbound: Uptime < 1h | Info | Process was recently (re)started |
| Unbound: Average recursion time > 500ms | Warning | Sustained high recursion latency |
| Unbound: Number of overwritten requests has exceeded limit | Info | Request list overflow — server under load |
| Request list maximum length > 75% num-queries-per-thread | Warning | Request list nearing capacity |

The last trigger is a **global trigger** (not attached to a single item) comparing `total.requestlist.max` against `option.num-queries-per-thread`.

---

## Macros

| Macro | Default | Description |
|-------|---------|-------------|
| `{$UNBOUND.REQUESTLIST_OVERWRITTEN_LIMIT}` | `0` | Threshold for the "overwritten requests" trigger. Set to a small positive integer to suppress noise on busy servers. |

---

## Dashboards

The template includes a built-in dashboard **Unbound** with two pages:

**Page 1 — Overview**
Cache efficiency · Request list size · Memory usage · Unwanted traffic · Recursion performance · Ratelimit · Cache entry counts · DNSSEC · Issues & security

**Page 2 — Query stats**
Queries overview · Query types (A/AAAA/HTTPS/MX/NS/PTR and SOA/SRV/SSHFP/SVCB/TXT/other) · Answers by RCODE · Transport protocols (incoming and outgoing) · Response-time histogram · IPv6 queries

---

## Known Limitations and Notes

- The template targets **Zabbix 7.4**. Earlier versions may not support all preprocessing steps or dashboard widget options used.
- The `unbound.stats_noreset` master item uses `stats_noreset` (counters are **not** reset on read), so all rate metrics are computed via the `CHANGE_PER_SECOND` preprocessing step. If you switch to `stats` (which resets counters), remove `CHANGE_PER_SECOND` from all dependent items.
- Per-thread counters (`thread0.*`, `thread1.*`, …) are **not** included; the script aggregates only the `total.*` counters already computed by unbound.
- The `unbound.version` item has a typo in its name (`Unboud:` instead of `Unbound:`) — this is harmless but worth fixing if you export the template.
- Items `histogram.128ms.256ms` and `histogram.4s.512s` are missing the explicit `value_type: FLOAT` field present on the other histogram items. Zabbix will default to `FLOAT` in practice, but adding it explicitly makes the template more consistent.

---

## Compatibility

Tested against **unbound 1.20 – 1.23**. The `total_num_queries_discard_timeout` and `total_num_queries_wait_limit` counters were introduced in unbound 1.23; on older versions the script emits `0` for these.

---

## License

This template is provided as-is, free to use and modify. Attribution appreciated but not required.

---

## Author

lpavlicek — template version 7.4-1
