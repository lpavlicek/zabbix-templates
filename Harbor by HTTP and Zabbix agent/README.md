# Harbor by HTTP and Zabbix agent

Zabbix 7.4 template for monitoring [Harbor](https://goharbor.io/) (container registry).

Two independent checks are combined in a single template:

1. **Health check** — `GET {$HARBOR.URL}/api/v2.0/health`, polled directly by the Zabbix server/proxy
   using an HTTP agent item. No Zabbix agent is required for this part.
2. **Prometheus metrics** — scraped from the Harbor core metrics endpoint
   (`http://127.0.0.1:{$HARBOR.METRICS.PORT}/metrics`), which by default only listens on
   `localhost` on the Harbor host itself. This part requires a Zabbix agent (2) installed on the
   Harbor host with a small `UserParameter` that runs `curl` against the local endpoint (see
   [Setup](#setup) below).

## Files

- `harbor_template.yaml` — the template, ready to import (Data collection → Templates → Import).
- `README.md` — this file.

## What is monitored

### Health API (`/api/v2.0/health`)

| Item | Description |
|---|---|
| `Harbor: Overall health status` | Overall status field from the health API (`healthy`/`unhealthy`). |
| `Harbor: Component {#COMPONENT} health status` (discovered) | Per-component status (`core`, `database`, `jobservice`, `portal`, `redis`, `registry`, `registryctl`, `trivy`, ...). Discovered automatically from the API response, so new/removed components are picked up without editing the template. |

Triggers fire (severity **High**) when the overall status, or any individual component, is not
`healthy`.

### Prometheus metrics (`/metrics`, localhost only)

Selected for functional/reliability monitoring and for service usage/capacity monitoring:

| Item | Metric | Purpose |
|---|---|---|
| `Harbor: Running status (Prometheus)` | `harbor_health` | Cross-check of overall health from the metrics side. |
| `Harbor: Component {#COMPONENT} up (Prometheus)` (discovered) | `harbor_up{component=...}` | Per-component up/down, independent source from the health API. |
| `Harbor: Queue {#QUEUE_TYPE} - pending tasks` (discovered) | `harbor_task_queue_size{type=...}` | Job service backlog per queue type (e.g. `GARBAGE_COLLECTION`, `IMAGE_SCAN`, `REPLICATION`, `RETENTION`, `WEBHOOK`, ...). |
| `Harbor: Queue {#QUEUE_TYPE} - oldest pending task age` (discovered) | `harbor_task_queue_latency{type=...}` | How long the oldest pending job has been waiting — indicates a stuck job service. |
| `Harbor: Scheduled tasks` | `harbor_task_scheduled_total` | Number of scheduled (periodic) jobs, informational. |
| `Harbor: Projects total` | `harbor_statistics_total_project_amount` | Usage/growth. |
| `Harbor: Repositories total` | `harbor_statistics_total_repo_amount` | Usage/growth. |
| `Harbor: Storage used total` | `harbor_statistics_total_storage_consumption` | Usage/capacity. |
| `Harbor: Project {#PROJECT} - repositories` (discovered) | `harbor_project_repo_total{project_name=...}` | Per-project usage. |
| `Harbor: Project {#PROJECT} - artifacts` (discovered) | `harbor_project_artifact_total{project_name=...}` | Per-project usage, summed across artifact types. |
| `Harbor: Project {#PROJECT} - quota used` / `- quota limit` (discovered) | `harbor_project_quota_usage_byte`, `harbor_project_quota_byte` | Per-project storage quota, drives the quota-usage-high trigger. |
| `Harbor: Project {#PROJECT} - artifact pulls` (discovered) | `harbor_artifact_pulled{project_name=...}` | Per-project pull activity/popularity. |

Metrics that are specific to the Go runtime/exporter process itself (`go_*`, `process_*`,
`promhttp_*`) were intentionally left out to keep the template focused on Harbor's own
functionality and usage — they can be added later if needed.

Discovery rules use Zabbix's `Prometheus to JSON` preprocessing together with `lld_macro_paths`,
so new projects, queue types, or components appear automatically without editing the template.

### Triggers

| Trigger | Severity | Condition |
|---|---|---|
| Overall health status is not healthy | High | Health API `status` != `healthy` |
| Component {#COMPONENT} is not healthy | High | Health API component status != `healthy` (per component) |
| Reports not running (Prometheus metrics) | High | `harbor_health` == 0 |
| Component {#COMPONENT} is down (Prometheus) | High | `harbor_up{component=...}` == 0 (per component) |
| Too many pending tasks in queue {#QUEUE_TYPE} | Warning | queue size > `{$HARBOR.QUEUE.SIZE.WARN}` for 10 min (per queue type) |
| Queue {#QUEUE_TYPE} has stale pending tasks | Warning | oldest pending task age > `{$HARBOR.QUEUE.LATENCY.WARN}` for 10 min (per queue type) |
| Project {#PROJECT} storage quota usage is high | Warning | quota used / quota limit > `{$HARBOR.QUOTA.USAGE.WARN}` % (skipped for unlimited quota, `-1`) |

There are intentionally no "no data" triggers. The health-API and Prometheus-based triggers are
independent of each other by design (they use different data sources), so both may fire for the
same underlying incident — this is expected and gives two independent confirmations of a problem.

## Macros

| Macro | Default | Description |
|---|---|---|
| `{$HARBOR.URL}` | `https://harbor.example.com` | Base URL of Harbor (scheme + host, no trailing slash). |
| `{$HARBOR.METRICS.PORT}` | `9090` | Port of the Harbor core Prometheus metrics endpoint (`metric_port` in `harbor.yml`). |
| `{$HARBOR.QUEUE.SIZE.WARN}` | `50` | Pending-task threshold per job queue. Supports macro context, e.g. `{$HARBOR.QUEUE.SIZE.WARN:"WEBHOOK"}`. |
| `{$HARBOR.QUEUE.LATENCY.WARN}` | `300` (seconds) | Oldest-pending-task-age threshold per job queue. Supports macro context. |
| `{$HARBOR.QUOTA.USAGE.WARN}` | `90` (percent) | Per-project storage quota usage threshold. |

## Setup

1. **Import** `harbor_template.yaml` in Zabbix (Data collection → Templates → Import). The
   template group `lpavlicek templates` is created automatically if it does not exist yet.
2. **Link** the template to the host representing the Harbor instance.
3. Set **`{$HARBOR.URL}`** to the base URL Harbor is reachable at (e.g. the same host you'd use
   for `curl https://<host>/api/v2.0/health`).
4. **Install a Zabbix agent (2)** on the Harbor host itself (required only for the Prometheus
   metrics part — the health check does not need it), and add the following UserParameter, e.g. in
   `/etc/zabbix/zabbix_agent2.d/userparameter_harbor.conf`:

   ```
   UserParameter=harbor.metrics.raw[*],curl -s --max-time 5 http://127.0.0.1:$1/metrics
   ```

   Restart the agent after adding the file. This mirrors exactly the `curl` command you already
   use to verify the endpoint manually:

   ```
   curl -s --max-time 5 http://127.0.0.1:9090/metrics
   ```

5. Make sure the Zabbix host has a working **Zabbix agent interface** so the passive item
   `Harbor: Get Prometheus metrics` can reach it; if the metrics port on your Harbor installation
   differs from `9090`, adjust `{$HARBOR.METRICS.PORT}` accordingly.
6. Adjust the threshold macros as needed (globally or per `{#QUEUE_TYPE}` / `{#PROJECT}` using
   macro context) once the template has had a chance to discover the actual queue types/projects.

### A note on TLS

The HTTP agent item for the health check does **not** verify the TLS certificate (Zabbix's
default for HTTP agent items). This is intentional — certificate expiry/validity for Harbor is
already covered by a separate SSL-check template, so this template stays focused on
application-level health rather than duplicating that check.

## Reference

- Harbor documentation: https://goharbor.io/docs/
- Harbor health API: `GET /api/v2.0/health`
- Harbor Prometheus metrics: enabled via `metric.enabled: true` in `harbor.yml` (default port
  `9090`, bound to `127.0.0.1` unless changed).
