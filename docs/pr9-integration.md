# PR #9 integration repair

The branch is reconciled with main at `502d6d804385539a01e650eae9fd69e033ae5f88`. Main's pinned package resolution, compile-once test products, three full UI test shards, cache compatibility checks and release workflow are retained alongside the current Dispatch visual system and mail UI work.

The last available full run failed when opening collection creation from the reader. Collection creation now uses an explicit button and navigation destination, while retaining the action sheet's completion callback and a 44-point target. Its existing UI regression waits for the identified button and verifies that it can be tapped before checking creation, files and removal of membership.

The merge retains the current split intelligence screens and inline summary/writing implementations, removes the obsolete consolidated duplicates, and avoids restoring obsolete inbox/search controls or duplicate settings entries. The composer subject remains a native single-line field, matching its existing interactions and tests.

The sharded test runner preserves comma-separated diagnostic selectors and independently verifies both plain and rich compose MIME fixtures whenever the full unit suite runs. The device artifact job remains gated by the required aggregate test result, and never publishes a release.

Local checks: edited Swift files parse, whitespace checks pass, and the CI partition/cache guard verifies that all 33 current UI tests appear exactly once. The whole-project supplementary parser retains the same errors in untouched source constructs as the original workspace. Xcode compilation and simulator/device validation are queued remotely; no successful build or test result is claimed.
