#!/usr/bin/env python3
"""Pick an available iOS 26+ iPhone from the selected Xcode installation."""
import json
import subprocess

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
candidates = []
for runtime, entries in devices["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split(".iOS-")[1].split("-"))
    if version[0] < 26:
        continue
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            # Reuse an already booted phone, otherwise prefer a standard-size device.
            candidates.append((device.get("state") == "Booted", version,
                               "Pro" not in device["name"] and "Air" not in device["name"] and "Plus" not in device["name"],
                               device["name"], device["udid"]))
if not candidates:
    raise SystemExit("No available iOS 26+ iPhone simulator. Check the runner image and selected Xcode.")
print(sorted(candidates)[-1][-1])
