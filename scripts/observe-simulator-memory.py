"""Observe the test app and WebKit services in one explicitly identified simulator.

No private WK PID API, sudo, global process scan, or retry after access denial.
RSS sums include shared mappings; they are not the phone's unique physical memory.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import signal
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument("--device", required=True)
p.add_argument("--out", type=Path, required=True)
args = p.parse_args()
assert re.fullmatch(r"[A-Fa-f0-9-]{36}", args.device)
args.out.mkdir(parents=True, exist_ok=True)
started = time.time()
stopping = False
errors = []
reported_errors = set()
denied = set()
samples = []
footprints = []

def stop(*_):
    global stopping
    stopping = True

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

def command(argv, operation, timeout=8):
    if operation in denied:
        return None
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        errors.append({"operation": operation, "error": "timeout", "argv": argv})
        return None
    if r.returncode:
        message = r.stderr.strip() or r.stdout.strip()
        if re.search(r"denied|not permitted|not authorized|permission", message, re.I):
            denied.add(operation)
            errors.append({"operation": operation, "error": message, "argv": argv, "stoppedAfterDenial": True})
        elif (operation, message) not in reported_errors:
            reported_errors.add((operation, message))
            errors.append({"operation": operation, "error": message, "argv": argv, "exitCode": r.returncode})
        return None
    return r.stdout

def webkit_jobs(catalog):
    found = {}
    # `list` and `print` have different output; retain the actual catalogs below.
    for line in catalog.splitlines():
        fields = line.split()
        if fields and fields[0].isdigit() and "webkit" in line.lower():
            found[int(fields[0])] = " ".join(fields[1:])
    for match in re.finditer(r"([^\s={}]*[Ww]eb[Kk]it[^\s={}]*)(?:\s*=)?\s*\{(.*?)\n\s*\}", catalog, re.S):
        pid = re.search(r"\bpid\s*=\s*(\d+)", match.group(2))
        if pid:
            found[int(pid.group(1))] = match.group(1)
    return {pid: label for pid, label in found.items() if pid > 0}

def footprint(pid, phase, index):
    operation = "vmmap pid " + str(pid)
    output = command(["/usr/bin/vmmap", "-summary", str(pid)], operation, timeout=12)
    if output is None:
        return None
    path = args.out / ("vmmap-%04d-%s.txt" % (index, pid))
    path.write_text(output)
    match = re.search(r"Physical footprint:\s*([0-9.]+)\s*([KMGT]?)", output, re.I)
    if not match:
        return {"pid": pid, "phase": phase, "timestamp": time.time(), "summary": path.name, "physicalFootprintBytes": None}
    scale = {"": 1, "K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4}[match.group(2).upper()]
    return {"pid": pid, "phase": phase, "timestamp": time.time(), "summary": path.name, "physicalFootprintBytes": float(match.group(1)) * scale}

container = None
discovery_at = 0
webkit_at = 0
vmmap_at = 0
webkit = {}
futures = []
previous_phase = None
pool = ThreadPoolExecutor(max_workers=1)
try:
    with (args.out / "memory-samples.jsonl").open("w") as sink:
        while not stopping and time.time() - started < 720:
            now = time.time()
            if container is None and now >= discovery_at:
                discovery_at = now + 2
                found = command(["xcrun", "simctl", "get_app_container", args.device, "com.door581.appletest", "data"], "owned simulator app container")
                if found:
                    container = Path(found.strip())
            if container is None:
                time.sleep(0.25)
                continue
            try:
                native = json.loads((container / "Documents/door581-memory-profile.json").read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                time.sleep(0.25)
                continue
            if native.get("timestamp", 0) < started:
                time.sleep(0.25)
                continue
            native_pid = native.get("process", {}).get("pid")
            if not isinstance(native_pid, int) or native_pid <= 0:
                time.sleep(0.25)
                continue
            if now >= webkit_at:
                webkit_at = now + 10
                operation = "owned simulator WebKit catalog"
                catalogs = [("list", ["list"]), ("system", ["print", "system"]), ("app-pid", ["print", "pid/" + str(native_pid)])]
                discovered = {}
                for name, arguments in catalogs:
                    if operation in denied:
                        break
                    listing = command(["xcrun", "simctl", "spawn", args.device, "launchctl"] + arguments, operation)
                    if listing is not None:
                        (args.out / ("webkit-catalog-" + name + ".txt")).write_text(listing)
                        discovered.update(webkit_jobs(listing))
                webkit = discovered
            pids = [native_pid] + sorted(webkit)
            rows = command(["/bin/ps", "-p", ",".join(map(str, pids)), "-o", "pid=,rss=,comm="], "owned test-process RSS")
            processes = []
            if rows:
                for line in rows.splitlines():
                    fields = line.strip().split(None, 2)
                    if len(fields) == 3 and fields[0].isdigit() and fields[1].isdigit():
                        pid = int(fields[0])
                        processes.append({"pid": pid, "rssBytes": int(fields[1]) * 1024, "kind": "native" if pid == native_pid else "webkit-service", "command": fields[2], "service": webkit.get(pid)})
            phase = native.get("phase")
            record = {"timestamp": now, "device": args.device, "nativeSnapshotAgeSeconds": now - native["timestamp"], "native": native, "processes": processes, "nativeRSSBytes": sum(r["rssBytes"] for r in processes if r["kind"] == "native"), "webkitServicesRSSBytes": sum(r["rssBytes"] for r in processes if r["kind"] == "webkit-service"), "sumRSSBytes": sum(r["rssBytes"] for r in processes)}
            samples.append(record)
            sink.write(json.dumps(record, separators=(",", ":")) + "\n"); sink.flush()
            if phase != previous_phase or now >= vmmap_at:
                vmmap_at = now + 10; previous_phase = phase
                # Restrict to PIDs already observed in this owned simulator scenario.
                if len([f for f in futures if not f.done()]) < 6:
                    for process in processes:
                        if process["kind"] != "native":
                            continue
                        futures.append(pool.submit(footprint, process["pid"], phase, len(futures)))
            time.sleep(0.25)
finally:
    pool.shutdown(wait=True)
    footprints = [f.result() for f in futures if f.result() is not None]
    groups = {}
    for sample in samples:
        phase = sample["native"].get("phase", "unknown") + "|active=" + str(sample["native"].get("active"))
        item = groups.setdefault(phase, {"samples": 0, "nativeRSSPeakBytes": 0, "webkitServicesRSSPeakBytes": 0, "sumRSSPeakBytes": 0, "latestNativeSnapshot": None})
        item["samples"] += 1
        for source, target in [("nativeRSSBytes", "nativeRSSPeakBytes"), ("webkitServicesRSSBytes", "webkitServicesRSSPeakBytes"), ("sumRSSBytes", "sumRSSPeakBytes")]:
            item[target] = max(item[target], sample[source])
        item["latestNativeSnapshot"] = sample["native"]
    report = {"scope": "One identified simulator, native app plus all running WebKit jobs in that device. RSS sum can double-count shared mappings; not phone total physical memory. Native task footprint/vmmap are separate; WebKit reports RSS, not an inferred unique physical footprint.", "device": args.device, "samples": len(samples), "webkitSamples": sum(s["webkitServicesRSSBytes"] > 0 for s in samples), "nativeRSSPeakBytes": max((s["nativeRSSBytes"] for s in samples), default=0), "webkitServicesRSSPeakBytes": max((s["webkitServicesRSSBytes"] for s in samples), default=0), "sumRSSPeakBytes": max((s["sumRSSBytes"] for s in samples), default=0), "phases": groups, "vmmap": footprints, "errors": errors, "deniedOperationsStopped": sorted(denied)}
    (args.out / "memory-summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"samples": report["samples"], "webkitSamples": report["webkitSamples"], "errors": errors}))
