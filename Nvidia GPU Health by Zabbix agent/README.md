# Nvidia GPU Health by Zabbix agent

Zabbix template for monitoring NVIDIA GPU health and compute applications (processes) via `nvidia-smi`. Tracks GPU driver state, NVLink errors, Xid kernel errors, persistence mode, and per-GPU compute process count and age — useful for detecting GPU failures and forgotten or stuck jobs on shared GPU servers.

Compatible with **Zabbix 7.4+**.

---

## Overview

The template combines two monitoring approaches:

- **Compute process monitoring** — a lightweight Python script deployed on the monitored host queries `nvidia-smi` and returns a JSON object with per-GPU process count and oldest-process age. Zabbix reads this JSON via a UserParameter and derives all monitored values from it using LLD (Low-Level Discovery).
- **GPU health monitoring** — additional UserParameters query `nvidia-smi` directly for GPU driver state, persistence mode, and NVLink error counters. Kernel Xid errors are read from `/var/log/kern.log` via active log monitoring.

### What is monitored

| Item | Description |
|---|---|
| `nvidia.apps.json` | Master item — runs every 5 minutes, all compute process items depend on it |
| `nvidia.apps.error_status` | Reflects whether `nvidia-smi` ran successfully (`null` = OK) |
| *(per GPU)* Number of compute apps | Count of processes currently using the GPU |
| *(per GPU)* Oldest compute app age | Age in seconds of the longest-running process on the GPU |
| *(per GPU)* Compute apps status | Aggregated status value (Idle / Active / Long-running / Error) |
| `nvidia.health.json` | Master item — GPU driver state and persistence mode, runs every 2 minutes |
| `nvidia.health.err_count` | Number of GPUs in ERR state (driver lost contact) |
| `nvidia.health.persistence_disabled` | Number of GPUs with persistence mode disabled |
| `nvidia.nvlink.json` | Master item — NVLink error counters, runs every 5 minutes |
| `nvidia.nvlink.errors` | Total NVLink error counter sum across all GPUs and links |
| `log[/var/log/kern.log...]` | Active log monitoring for NVIDIA Xid kernel errors |

### Triggers

| Trigger | Priority | Condition |
|---|---|---|
| Nvidia: critical Xid error – reboot likely required | Disaster | Xid 48, 61, 62, 79, 95, 101, 119, or 154 in kern.log |
| Nvidia: Xid error – investigation required | High | Xid 63, 74, 92, 94, or 100 in kern.log |
| Nvidia get apps (`nvidia-smi`) error | High | `nvidia-smi` failed or returned an error |
| Nvidia: {N} GPU(s) in ERR state | High | Any GPU shows ERR! in nvidia-smi |
| Nvidia: NVLink error counters are increasing | Average | NVLink error counters grew since last check (only when `{$NVLINK_PRESENT}=1`) |
| Nvidia: Xid error detected | Warning | Any other Xid error in kern.log |
| Max process age > `{$GPU_PROC_MAX_AGE_LIMIT_WARN}` | Warning | A process has been running on the GPU longer than the warning threshold |
| Nvidia: persistence mode disabled on {N} GPU(s) | Info | Any GPU has persistence mode disabled |
| Max process age > `{$GPU_PROC_MAX_AGE_LIMIT_INFO}` | Info | A process has been running on the GPU longer than the info threshold |

### Xid error severity groups

| Priority | Xid codes | Meaning |
|---|---|---|
| **Disaster** | 48, 61, 62, 79, 95, 101, 119, 154 | GPU unresponsive or unrecoverable — reboot almost certainly required |
| **High** | 63, 74, 92, 94, 100 | NVLink or ECC errors — investigate promptly, reboot may be required |
| **Warning** | all others | Transient or process-level faults — monitor for recurrence |

### Macros

| Macro | Default | Description |
|---|---|---|
| `{$GPU_PROC_MAX_AGE_LIMIT_INFO}` | `3d` | Process age Info trigger threshold |
| `{$GPU_PROC_MAX_AGE_LIMIT_WARN}` | `7d` | Process age Warning trigger threshold |
| `{$NVLINK_PRESENT}` | `0` | Set to `1` on hosts with NVLink connections between GPUs to enable the NVLink error trigger |

### Value map — Compute apps status

| Value | Label |
|---|---|
| 0 | Idle |
| 1 | Active |
| 2 | Long-running process (info) |
| 3 | Long-running process (warning) |
| 4 | Error |

---

## Files

```
├── Nvidia GPU Health by Zabbix agent.yaml  # Zabbix template (import into Zabbix UI)
├── userparameter_nvidia.conf                # Zabbix agent UserParameter definitions
└── scripts/
    └── nvidia_apps_json.py                  # Python 3 script executed by the agent
```

---

## Requirements

- **NVIDIA GPU** with drivers installed
- **`nvidia-smi`** available on the monitored host
- **Python 3** on the monitored host
- **Zabbix agent 2** (active mode required for log monitoring) on the monitored host
- Zabbix server/proxy **7.4** or newer

---

## Installation

### 1. Deploy the script

Copy `nvidia_apps_json.py` to the monitored host and make it executable:

```bash
sudo mkdir -p /etc/zabbix/scripts/nvidia
sudo cp scripts/nvidia_apps_json.py /etc/zabbix/scripts/nvidia/
sudo chmod +x /etc/zabbix/scripts/nvidia/nvidia_apps_json.py
```

Verify it works:

```bash
/etc/zabbix/scripts/nvidia/nvidia_apps_json.py
```

