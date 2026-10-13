#!/usr/bin/env python3
"""Let simulator startup overlap compilation; stop promptly if compilation fails."""
import json
import os
import time
import urllib.error
import urllib.request


def read_api(path):
    request = urllib.request.Request(
        f"{os.environ['GITHUB_API_URL']}/repos/{os.environ['GITHUB_REPOSITORY']}/{path}",
        headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}",
                 "Accept": "application/vnd.github+json", "Cache-Control": "no-cache"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def main():
    run = os.environ["GITHUB_RUN_ID"]
    deadline = time.monotonic() + 25 * 60
    while time.monotonic() < deadline:
        nonce = time.time_ns()
        try:
            artifacts = read_api(f"actions/runs/{run}/artifacts?per_page=100&check={nonce}")
            if any(a["name"] == "simulator-test-products" and not a["expired"] for a in artifacts["artifacts"]):
                print("Compiled test products are ready; download and run without rebuilding.")
                return
            jobs = read_api(f"actions/runs/{run}/jobs?per_page=100&check={nonce}")
            for job in jobs["jobs"]:
                if job["name"].split(" / ")[-1] == "compile" and job["status"] == "completed" and job["conclusion"] != "success":
                    raise SystemExit(f"Compilation ended with {job['conclusion']}; refusing to wait or test stale products.")
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504):
                raise
            print(f"Temporary GitHub API status {error.code}; retrying.")
        except (urllib.error.URLError, TimeoutError):
            print("Temporary GitHub API connection failure; retrying.")
        time.sleep(15)
    raise SystemExit("Timed out waiting for this run's compiled test products.")


if __name__ == "__main__":
    main()
