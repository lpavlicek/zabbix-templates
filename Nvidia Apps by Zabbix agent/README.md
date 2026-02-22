# Nvidia Apps by Zabbix agent

Zabbix template for monitoring NVIDIA GPU compute applications (processes) via `nvidia-smi`. For each GPU it tracks the number of running compute processes and the age of the longest-running one — useful for detecting forgotten or stuck jobs on shared GPU servers.

Compatible with **Zabbix 7.4+**.

---

## Overview

The template uses a lightweight Python script deployed on the monitored host. The script queries `nvidia-smi` and returns a JSON object with per-GPU process count and oldest-process age. Zabbix reads this JSON via a UserParameter and derives all monitored values from it using LLD (Low-Level Discovery).

### What is monitored

| Item | Description |
|---|---|
| Raw JSON data | Master item — runs every 5 minutes, all other items depend on it |
| Error status | Reflects whether `nvidia-smi` ran successfully (`null` = OK) |
| *(per GPU)* Number of compute apps | Count of processes currently using the GPU |
| *(per GPU)* Oldest compute app age | Age in seconds of the longest-running process on the GPU |
| *(per GPU)* Compute apps status | Aggregated status value (Idle / Active / Long-running / Error) |

### Triggers

| Trigger | Severity | Description |
|---|---|---|
| `nvidia-smi` error status | High | `nvidia-smi` failed or returned an error (e.g. driver/library version mismatch) |
| Max process age > `{$GPU_PROC_MAX_AGE_LIMIT_INFO}` | Info | A process has been running on the GPU longer than the info threshold |
| Max process age > `{$GPU_PROC_MAX_AGE_LIMIT_WARN}` | Warning | A process has been running on the GPU longer than the warning threshold |

### Macros

| Macro | Default | Description |
|---|---|---|
| `{$GPU_PROC_MAX_AGE_LIMIT_INFO}` | `3d` | Info-level trigger threshold for oldest process age |
| `{$GPU_PROC_MAX_AGE_LIMIT_WARN}` | `7d` | Warning-level trigger threshold for oldest process age |

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
├── Nvidia Apps by Zabbix agent.yaml   # Zabbix template (import into Zabbix UI)
├── userparameter_nvidia.conf           # Zabbix agent UserParameter definition
└── scripts/
    └── nvidia_apps_json.py             # Python 3 script executed by the agent
```

---

## Requirements

- **NVIDIA GPU** with drivers installed
- **`nvidia-smi`** available on the monitored host
- **Python 3** on the monitored host
- **Zabbix agent** (active or passive) on the monitored host
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

### 2. Configure the Zabbix agent UserParameter

Copy `userparameter_nvidia.conf` to the Zabbix agent configuration directory:

```bash
sudo cp userparameter_nvidia.conf /etc/zabbix/zabbix_agentd.d/
```

Restart the Zabbix agent:

```bash
sudo systemctl restart zabbix-agent
# or zabbix-agent2, depending on your setup
```

### 3. Grant permissions (if needed)

If the Zabbix agent runs as a non-root user (typically `zabbix`) and `nvidia-smi` requires elevated privileges, add a sudoers entry:

```
zabbix ALL=(ALL) NOPASSWD: /usr/bin/nvidia-smi
```

In most standard driver setups `nvidia-smi` is accessible without `sudo`.

### 4. Import the template into Zabbix

1. In the Zabbix UI go to **Data collection → Templates**.
2. Click **Import** and upload `Nvidia Apps by Zabbix agent.yaml`.
3. Confirm the import.

### 5. Assign the template to a host

1. Open the host configuration in **Data collection → Hosts**.
2. Under the **Templates** tab, add **Nvidia Apps by Zabbix agent**.
3. Save.

---

## How it works

Every 5 minutes the master item (`nvidia.apps.json`) calls the UserParameter, which executes `nvidia_apps_json.py`. The script runs:

```
nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory --format=csv,noheader,nounits
```

For each running process it reads `/proc/<pid>` to calculate process age (seconds since the process started). The output JSON groups results by GPU UUID:

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
- Check that the UserParameter is loaded: `zabbix_agentd -p | grep nvidia`.
- Check the Zabbix agent log for permission errors.

---

## License

MIT
