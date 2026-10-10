#!/usr/bin/env python3
"""Guard test coverage partitioning and incremental-cache invalidation."""
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("shards", root / "scripts/test-shards.py")
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)
os.chdir(root)
groups = shards.partition()
methods = re.findall(r"func\s+(test\w+)\s*\(", Path("Tests/UI/DispatchUITests.swift").read_text())
assert set(groups[0]).isdisjoint(groups[1])
assert sorted(groups[0] + groups[1]) == sorted(methods)
assert set(shards.partition("smoke")[0]) <= set(methods)
Path("build").mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=root / "build") as directory:
    temp = Path(directory)
    subprocess.run(["git", "init", "-q", directory], check=True)
    source = temp / "unchanged.swift"
    source.write_text("original")
    modified = temp / "changed.swift"
    modified.write_text("before")
    subprocess.run(["git", "-C", directory, "add", "."], check=True)
    old = 1_700_000_000_000_000_000
    for path in (source, modified):
        os.utime(path, ns=(old, old))
    command = [sys.executable, str(root / "scripts/cache-inputs.py")]
    subprocess.run(command + ["save", "manifest.json"], cwd=directory, check=True)
    modified.write_text("after")
    current = 1_800_000_000_000_000_000
    for path in (source, modified):
        os.utime(path, ns=(current, current))
    subprocess.run(command + ["restore", "manifest.json"], cwd=directory, check=True)
    assert source.stat().st_mtime_ns == old
    assert modified.stat().st_mtime_ns == current
    assert json.loads((temp / "manifest.json").read_text())["unchanged.swift"][1] == old
print(f"CI guards passed: {len(methods)} UI tests partitioned exactly once; changed inputs keep new timestamps.")