Expected output (no active processes):

```json
{"error": null, "gpus": {"GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx": {"proc_count": 0, "max_age": 0}}}
```

### 2. Configure the Zabbix agent UserParameters

Copy `userparameter_nvidia.conf` to the Zabbix agent configuration directory:

```bash
sudo cp userparameter_nvidia.conf /etc/zabbix/zabbix_agent2.d/
```

The file defines three UserParameters:

```
UserParameter=nvidia.apps.json,/etc/zabbix/scripts/nvidia/nvidia_apps_json.py
UserParameter=nvidia.health.json,nvidia-smi --query-gpu=index,pstate,persistence_mode --format=csv,noheader 2>&1
UserParameter=nvidia.nvlink.json,nvidia-smi nvlink --errorcounters 2>&1
```

Restart the Zabbix agent:

```bash
sudo systemctl restart zabbix-agent2
```

### 3. Grant log read permission

The Xid log item reads `/var/log/kern.log` via active log monitoring. The `zabbix` user must be able to read this file:

```bash
sudo usermod -aG adm zabbix
sudo systemctl restart zabbix-agent2
```

On Ubuntu/Debian the `adm` group has read access to `/var/log/kern.log` by default.

### 4. Import the template into Zabbix

1. In the Zabbix UI go to **Data collection → Templates**.
2. Click **Import** and upload `Nvidia GPU Health by Zabbix agent.yaml`.
3. Confirm the import.

### 5. Assign the template to a host

1. Open the host configuration in **Data collection → Hosts**.
2. Under the **Templates** tab, add **Nvidia GPU Health by Zabbix agent**.
3. Save.

### 6. Set the NVLink macro on multi-GPU hosts

On hosts where GPUs are connected via NVLink (e.g. servers with 2 or more H100/H200 cards), override the macro at the host level:

1. Open the host in **Data collection → Hosts**.
2. Go to the **Macros** tab, select **Inherited and host macros**.
3. Find `{$NVLINK_PRESENT}`, change the value to `1`, and save.

This enables the NVLink error counter trigger for that host. Leave the macro at `0` on single-GPU hosts.

### 7. Enable persistence mode (recommended)

Persistence mode keeps the NVIDIA driver loaded between workloads, reducing the risk of NVLink initialization failures and GSP timeouts on cold GPU start:

```bash
systemctl status nvidia-persistenced
```

If the daemon is running with `--no-persistence-mode`, create a systemd override:

```bash
systemctl edit nvidia-persistenced
```

Add:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/nvidia-persistenced --user nvidia-persistenced --verbose
```

```bash
systemctl daemon-reload && systemctl restart nvidia-persistenced
```

Verify:

```bash
nvidia-smi --query-gpu=index,persistence_mode --format=csv
```

All GPUs should report `Enabled`.

---

## How it works

### Compute process monitoring

Every 5 minutes the master item (`nvidia.apps.json`) calls the UserParameter, which executes `nvidia_apps_json.py`. The script runs:

```
nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory --format=csv,noheader,nounits
```

For each running process it reads `/proc/<pid>/stat` to calculate process age (seconds since the process started). The output JSON groups results by GPU UUID:

```json
{
  "error": null,
  "gpus": {
    "GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx": {
      "proc_count": 2,
      "max_age": 19189
    }
  }
}
```

LLD discovers all GPU UUIDs present in the JSON and creates item/trigger instances for each GPU automatically. When a GPU has no running processes it still appears in the JSON (with `proc_count: 0`) so the corresponding Zabbix items continue to exist and report an **Idle** status.

### GPU health monitoring

Every 2 minutes `nvidia.health.json` queries `nvidia-smi` for driver state and persistence mode. If any GPU shows `ERR!` in the pstate column, the driver has lost communication with that GPU — typically caused by an NVLink GSP timeout (Xid 119) or a required GPU reset (Xid 154). Recovery requires a server reboot.

### Xid log monitoring

The active log item watches `/var/log/kern.log` for lines containing `NVRM: Xid`. Only new lines written after the agent starts are evaluated — existing entries are skipped. Three triggers cover different severity levels based on the Xid code found in the log line.

---

## Troubleshooting

**Trigger: `nvidia-smi` error status fires**

A common cause is a driver/library version mismatch after a kernel or driver update. Steps to resolve:

1. Check the kernel driver version:
   ```bash
   cat /proc/driver/nvidia/version
   ```
2. Rebuild initramfs:
   ```bash
   sudo update-initramfs -u
   ```
3. If the GPU is idle, try reloading the kernel modules:
   ```bash
   sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia
   nvidia-smi
   ```
4. If the GPU is in use, reboot after step 2.

**No GPUs discovered**

- Confirm `nvidia_apps_json.py` runs without errors as the `zabbix` user.
- Check that the UserParameters are loaded: `zabbix_agent2 -p | grep nvidia`.
- Check the Zabbix agent log for permission errors.

**Xid log item not collecting data**

- Confirm the `zabbix` user is in the `adm` group: `groups zabbix`.
- Confirm the agent is configured for active checks and the server/proxy address is set in `zabbix_agent2.conf`.
- Confirm `/var/log/kern.log` exists and contains NVIDIA entries: `grep "NVRM" /var/log/kern.log | tail -5`.

**NVLink trigger fires on a single-GPU host**

Set `{$NVLINK_PRESENT}=0` at the host level (it is `0` by default in the template). If it still fires, check that the host-level macro override is saved correctly.

---

## License

MIT
