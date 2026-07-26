# LiteLLM Proxy — Zabbix 7.4 Template

Monitoring template for a self-hosted [LiteLLM](https://www.litellm.ai/) proxy, running as a
systemd service with a Zabbix agent installed on the same host, and fronted by nginx for
external access.

- Template group: `lpavlicek templates`
- Vendor: `lpavlicek`
- Template name: `LiteLLM Proxy`
- File: `zbx_export_templates.yaml`

## Scope

Covered:

- systemd unit / process / TCP port availability
- `/health/liveliness` and `/health/readiness` endpoints
- end-to-end functional test — a real chat completion request against a configured model

Deliberately **not** covered:

- Prometheus `/metrics` (request rate, latency histograms, error rate)
- token usage / spend tracking

Both are available directly through the LiteLLM web UI and were explicitly out of scope for
this template.

## Requirements

- Zabbix agent (classic or Agent 2) installed **on the LiteLLM host itself**.
- LiteLLM proxy running as a systemd service.
- `store_model_in_db: true` is assumed for the description of `litellm.health.readiness.db`,
  but the item itself works regardless of how models are configured.
- A dedicated LiteLLM virtual API key for the functional test (see below) — do not reuse the
  master key.
- Network path from the **Zabbix server/proxy** (not the agent) to the public URL, since the
  functional test is a web scenario and web scenarios are always executed by the server/proxy,
  never by the Zabbix agent.

## Why two different base URLs

| Macro | Value (default) | Used by | Why |
|---|---|---|---|
| `{$LITELLM.URL}` | `http://localhost:4000` | liveliness, readiness | Checked locally by the Zabbix agent, independent of nginx/TLS/DNS. If nginx breaks, these stay green — correctly showing that the LiteLLM process itself is fine. |
| `{$LITELLM.PUBLIC_URL}` | `https://litellm.vse.cz` | functional test (web scenario) | Goes through nginx, exactly like a real user request. If nginx, the TLS certificate, or routing breaks, this is what will catch it. |

## Why `web.page.get` instead of an HTTP agent item for health checks

HTTP agent items are polled by the **Zabbix server/proxy**, not by the local agent. Since
`{$LITELLM.URL}` points at `localhost`, an HTTP agent item would try to reach the *Zabbix
server's* own localhost, not the LiteLLM host. `web.page.get` is executed by the **Zabbix
agent on the monitored host**, so `localhost` correctly resolves there.

The trade-off: `web.page.get` returns the full raw HTTP response (status line + headers +
body), with no option to return the body only. For `litellm.health.liveliness.raw` this
doesn't matter — the dependent item just searches for the substring `alive` anywhere in the
raw text. For `litellm.health.readiness.raw` it does matter, since the dependent items run
JSONPath against the body — so a `REGEX` preprocessing step (`\{.*\}`) strips everything
before the JSON object before it is stored, regardless of the returned HTTP status code.

## Items

| Item | Key | Notes |
|---|---|---|
| Systemd unit state | `systemd.unit.info["{$LITELLM.SERVICE_NAME}",ActiveState]` | Root-cause check; most triggers depend on this one |
| Process count | `proc.num[,,,"{$LITELLM.PROCESS.CMDLINE}"]` | Matches by cmdline, not process name (runs as `python3`) |
| Process CPU utilization | `proc.cpu.util[,,,"{$LITELLM.PROCESS.CMDLINE}"]` | Informational only |
| Process memory (RSS) | `proc.mem[,,sum,"{$LITELLM.PROCESS.CMDLINE}",rss]` | Informational only |
| TCP port status | `net.tcp.port[,{$LITELLM.PORT}]` | |
| Liveliness (raw) | `web.page.get["{$LITELLM.URL}/health/liveliness"]` | Master item, `history: 0` |
| Liveliness | `litellm.health.liveliness` | Dependent, boolean (1/0) via regex |
| Readiness (raw) | `web.page.get["{$LITELLM.URL}/health/readiness"]` | Master item, `history: 0`, strips headers via regex |
| Readiness status | `litellm.health.readiness.status` | Dependent, JSONPath `$.status` |
| Database connection status | `litellm.health.readiness.db` | Dependent, JSONPath `$.db` |
| Functional test | web scenario `LiteLLM functional test` | Real `POST {$LITELLM.PUBLIC_URL}/v1/chat/completions` against `{$LITELLM.TEST_MODEL}` |

## Triggers

Every trigger has a `description` field with a short explanation and a suggested first
diagnostic step — visible in the Problems view. Most triggers **depend** on
`LiteLLM: systemd unit {$LITELLM.SERVICE_NAME} is not active` (and, where relevant, on
`LiteLLM: process is not running`) so that a single outage produces one root-cause alert
instead of five simultaneous ones.

| Trigger | Severity |
|---|---|
| systemd unit is not active | High |
| process is not running | High |
| no data from Zabbix agent for 10m (process count) | Warning |
| port `{$LITELLM.PORT}` is not listening | High |
| proxy liveliness check failed | High |
| no data from liveliness check for 10m | Warning |
| proxy is not ready to accept requests | High |
| database connection is down | High |
| no data from readiness check for 10m | Warning |
| functional test against model `{$LITELLM.TEST_MODEL}` failed | High |
| functional test response time exceeds `{$LITELLM.FUNC_TEST.MAX_RESPONSE_TIME}`s | Warning |

## Macros — set these after import

| Macro | Default | Must be changed? |
|---|---|---|
| `{$LITELLM.URL}` | `http://localhost:4000` | Only if the proxy listens elsewhere |
| `{$LITELLM.PUBLIC_URL}` | `https://litellm.vse.cz` | **Yes**, if the public hostname differs |
| `{$LITELLM.PORT}` | `4000` | Only if changed from default |
| `{$LITELLM.SERVICE_NAME}` | `litellm.service` | Only if the unit is named differently |
| `{$LITELLM.PROCESS.CMDLINE}` | `litellm` | Only if the cmdline pattern doesn't match |
| `{$LITELLM.TEST_MODEL}` | `gemma3:270m` | Only if a different canary model is preferred |
| `{$LITELLM.TEST_API_KEY}` | *(empty, Secret text)* | **Yes, required** — dedicated virtual key, scoped to `{$LITELLM.TEST_MODEL}` only |
| `{$LITELLM.HTTP.TIMEOUT}` | `10s` | Rarely |
| `{$LITELLM.FUNC_TEST.TIMEOUT}` | `20s` | Match your proxy/model timeout |
| `{$LITELLM.FUNC_TEST.MAX_RESPONSE_TIME}` | `5` (seconds) | Tune based on observed latency for `{$LITELLM.TEST_MODEL}` |

## Known limitations

- The aggregate `/health` endpoint (model-level healthy/unhealthy counts) is **not** used in
  this template. On this deployment it reports `healthy_count: 0, unhealthy_count: 0`
  regardless of the actual model list, because models are managed in the database
  (`store_model_in_db: true`) rather than in `config.yaml`. The functional test covers this gap
  by exercising a real model end to end instead.
- The functional test always calls the **same** canary model
  (`{$LITELLM.TEST_MODEL}`) — it does not cover the other 10+ models configured in the proxy.
- `web.page.get` has no option to return the body only (open Zabbix feature request
  [ZBXNEXT-8860](https://support.zabbix.com/browse/ZBXNEXT-8860)); the readiness item works
  around this with a regex preprocessing step.

## Changelog

- **7.4-1** — initial version: systemd/process/port checks, liveliness/readiness health
  checks via Zabbix agent, functional end-to-end test via web scenario, trigger dependency
  hierarchy.
