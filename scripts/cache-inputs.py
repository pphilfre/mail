#!/usr/bin/env python3
"""Restore timestamps only for byte-identical Xcode inputs; never hide changed files."""
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path


def inputs():
    paths = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
    paths += [str(p) for p in Path("Dispatch.xcodeproj").rglob("*") if p.is_file()]
    return [Path(p) for p in paths if p and Path(p).is_file()]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    mode, manifest = sys.argv[1], Path(sys.argv[2])
    if mode == "save":
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps({str(p): [digest(p), p.stat().st_mtime_ns] for p in inputs()}))
    elif mode == "restore":
        if not manifest.exists():
            print("Cold build: no input timestamp manifest")
            return
        prior = json.loads(manifest.read_text())
        restored = 0
        for path in inputs():
            record = prior.get(str(path))
            if record and digest(path) == record[0]:
                os.utime(path, ns=(path.stat().st_atime_ns, record[1]))
                restored += 1
        print(f"Restored timestamps for {restored} byte-identical inputs")
    else:
        raise SystemExit("Expected save or restore")


if __name__ == "__main__":
    main()
