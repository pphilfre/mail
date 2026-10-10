#!/usr/bin/env python3
"""Partition every discovered UI test exactly once across separate simulators."""
import argparse
import re
from pathlib import Path

SMOKE = {
    "testWelcomeAndDrawerNavigation", "testSampleMessageOpens",
    "testComposeDraftSurvivesRelaunch", "testDraftAutosaveSurvivesRelaunchWithoutPressingSave",
    "testLocalSearchFindsSampleMailAndShowsNoResults", "testComposerShowsInvalidRecipientsBeforeSend",
    "testGroupedBulkArchiveCanBeUndoneWithoutProviderAccess",
    "testRedesignedReaderActionsAndHonestSecurityInspector",
}
# Seconds measured in run 38049387073; new tests use a conservative default.
SECONDS = {
    "testAttachmentLibrarySearchAndSourceConversation": 84,
    "testAttachedDraftReopensAndRemovalPersistsAfterRelaunch": 50,
    "testCollectionCreatedFromReaderIncludesThreadFilesAndCanRemoveMembership": 50,
    "testMailTaskCanBeCreatedCompletedAndReopenedWithConversationLink": 44,
    "testCompactInboxAndPreviewSettingReduceActualRowHeight": 33,
    "testPeopleProfileCanSaveNicknameAndShowSenderFiles": 32,
}


def partition(scope="full"):
    methods = re.findall(r"func\s+(test\w+)\s*\(", Path("Tests/UI/DispatchUITests.swift").read_text())
    if len(methods) != len(set(methods)) or not methods:
        raise ValueError("Expected unique XCTest methods in DispatchUITests")
    if not SMOKE <= set(methods):
        raise ValueError(f"Smoke selectors missing from source: {SMOKE - set(methods)}")
    if scope == "smoke":
        return [sorted(SMOKE)]
    shards, costs = [[], []], [0, 0]
    for method in sorted(methods, key=lambda name: (-SECONDS.get(name, 25), name)):
        index = min(range(2), key=lambda i: costs[i])
        shards[index].append(method)
        costs[index] += SECONDS.get(method, 25)
    assert sorted(shards[0] + shards[1]) == sorted(methods)
    return shards


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--scope", choices=["full", "smoke"], default="full")
    parser.add_argument("--shard", type=int, default=0)
    args = parser.parse_args()
    for method in partition(args.scope)[args.shard]:
        print(f"DispatchUITests/DispatchUITests/{method}")
