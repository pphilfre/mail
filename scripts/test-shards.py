#!/usr/bin/env python3
"""Partition every discovered UI test exactly once across separate simulators."""
import argparse
import json
import re
from pathlib import Path

SMOKE = {
    "testWelcomeAndDrawerNavigation", "testSampleMessageOpens",
    "testComposeDraftSurvivesRelaunch", "testDraftAutosaveSurvivesRelaunchWithoutPressingSave",
    "testLocalSearchFindsSampleMailAndShowsNoResults", "testComposerShowsInvalidRecipientsBeforeSend",
    "testGroupedBulkArchiveCanBeUndoneWithoutProviderAccess",
    "testRedesignedReaderActionsAndHonestSecurityInspector",
}
# Seconds measured in full release run 38054443359; new tests use a conservative default.
SECONDS = json.loads(Path(__file__).with_name("ui-test-durations.json").read_text())


def partition(scope="full"):
    methods = re.findall(r"func\s+(test\w+)\s*\(", Path("Tests/UI/DispatchUITests.swift").read_text())
    if len(methods) != len(set(methods)) or not methods:
        raise ValueError("Expected unique XCTest methods in DispatchUITests")
    if not SMOKE <= set(methods):
        raise ValueError(f"Smoke selectors missing from source: {SMOKE - set(methods)}")
    if scope == "smoke":
        return [sorted(SMOKE)]
    shards, costs = [[], [], []], [15, 0, 0]  # Include the unit suite's measured cost.
    for method in sorted(methods, key=lambda name: (-SECONDS.get(name, 25), name)):
        index = min(range(len(shards)), key=lambda i: costs[i])
        shards[index].append(method)
        costs[index] += SECONDS.get(method, 25)
    assert sorted(method for shard in shards for method in shard) == sorted(methods)
    return shards


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--scope", choices=["full", "smoke"], default="full")
    parser.add_argument("--shard", type=int, default=0)
    args = parser.parse_args()
    for method in partition(args.scope)[args.shard]:
        print(f"DispatchUITests/DispatchUITests/{method}")
