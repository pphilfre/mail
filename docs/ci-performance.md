# Consolidated branches and CI performance

All eight remote branch tips present on 10 October 2026 were reviewed. Compact mail,
composer attachments and drafts/attachments were already ancestors of main.
Productivity included main and earlier security work. The security candidate's later
fixes were merged explicitly, resolving six overlapping security source/test files
in favour of its validated QR decoder, DNS bounds, file protection and authentication
regressions. Everyday-features' remaining documentation commit was merged as well.
No source branch was deleted, and the original checkout's uncommitted files were left intact.

## Measured baseline

- [Main CI 38049387073](https://github.com/pphilfre/mail/actions/runs/38049387073):
  19m 34s elapsed. Simulator build-for-testing ran from 11:43:15 to 11:49:09 UTC
  (5m 54s). 133 unit tests took 11.76s; 28 UI tests took 11m 48s.
- [Successful security release 38050888619](https://github.com/pphilfre/mail/actions/runs/38050888619):
  23m 51s elapsed including queueing; validation job 20m 58s, device job 1m 20s.
- [Local intelligence CI 38047553613](https://github.com/pphilfre/mail/actions/runs/38047553613):
  25m 13s elapsed. This better reflects the dependency-heavy main tree.

These revisions differ in functionality and dependency footprint. Compare both cold
and warm runs of the consolidated tree; do not present the estimated improvement as a measurement.

## Workflow changes

- Device compilation and simulator validation start independently. An Ubuntu publish
  job requires both to succeed, verifies the IPA SHA-256 and refuses asset overwrite.
- Compile the app and tests once. Transfer only tarred Build/Products to two macOS
  runners, preserving executable permissions and symlinks. `test-without-building`
  uses the relocatable xctestrun; it never resolves packages or recompiles.
- Split all discovered UI methods exactly once using measured longer-test weights.
  New methods join the full suite automatically. All unit tests and the independent
  Python MIME check run on shard zero. Separate simulators isolate test state.
- Cache package downloads separately from build products. Compiler caches are split
  by device/simulator, coverage, OS, architecture, runner image and Xcode build.
  Source hashes choose exact caches, with compatible prior builds as fallback.
- Restore input mtimes only when SHA-256 matches, including generated project inputs,
  so checkout timestamps do not invalidate every unchanged Swift compilation. Changed
  and deleted files remain visible to Xcode; its dependency graph still controls rebuilding.
- Do not cache simulator state, credentials, Index or build logs. Cache success never
  bypasses compilation or validation. Cold builds remain supported.
- Full tests on main, releases, weekly coverage and manual full runs. Core/provider-only
  pull requests use all unit tests and eight critical UI tests. Changes to app/UI,
  resources, project or CI infrastructure select the full UI suite. Documentation-only
  changes skip CI. Branch pushes no longer duplicate pull-request builds.
- Coverage instrumentation moves from every build to the weekly full run. Successful
  screenshots remain in xcresult; attachment export is only performed for failures.
  Already-compressed IPA/test archives are uploaded without duplicate compression.
- Keep pinned Xcode, Swift strict concurrency, simulator Keychain signing, protected
  attachment tests and all existing test assertions. XcodeGen setup already takes only
  a few seconds, so adding a fragile Homebrew cache would not address the bottleneck.

The pipeline trades extra concurrent macOS runners for lower elapsed time. Simulator
and device products cannot share compiled objects because SDKs/configurations differ;
their dependency downloads can share a cache. Test execution requires its compilation
outputs, so those stages cannot safely begin together.

## Follow-up measurements and improvements

Record cold and warm run URLs, elapsed time, compilation time and each shard's duration
after validation. Runner queues and simulator migration can dominate variance. Rebalance
weights with consolidated-tree timings; consider three shards only if concurrency/cost
permits. Check the generated transitive Package.resolved into Configuration after the
first successful resolve for reproducible dependencies. Benchmark larger macOS runners
or a maintained self-hosted Mac before committing to their cost. Device login, sideloading,
notifications and real Gmail delivery still need signed-device validation.

Cache mechanics follow [GitHub's dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
Build-once testing follows [Apple's command-line Xcode guidance](https://developer.apple.com/library/archive/technotes/tn2339/_index.html).
