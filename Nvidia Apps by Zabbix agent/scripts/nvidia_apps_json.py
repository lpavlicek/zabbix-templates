#!/usr/bin/env python3
import json
import subprocess
import time
import os

def get_process_age(pid):
    try:
        # Získáme čas vytvoření procesu v sekundách od epochy
        stat_info = os.stat(f"/proc/{pid}")
        return int(time.time() - stat_info.st_ctime)
    except:
        return 0

def get_data():
    try:
        # Spuštění nvidia-smi
        cmd = ["nvidia-smi", "--query-compute-apps=gpu_uuid,pid,process_name,used_memory", "--format=csv,noheader,nounits"]
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode('utf-8').strip()
        
        if not result: # Žádné běžící procesy
            # Musíme ale zjistit UUID všech karet pro LLD
            gpu_cmd = ["nvidia-smi", "--query-gpu=uuid", "--format=csv,noheader"]
            uuids = subprocess.check_output(gpu_cmd).decode('utf-8').strip().split('\n')
            return {"error": None, "gpus": {uuid: {"proc_count": 0, "max_age": 0} for uuid in uuids if uuid}}

        lines = result.split('\n')
        gpu_data = {}

        for line in lines:
            uuid, pid, name, mem = [x.strip() for x in line.split(',')]
            age = get_process_age(pid)
            
            if uuid not in gpu_data:
                gpu_data[uuid] = {"proc_count": 0, "max_age": 0}
            
            gpu_data[uuid]["proc_count"] += 1
            if age > gpu_data[uuid]["max_age"]:
                gpu_data[uuid]["max_age"] = age

        return {"error": None, "gpus": gpu_data}

    except subprocess.CalledProcessError as e:
        return {"error": f"Nvidia-smi error: {e.output.decode().strip()}", "gpus": {}}
    except Exception as e:
        return {"error": str(e), "gpus": {}}

if __name__ == "__main__":
    print(json.dumps(get_data()))
