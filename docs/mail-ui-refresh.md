# Mail UI, responsiveness and release build refresh

The existing paper, ink and mauve palette and serif navigation font remain the shared
design tokens. Liquid Glass is reserved for compact controls. Changes build on the
existing draft editor, attachment library, search filters, reader renderer and CI caches.

## Screens and behaviour

- Inbox has profile and Settings icons and a compose control above the native bottom
  navigation/search bar. Mailbox and filter chrome stays in the same place, including
  Starred. Scope changes do not animate recycled cells underneath the header.
- Secondary screens use inbox paper, shared dividers and centred navigation titles.
  Search toolbars remain visible while focused; filter menus use the leading side,
  opposite Close. Existing mail filter tabs remain available.
- Reply, Forward and Share use white icons on a common tinted glass surface, with an
  opaque fallback for Reduce Transparency. Summarise and writing assistance share a
  gradient glass treatment; only running operations animate, respecting Reduce Motion.
- Generated, complete summaries persist locally under a content hash. Reopening mail
  reuses the result; changed bodies get a new key. Cache reads, hashing and writes happen
  on a separate actor. Files use complete device protection and are excluded from backup.
  The cache retains up to 100 summaries and clears when removing an account.
- Sender icons reuse decoded images, downsampled disk images and successful domain
  resolutions. The bounded disk cache retains up to 200 icons / 20 MB for 30 days.
  Discovery begins alongside the standard favicon instead of after every fallback.
  Discord's currently declared Website Files CDN namespace is explicitly accepted only
  for Discord; arbitrary external icon hosts remain rejected. Recipient suggestions and
  receipt rows reuse these icons. The Google provider logo is bundled for offline use.
- Compose shows an accessible saving/saved/error icon beside its title. Done fits its
  label. Formatting expands inside one horizontal glass toolbar, with a collapse arrow.
  The compact AI toolbar appears above it while the editor and keyboard remain mounted.
  Revision acceptance still checks the captured draft and preserves formatting/Undo.
  Manage signatures remains available in Composer options.
- Attach file offers From Device and From Email. Email selection reuses the attachment
  library with search, file-type icons, sorting, offline/inline filters and Quick Look.
  Selecting an attachment copies it through the existing protected draft attachment
  store; downloading and import failures are shown in compose.
- Accounts removes management/sign-in prose and uses an Add Account provider picker.
  Google is the only working provider and is the only provider offered. Settings labels
  are shorter, with optional information popovers for remote images and company icons.
  Drafts uses accessible device/cloud icon buttons in a compact glass picker.
- People supports All, Recent (30 days), Frequent and Favourites. Favourite status is
  editable in sender notes and persists in the existing profile metadata. Older profiles
  and receipt corrections remain readable without migration.
- Receipts uses a Wallet-inspired activity card, compact merchant/date/amount rows and
  company icons. Unknown amounts display `?` with a spoken label. The loading indicator
  is small. Filters cover month, receipt/invoice, cash-flow direction and unknown amounts.
  Review uses labelled fields and an editable receipt/invoice type; original email content
  is accessed from the detail screen. The graph has rounded gradient bars, clearer axes
  and reduced-motion-aware data transitions.

## Responsiveness

HTML document preparation and plain-text link detection run off the UI actor. Plain
text is available immediately, with links applied when ready. Embedded web views cannot
capture the outer scroll gesture, and measured height changes do not animate large layout
shifts. The existing warm web-view pool stays in use. Attachment and receipt search state
is separated from database snapshots so typing does not rebuild every cached mail body.
Smart mailbox attachment/folder lookup uses grouped dictionaries, and mailbox rows are
computed once per rendering pass. ProMotion eligibility is enabled in Info.plist.

These changes target responsive 60/120 Hz rendering; they do not constitute an FPS
measurement. Profile cold/warm reader opening, mailbox changes, long HTML threads,
large inboxes and typing with Instruments on a supported signed device before claiming
a stable frame-rate target.

## Build investigation and changes

GitHub Actions step timings were inspected on 14 October 2026:

| Successful run | Overall | Simulator compilation | Device packaging | Main bottleneck |
| --- | --- | --- | --- | --- |
| [38439880221](https://github.com/pphilfre/mail/actions/runs/38439880221) | 39m 25s | 2m 26s | 7m 34s | Third test shard started 15 minutes after the run began; packaging waited for all validation |
| [38470765349](https://github.com/pphilfre/mail/actions/runs/38470765349) | 19m 50s | 2m 15s | 5m 45s | UI test shards took about 9–10 minutes; packaging then ran serially |

The existing build-once simulator products, locked Swift packages and three-way full UI
sharding are preserved. Further changes:

- Main IPA builds run all unit tests and eight critical UI tests. UI pull requests,
  **iOS Regression** (weekly/on demand) and **Release IPA** still run the complete suite.
  Weekly regression retains coverage and does not produce an unnecessary IPA.
- Device packaging starts alongside simulator validation and uses the existing pinned
  Xcode/package/incremental cache action, including input timestamp preservation. It
  previously skipped that cache action. IPA uploads skip redundant compression.
- Build commands explicitly parallelise targets, disable unused index-store output and
  include Xcode's build timing summary for cold/warm comparisons.
- Tag and manual **Release IPA** runs always publish the IPA and SHA-256 checksum to
  GitHub's Releases tab after the full validation and package jobs pass. Existing releases
  cannot be overwritten. Existing tags must point to the validated commit. Actions summaries
  link to the published release. Ordinary CI IPA artifacts are development builds.

Removing serial packaging and reducing routine test jobs addresses both elapsed time
and runner contention. New cold/warm timings remain to be measured after these local
changes are committed and run. No speedup percentage is claimed.

Cache behaviour follows [GitHub's caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
Focused search chrome uses [Apple's toolbar behaviour API](https://developer.apple.com/documentation/swiftui/view/searchpresentationtoolbarbehavior(_:)).

## Verification and limits

New unit coverage checks persisted summary reuse/content invalidation, field-boundary
hashing, incomplete-summary rejection, cache clearing, offline favicon loading, Discord
CDN scoping, editable receipt types and legacy correction decoding. Existing UI checks
now expect the keyboard to remain open and locate the accessible draft icon picker.

Windows validation covers Swift syntax for changed files, workflow YAML parsing, asset
metadata/XML, CI test partitioning/cache invalidation and whitespace. Full-tree Swift
parsing still reports the existing unsupported SwiftData `#Index` and conditional security
constructs; those files were unchanged in this pass. Xcode type checking, XCTest execution,
simulator screenshots and signed-device performance/keyboard/AI checks cannot run on this
Windows host. Gmail sign-in, real attachment downloads, local model generation and actual
GitHub publication require their normal connected/device/CI environments.
