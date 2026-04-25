# Ollama by Zabbix agent

Zabbix template for monitoring [Ollama](https://ollama.com/) — a local LLM inference server.
Monitors service availability, inference performance, model inventory, VRAM usage, and process-level resource consumption via Zabbix agent UserParameters backed by a shell wrapper script.

## Requirements

| Component | Version |
|---|---|
| Zabbix server / proxy | 7.4 or later |
| Zabbix agent | 2.0 or later (classic agent or agent2) |
| Ollama | 0.3 or later |
| OS | Ubuntu 22.04 / 24.04, Debian 12 (other systemd-based Linux distributions should work) |
| Shell | bash 4.0 or later |
| curl | any version supporting `--write-out` and `--output` |

`UnsafeUserParameters=1` is **not** required. All argument validation is handled inside the wrapper script.

## Files

```
zbx_export_templates_ollama.yaml   Zabbix template (import into Zabbix frontend)
zabbix_ollama.sh                   Wrapper script deployed on every monitored host
userparameter_ollama.conf          Zabbix agent UserParameter definitions
```

## Setup

### 1. Deploy the wrapper script

Copy the script to each host running Ollama and set appropriate permissions.

```bash
cp zabbix_ollama.sh /etc/zabbix/scripts/ollama/zabbix_ollama.sh
chmod 0755 /etc/zabbix/scripts/ollama/zabbix_ollama.sh
chown root:root /etc/zabbix/scripts/ollama/zabbix_ollama.sh
```

The script must be executable by the `zabbix` user. It does not require root privileges at runtime.

### 2. Deploy the UserParameter configuration

```bash
cp userparameter_ollama.conf /etc/zabbix/zabbix_agentd.d/
```

Then reload the agent:

```bash
# Classic agent
systemctl reload zabbix-agent

# Agent 2
systemctl reload zabbix-agent2
```

Verify the UserParameters are recognised:

```bash
zabbix_agentd -t 'ollama.version.get[11434]'
zabbix_agentd -t 'ollama.models.available.get[11434]'
zabbix_agentd -t 'ollama.models.loaded.get[11434]'
zabbix_agentd -t 'ollama.probe.get[11434,gemma3:270m,0]'
```

Each command should return a JSON object. If Ollama is not running, the script returns `{"error":"curl_failed","curl_exit_code":7}`.

### 3. Pull the probe model on every monitored host

The inference probe sends a minimal request to a real model. The model must be present locally before the template is linked to the host.

```bash
ollama pull gemma3:270m
```

If you prefer a different model, change the default value of `{$OLLAMA.PROBE.MODEL}` either in the template (globally) or as a host-level macro override.

### 4. Import the template

In the Zabbix frontend go to **Data collection → Templates** and import `zbx_export_templates_ollama.yaml`.

### 5. Link the template to hosts

Go to the host configuration, open the **Templates** tab, and add **Ollama by Zabbix agent**.

Review the macros listed in the section below before or immediately after linking.

## Macros

All template parameters are stored as user macros. They can be overridden at the host level to support different configurations on different hosts.

| Macro | Default | Description |
|---|---|---|
| `{$OLLAMA.PORT}` | `11434` | TCP port the Ollama API listens on. |
| `{$OLLAMA.PROBE.MODEL}` | `gemma3:270m` | Model used for the inference probe. Must be pulled on every monitored host. Use a small, fast model. |
| `{$OLLAMA.PROBE.KEEP_ALIVE}` | `30m` | How long to keep the probe model loaded in VRAM after the test. `0` = unload immediately, `-1` = keep permanently, `30m` = 30 minutes. |
| `{$OLLAMA.PROBE.TOTAL_DURATION.MAX.WARN}` | `1` | Warning threshold for probe `total_duration` in seconds. Adjust to match the expected inference speed on the given hardware (see [Tuning](#tuning)). |

## Items

### Service availability

| Item | Key | Interval | Description |
|---|---|---|---|
| Ollama: Alive | `net.tcp.service[http,localhost,{$OLLAMA.PORT}]` | 2m | TCP port reachability check. Returns 1 (up) or 0 (down). Does not invoke the API. |

### Available models

| Item | Key | Interval | Description |
|---|---|---|---|
| Ollama: Get available models | `ollama.models.available.get[{$OLLAMA.PORT}]` | 10m | Master item. Raw JSON from `GET /api/tags`. History not stored. |
| Ollama: Available models count | `ollama.models.available.count` | dependent | Number of models pulled and stored on disk. |
| Ollama: Available models - names | `ollama.models.available.names` | dependent | Comma-separated list of available model names. |

### Loaded models (VRAM)

| Item | Key | Interval | Description |
|---|---|---|---|
| Ollama: Get loaded models | `ollama.models.loaded.get[{$OLLAMA.PORT}]` | 5m | Master item. Raw JSON from `GET /api/ps`. History not stored. |
| Ollama: Loaded models count | `ollama.models.loaded.count` | dependent | Number of models currently loaded in memory. |
| Ollama: Loaded models names | `ollama.models.loaded.names` | dependent | Comma-separated list of loaded model names. |
| Ollama: Loaded models VRAM usage | `ollama.models.loaded.vram` | dependent | Total VRAM consumed by all loaded models, in bytes. |

### Inference probe

| Item | Key | Interval | Description |
|---|---|---|---|
| Ollama: Get probe response | `ollama.probe.get[{$OLLAMA.PORT},{$OLLAMA.PROBE.MODEL},{$OLLAMA.PROBE.KEEP_ALIVE}]` | 10m | Master item. Sends `POST /api/generate` with prompt `"1+1"`. Verifies end-to-end inference capability. History not stored. |
| Ollama: Probe response error | `ollama.probe.error` | dependent | Error string extracted from the probe response. Empty on success. |
| Ollama: Probe response - no response (timeout/empty) | `ollama.probe.no_response` | dependent | Returns 1 when the probe received no usable response (transport error or empty body). |
| Ollama: Probe load_duration | `ollama.probe.load_duration` | dependent | Time spent loading the model for the probe, in seconds. Zero if the model was already in VRAM. |
| Ollama: Probe total_duration | `ollama.probe.total_duration` | dependent | Total wall-clock time for the probe request, in seconds. |

### Version

| Item | Key | Interval | Description |
|---|---|---|---|
| Ollama: Version | `ollama.version.get[{$OLLAMA.PORT}]` | 30m | Ollama server version string (e.g. `0.5.12`). Stored only on change (heartbeat 12h). |

### Process metrics

| Item | Key | Interval | Description |
|---|---|---|---|
| Ollama: CPU utilization | `proc.cpu.util[ollama]` | 2m | CPU usage of all `ollama` processes, in percent. |
| Ollama: Memory used | `proc.mem[ollama]` | 2m | RSS memory consumed by all `ollama` processes, in bytes. Does not include VRAM. |
| Ollama: Number of processes | `proc.num[ollama]` | 2m | Number of running `ollama` processes. Normally 1. |

## Triggers

| Trigger | Severity | Description |
|---|---|---|
| Ollama: Service is not responding on port {$OLLAMA.PORT} | High | Ollama TCP port is unreachable. Service is likely stopped or crashed. |
| Ollama: No ollama process found | High | No process named `ollama` is running. Independent of the TCP check; may fire slightly earlier. |
| Ollama: Failed to retrieve available models list | Warning | `/api/tags` returned an unexpected response (`available.count = -1`). Depends on the port trigger. |
| Ollama: Probe request returned an error | Average | Probe response contains a non-empty `error` field. Covers API errors, HTTP errors (e.g. 503), network timeouts, and empty responses. Requires manual close. Depends on the port trigger. |
| Ollama: Probe response - no response (timeout/empty) | High | Probe received no usable data at all (`curl_failed` or `empty_response`). Indicates the engine is unresponsive or overloaded. Requires manual close. Depends on the port trigger. |
| Ollama: Probe total_duration exceeds {$OLLAMA.PROBE.TOTAL_DURATION.MAX.WARN} | Warning | Inference took longer than the configured threshold. Requires manual close. Depends on the port trigger. |

### Trigger dependencies

```
Ollama: Service is not responding on port {$OLLAMA.PORT}
  └── Ollama: Failed to retrieve available models list
  └── Ollama: Probe request returned an error
  └── Ollama: Probe response - no response (timeout/empty)
  └── Ollama: Probe total_duration exceeds ...
```

The process count trigger (`No ollama process found`) has no dependency on the port trigger intentionally — it is an independent check and may fire briefly before the TCP check detects the same outage.

## Error handling in the wrapper script

The script `zabbix_ollama.sh` normalises all failure modes into a JSON object that Zabbix preprocessing can act on. The table below lists all possible `error` values.

| `error` value | Cause | Detected by |
|---|---|---|
| `curl_failed` | Network error or timeout (curl non-zero exit code). `curl_exit_code` field contains the curl exit code. | `ollama.probe.no_response` → trigger High |
| `empty_response` | HTTP 200 returned but response body was empty. | `ollama.probe.no_response` → trigger High |
| `http_error` | HTTP status code other than 200 (e.g. 400, 404, 500, 503). `http_status` field contains the numeric code. Body included when it is valid JSON. | `ollama.probe.error` → trigger Average |
| `invalid_json` | Response body does not start with `{` or `[`. | `ollama.probe.error` → trigger Average |
| `invalid_action` | Internal: unknown action argument. Should not occur in normal operation. | — |
| `invalid_port` | Internal: port argument failed validation. Should not occur in normal operation. | — |
| `invalid_model` | Internal: model argument contains disallowed characters. | — |
| `invalid_keep_alive` | Internal: keep_alive argument failed validation. | — |
| `missing_model` | Internal: probe called without a model argument. | — |

### Timeout values

| Setting | Value | Location |
|---|---|---|
| curl connect timeout | 2 s | `zabbix_ollama.sh` |
| curl max time (total) | 3 s | `zabbix_ollama.sh` |
| Zabbix agent item timeout | 4 s | Item configuration in template |

The Zabbix agent timeout is intentionally set 1 second above the curl max time to allow the script to finish cleanly and return a structured error JSON rather than being killed mid-execution.

## Tuning

### Probe model selection

Use the smallest model available on all monitored hosts. Smaller models load faster, consume less VRAM during the probe, and make the `total_duration` threshold easier to calibrate.

Recommended options (in order of size): `smollm2:135m`, `gemma3:270m`, `qwen2.5:0.5b`.

If different hosts run different hardware, set `{$OLLAMA.PROBE.MODEL}` and `{$OLLAMA.PROBE.TOTAL_DURATION.MAX.WARN}` as host-level macro overrides rather than changing the template default.

### total_duration threshold

Typical values to use as a starting point for `{$OLLAMA.PROBE.TOTAL_DURATION.MAX.WARN}`:

| Hardware | Model | Expected total_duration |
|---|---|---|
| NVIDIA GPU (mid-range or better) | gemma3:270m | 0.2 – 0.5 s |
| Apple Silicon (M-series) | gemma3:270m | 0.3 – 0.8 s |
| CPU only (modern server) | gemma3:270m | 5 – 20 s |
| CPU only (low-power / ARM) | gemma3:270m | 20 – 60 s |

Run a few manual probes to establish a baseline before setting the threshold:

```bash
for i in 1 2 3 4 5; do
    /etc/zabbix/scripts/ollama/zabbix_ollama.sh probe 11434 gemma3:270m 0 \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(round(d.get('total_duration',0)/1e9,3), 's')"
done
```

### keep_alive and VRAM

The default value `30m` keeps the probe model in VRAM for 30 minutes after each probe. This avoids the model reload overhead on the next probe cycle (10 minutes), at the cost of permanently occupying VRAM.

If VRAM is scarce, set `{$OLLAMA.PROBE.KEEP_ALIVE}` to `0` to unload the model immediately after each probe. The `load_duration` metric will then reflect the full model load time on every probe.

## Dashboard

The template includes a built-in dashboard named **Ollama** with the following widgets:

- Service status (alive indicator)
- Available model count
- Loaded model count
- Number of ollama processes
- Ollama version
- Probe response duration graph (`load_duration` + `total_duration`)
- Memory usage graph (RSS)
- CPU utilization graph
- Ollama model count graph (available vs. loaded)
- VRAM usage graph

## Tested with

- Ollama 0.5.x on Ubuntu 22.04 and 24.04
- Zabbix 7.4 with classic Zabbix agent
- Models: gemma3:270m, llama3.2:3b, mistral:7b
