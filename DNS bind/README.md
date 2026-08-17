# DNS bind

Zabbix 7.4 template for monitoring an [ISC BIND](https://www.isc.org/bind/) DNS server via its `statistics-channels` HTTP/JSON API.

Unlike a typical Zabbix template, BIND is never polled directly by the Zabbix server/proxy. All items are trapper (`TRAP`) items: a small collector binary, `bind_stats_zabbix` (source included under [`scripts/`](#collector-script-bind_stats_zabbix)), runs locally on the BIND host, reads BIND's statistics JSON, and prints one Zabbix-sender bulk-input line per metric to stdout. A cron wrapper script pipes that output straight into `zabbix_sender`.

## Files

- `DNS bind.yaml` — the template, ready to import (Data collection → Templates → Import).
- `scripts/bind_stats.go` — source of the collector, compiled into the `bind_stats_zabbix` binary that runs on each BIND host.
- `scripts/preklad.sh` — build command (static Linux/amd64 binary, no CGO).
- `scripts/bind_stats_to_zabbix.sh` — example cron wrapper that runs the compiled binary and pipes its output into `zabbix_sender` over PSK-encrypted TLS.
- `README.md` — this file.

## Architecture

```
cron, every 5 minutes (on the BIND host, e.g. "*/5 * * * *  cd zabbix; ./bind_stats_to_zabbix.sh")
  │
  ▼
bind_stats_to_zabbix.sh
  │  runs the compiled collector and pipes its stdout into zabbix_sender
  ▼
bind_stats_zabbix  ── static Go binary; GETs http://127.0.0.1:8053/json/v1/server
  │  on success: prints "<host> bind.<key> <value>" for every mapped field, then
  │              "<host> bind.error_msg \"\"" last (clears any previous error)
  │  on HTTP/parse failure: prints only "<host> bind.error_msg \"<error text>\"" and stops
  ▼
zabbix_sender -i -  ── bulk-loads all lines from stdin, TLS/PSK to the Zabbix server
  │
  ▼
Zabbix server  ── each item key below is an independent TRAP item (no master/dependent item split)
```

## Collector script (`bind_stats_zabbix`)

Written in Go and built as a fully static binary (`CGO_ENABLED=0`, `-ldflags '-s -w'`, `-trimpath`, see `scripts/preklad.sh`) specifically because some of the BIND hosts it runs on don't allow installing packages — only running a binary the user drops in their own home directory via cron. A static Go binary has no runtime dependencies (no Python/Perl interpreter, no shared libraries to match), so "deploy" is just "copy the file and `chmod +x`".

- **Flags**: `-url` (statistics endpoint, default `http://127.0.0.1:8053/json/v1/server`), `-hostname` (Zabbix host name to send data as; defaults to the local FQDN via reverse DNS lookup, falling back to the plain hostname if that fails or isn't set explicitly).
- **Output**: Zabbix sender's plain-text bulk input format, one `<hostname> <key> <value>` line per metric, meant to be piped straight into `zabbix_sender -i -` (see `scripts/bind_stats_to_zabbix.sh`) rather than shelling out per metric.
- **Field mapping**: pulls `version`, `boot-time`, `config-time` (parsed from BIND's `2006-01-02T15:04:05.000Z` timestamp format into a Unix timestamp), all of `nsstats`, and a fixed set of `qtypes` — everything not in that fixed set is summed into `bind.qtypes.other`. Cross-checked programmatically against this template: the 33 `nsstats` keys and 13 named `qtypes` keys the collector emits match the template's items **exactly**, 1:1 in both directions — no field the collector sends is missing an item, and no item expects a field the collector doesn't send.
- **Error handling**: if the HTTP request or JSON parsing fails, the collector prints only `bind.error_msg` with the error text and exits immediately — none of the other items get a new value that run (so on a persistent outage, `bind.nsstats.Response` etc. eventually go stale and the "no data" trigger fires, on top of the immediate `error_msg` trigger). On success, `bind.error_msg` is sent last with an explicit empty string, clearing the error trigger.

## What is monitored

### Server / general

| Item | Key | Units | Notes |
|---|---|---|---|
| Bind Boot-Time | `bind.boot-time` | `unixtime` | Time BIND (the `named` process) was last started. |
| Bind Config-time | `bind.config-time` | `unixtime` | Time of the last configuration reload/change in the running process. |
| Bind Software Version | `bind.version` | — | BIND version string. A change fires an informational trigger (useful for spotting version drift after upgrades). |
| Bind Error message when retrieving data | `bind.error_msg` | — (text) | Populated by the collector script when it fails to read/parse BIND's statistics; empty otherwise. Drives the `BIND: error retrieving statistics data` trigger. |

### Query/response counters (`nsstats`)

All counters below are cumulative since BIND startup on the BIND side; the template converts them to a rate with `CHANGE_PER_SECOND` preprocessing, so the stored/graphed value is "per second", not a running total.

| Item | Key | Units | Description |
|---|---|---|---|
| Requestv4 | `bind.nsstats.Requestv4` | req/s | Total DNS requests received via IPv4 (UDP + TCP). |
| Requestv6 | `bind.nsstats.Requestv6` | req/s | Total DNS requests received via IPv6 (UDP + TCP). |
| ReqTCP | `bind.nsstats.ReqTCP` | req/s | Requests received over TCP (low-level counter — also includes zone transfers, NOTIFY, DNS UPDATE; a single TCP connection can carry several requests). |
| QryTCP | `bind.nsstats.QryTCP` | qry/s | Queries received via TCP. |
| QryUDP | `bind.nsstats.QryUDP` | qry/s | Queries received via UDP. |
| ReqEdns0 | `bind.nsstats.ReqEdns0` | req/s | Requests that included EDNS0. |
| RespEDNS0 | `bind.nsstats.RespEDNS0` | resp/s | Responses sent with EDNS0. |
| ECSOpt | `bind.nsstats.ECSOpt` | req/s | Requests carrying an EDNS Client Subnet (ECS) option. |
| ReqTSIG | `bind.nsstats.ReqTSIG` | req/s | Requests with TSIG authentication. |
| RespTSIG | `bind.nsstats.RespTSIG` | resp/s | Responses with a TSIG (normally tracks `ReqTSIG`). |
| Response | `bind.nsstats.Response` | resp/s | Total responses sent. Also drives the "no data" trigger below. |
| QrySuccess | `bind.nsstats.QrySuccess` | qry/s | Successful queries (NOERROR with at least one record returned). |
| QryAuthAns | `bind.nsstats.QryAuthAns` | qry/s | Responses with the AA (Authoritative Answer) bit set. |
| QryNoauthAns | `bind.nsstats.QryNoauthAns` | qry/s | Responses without the AA bit (recursive answers or served from cache). |
| QryNxrrset | `bind.nsstats.QryNxrrset` | qry/s | NOERROR responses with no records of the requested type. |
| QryNXDOMAIN | `bind.nsstats.QryNXDOMAIN` | qry/s | NXDOMAIN responses (name does not exist). |
| QryReferral | `bind.nsstats.QryReferral` | qry/s | Referral responses (delegation to other nameservers). |
| QryFailure | `bind.nsstats.QryFailure` | qry/s | Other query failures (e.g. SERVFAIL), excluding NXDOMAIN. |
| QryDropped | `bind.nsstats.QryDropped` | qry/s | Queries dropped, most often due to rate limiting. |
| AuthQryRej | `bind.nsstats.AuthQryRej` | req/s | Requests for authoritative zones rejected. |
| RecQryRej | `bind.nsstats.RecQryRej` | req/s | Requests for recursive resolution rejected (recursion disabled or blocked by an `allow-recursion` ACL). |
| RateDropped | `bind.nsstats.RateDropped` | req/s | Responses completely discarded by rate limiting. |
| RateSlipped | `bind.nsstats.RateSlipped` | req/s | Responses where the TC (truncated) bit was set instead of being discarded, as a rate-limiting "slip" response. |
| TruncatedResp | `bind.nsstats.TruncatedResp` | resp/s | Responses for which the TC bit was set (client is expected to retry over TCP). |
| CookieIn | `bind.nsstats.CookieIn` | cookie/s | DNS cookies received (RFC 7873). |
| CookieNew | `bind.nsstats.CookieNew` | cookie/s | New cookie generated for a client (first contact). |
| CookieMatch | `bind.nsstats.CookieMatch` | cookie/s | Cookie successfully verified (status: good). |
| CookieNoMatch | `bind.nsstats.CookieNoMatch` | cookie/s | Cookie present but does not match any known client. |
| CookieBadTime | `bind.nsstats.CookieBadTime` | cookie/s | Cookie with an invalid timestamp (too old/too new). |
| QryBADCOOKIE | `bind.nsstats.QryBADCOOKIE` | cookie/s | BADCOOKIE responses sent (client is asked to resend with a fresh cookie). |
| XfrReqDone | `bind.nsstats.XfrReqDone` | req/s | Zone transfers (AXFR/IXFR) completed successfully. |
| XfrRej | `bind.nsstats.XfrRej` | req/s | Zone transfers rejected. |

`bind.nsstats.TCPConnHighWater` is the one gauge in this group — it is **not** rate-converted:

| Item | Key | Units | Description |
|---|---|---|---|
| TCPConnHighWater | `bind.nsstats.TCPConnHighWater` | conn | High-water mark: the maximum number of concurrent TCP connections seen since the counter was last reset. |

### Query type breakdown (`qtypes`)

One rate item (`CHANGE_PER_SECOND`, `qry/s`) per query type: `A`, `AAAA`, `CNAME`, `DNSKEY`, `DS`, `HTTPS`, `MX`, `NS`, `PTR`, `SOA`, `SRV`, `SVCB`, `TXT`, plus `other` (anything not covered by the named types). Keys follow the pattern `bind.qtypes.<TYPE>`.

## Triggers

| Trigger | Severity | Condition |
|---|---|---|
| `BIND: error retrieving statistics data` | Average | `bind.error_msg` is non-empty. Manual close. |
| `BIND: no response stats in the last 15 minutes` | Warning | `nodata()` on `bind.nsstats.Response` for 15 minutes. Depends on the trigger above, so it doesn't fire redundantly when the collector is already reporting an error. |
| `BIND: version changed` | Info | `bind.version` changed since the last check. Manual close, informational only. |

There are no configurable macros in this template — the 15-minute "no data" window and the 8h/2h "unchanged" heartbeats on `bind.error_msg`/`bind.version`/`TCPConnHighWater` are hardcoded. If your collector runs on a much longer or shorter interval than a few minutes, adjust the `nodata()` window in the trigger expression directly.

## Dashboard

The template ships a `Bind` dashboard page with per-topic graphs (requests, query results, TCP/UDP protocol split, TSIG, EDNS0/ECS, DNS cookies, rate limiting, zone transfers, two query-type breakdown graphs) plus single-value tiles for version, boot time, config reload time, the error message and the TCP connection high-water mark. It is imported automatically together with the template and needs no extra configuration.

There is also one classic graph, `DNS query types`, plotting all 14 `bind.qtypes.*` items together — kept separate from the dashboard for hosts/views that only use the legacy Graphs section.

## Requirements

- **BIND `statistics-channels`** enabled and reachable at `127.0.0.1:8053` (the collector's default `-url`). In `named.conf`:
  ```
  statistics-channels {
      inet 127.0.0.1 port 8053 allow { 127.0.0.1; };
  };
  ```
  BIND packages on Debian/Ubuntu/RHEL are normally built with JSON statistics support already enabled; no rebuild should be needed.
- **`zabbix_sender`** installed on the BIND host (part of `zabbix-sender`/`zabbix-get` packages on most distributions), and, if the PSK file is root/zabbix-owned, a `sudo -u zabbix` rule for it — see `scripts/bind_stats_to_zabbix.sh`.
- **A Go toolchain only on whatever machine builds the binary** — the BIND hosts themselves just need to be able to execute a static Linux/amd64 binary from cron; no compiler, no package installation rights, and no root are required on them. This is the whole reason the collector is a compiled Go binary rather than a Python/Perl script with a package dependency.
- **A per-host Zabbix trapper PSK** (Host → Encryption in Zabbix), since the observed deployments authenticate `zabbix_sender` with `--tls-connect psk`. Identity and secret file differ per host — that's expected, not a bug (see the two examples in `scripts/bind_stats_to_zabbix.sh`).

## Setup

1. Enable `statistics-channels` in BIND's configuration (see above) and reload/restart `named`.
2. Build the collector on a machine with Go installed: `cd scripts && ./preklad.sh`, which produces a static `bind_stats_zabbix` binary (`GOOS=linux GOARCH=amd64`). Copy just that binary (not the Go toolchain) to each BIND host.
3. On the BIND host, verify the endpoint directly first: `curl http://127.0.0.1:8053/json/v1/server` should return a JSON document containing `boot-time`, `config-time`, `version`, `nsstats` and `qtypes`. Then sanity-check the collector itself: `./bind_stats_zabbix` (no arguments) should print a page of `<hostname> bind.<key> <value>` lines to stdout, ending with `<hostname> bind.error_msg ""`.
4. In Zabbix, create the host's trapper PSK under Host → Encryption if it doesn't already exist, and export/copy the secret to the BIND host (e.g. `tls_psk_auto.secret`, permissions restricted to whichever user will run `zabbix_sender`).
5. Copy `scripts/bind_stats_to_zabbix.sh` next to the binary on the BIND host and edit `ZABBIX_SERVER` / `PSK_IDENTITY` / `PSK_FILE` for that host (see the two variants documented in the script's comments — some hosts run `zabbix_sender` directly with a locally-owned PSK file, others need `sudo -u zabbix` because the PSK file lives under `/etc/zabbix/` and is only readable by that user).
6. Add the cron job, e.g. `*/5 * * * *   cd zabbix; ./bind_stats_to_zabbix.sh` — a 5-minute interval is what's used in the observed deployments and lines up with the template's 15-minute "no data" trigger window.
7. In Zabbix: **Data collection → Templates → Import**, upload `DNS bind.yaml`. The template group `lpavlicek templates` is created automatically if it doesn't already exist.
8. Create/confirm the Zabbix host name matches exactly what the collector will send (the `-hostname` flag, i.e. the BIND host's FQDN by default), and link the `DNS bind` template to it. The host needs no interface (agent/SNMP) — all data arrives as trapper pushes.
9. After the first cron run, confirm data is arriving under **Monitoring → Latest data** for the host, and that the `Bind` dashboard renders.

## Troubleshooting

- **All items stay "no data" after import** — run `scripts/bind_stats_to_zabbix.sh` by hand on the BIND host and watch for errors; check that the cron job is actually firing (`grep CRON /var/log/syslog` or the user's mail); a Zabbix host name that doesn't match the collector's `-hostname` output or a wrong/expired PSK are the most common causes.
- **`BIND: error retrieving statistics data` trigger is firing** — check `bind.error_msg`'s value in Latest data; the collector populates it verbatim from a Go HTTP or JSON-decode error (e.g. `Chyba HTTP: ...`, `Chyba statusu: ...`, `Chyba parsování JSON: ...`) when it can't reach or parse `http://127.0.0.1:8053/json/v1/server` (BIND down, `statistics-channels` not enabled/reachable, or a JSON parsing error).
- **`BIND: no response stats in the last 15 minutes`** — the collector has stopped running (cron disabled, binary missing/not executable) or `zabbix_sender` is failing after the collector already ran successfully (check PSK/connectivity); the dependency on the error trigger above means this shouldn't fire redundantly with a known collector error, since the collector only ever fails to send `bind.nsstats.Response` together with everything else in the same run.
- **Values arrive under the wrong Zabbix host** — the collector defaults `-hostname` to a reverse-DNS lookup of the local hostname; if that resolves to something other than the exact Zabbix host name, pass `-hostname <exact Zabbix host name>` explicitly in the wrapper script.

## Review against Zabbix 7.4 recommendations and fixes

The template already had a filled-in `vendor` block (`lpavlicek`, `7.4-1`) and valid, unique UUIDs (58/58 checked as UUID4) — no changes needed there. Template-level tags (`component: dns`, `software: bind`) already match the convention used by the closest sibling template in this repository, `DNS unbound` (same `component`/`software` tag names, not the `class`/`target` pair used elsewhere in the repo) — left as-is rather than converted, since it's an established, deliberate pattern for this DNS sub-family. The one trigger dependency (`BIND: no response stats in the last 15 minutes` → `BIND: error retrieving statistics data`) was checked and its name/expression match the target trigger exactly.

One real gap was found and fixed:

1. **`bind.nsstats.TruncatedResp` had no visualization anywhere** — the item existed and collected data, but was referenced by neither the dashboard's 17 widgets nor the classic `DNS query types` graph (verified programmatically against every widget/graph item reference in the template). Added it as a fourth series to the dashboard's `Problematic / Rejected Queries` graph, alongside `QryDropped`/`QryFailure`/`AuthQryRej`/`RecQryRej`, since a rising truncation rate is the same kind of "something's wrong with responses" signal as those.

Since the collector's Go source was added to this repository, its field mapping could be checked directly rather than assumed: the 33 `nsstats` keys and 13 named `qtypes` keys `bind_stats_zabbix` sends match this template's items exactly, 1:1 in both directions (verified programmatically) — no missing or orphaned item on either side.

Not changed, noted only as an observation:
- There are no configurable macros — the `nodata()` window (15m) and the "unchanged" heartbeat windows (8h for `bind.error_msg`/`bind.version`, 2h for `TCPConnHighWater`) are hardcoded in the item/trigger definitions rather than exposed as `{$...}` macros. Fine as long as the collector's push interval stays in the few-minutes range (5 minutes in the observed deployments); if it changes significantly, edit those values directly.

## Reference

- BIND statistics channels overview: https://kb.isc.org/docs/aa-01123
- BIND Administrator Reference Manual, "Statistics" chapter (JSON `nsstats`/`qtypes`/`boot-time`/`config-time`/`version` fields): https://bind9.readthedocs.io/

## Changelog

### 7.4-1 (2026-08-17, review and minor fix)
- Placed into this repository.
- Confirmed 58/58 UUIDs valid and unique (UUID4).
- Confirmed the `BIND: no response stats...` trigger's dependency name/expression match its target trigger.
- Added the previously unvisualized `bind.nsstats.TruncatedResp` item to the `Problematic / Rejected Queries` dashboard graph.
- Added the `bind_stats_zabbix` collector's Go source, build script and an example cron wrapper under `scripts/`; rewrote the architecture, requirements, setup and troubleshooting sections around the real collector instead of a generic description, and confirmed its field mapping matches the template's items 1:1.
- Removed `scripts/bind_stats_old.go` (superseded revision, deleted by the template owner).
