# Premium native mail audit

## Functional findings and changes

| Finding | Cause | Change |
| --- | --- | --- |
| Subject-like or nonsensical summaries | Preview-only inputs, 4,000-character truncation, 192-token output, and a 0.6B model tasked with factual synthesis | Inline summaries consume downloaded plain/HTML bodies. Apple Foundation Models is preferred when actually available. Long bodies are chunked; unavailable/failed generation falls back to explicitly labelled source passages. Qwen is restricted to writing assistance. |
| Missing lower sections of HTML mail | Wrapper bounds omitted overflowing/floating content; late images/fonts altered layout; large Gmail bodies can be returned as attachment IDs | Reader fetches external text/HTML parts, preserves hydrated caches, measures scaled scroll height, watches image/font/content changes, and retains the script-disabled ephemeral renderer. |
| Formatting controls could not format outgoing email | Composer used a plain TextEditor and plain-only MIME | Native UITextView selection/typing formatting, bold/italic/underline/strike, lists, links, portable rich draft metadata, and multipart/alternative inside multipart/mixed. HTML escapes all text/attributes and rejects active link schemes. |
| Lost or duplicated signatures on account changes | Signature management was not restored when reopening a saved draft | Unedited account footers remain managed across reopen/switch; user edits are preserved. Writing assistance excludes signatures and quoted history, or uses the selected passage. |
| Cluttered, inconsistent navigation | A custom bottom dock pushed Tasks, Inbox filters doubled as mailbox navigation, and the drawer mixed grids/cards/menus | Native selected Mail/Tasks/Search tabs, an Inbox/Catch Up/Sent selector, separate quick filters, and compact grouped mailbox rows. Local Categories and the separate insights/summary screen are removed. |
| Search stalled as filters/queries changed | Keyword matching ran synchronously during view rendering | Debounced, cancellable background matching; stale requests cannot publish results. Three quick filters and one advanced menu preserve sender/date/account/saved/operator/meaning search. |
| Privacy and security were hard to scan | Long technical explanations, unfinished compatibility lists, and always-visible links | Compact truthful feature states, byte-based download progress, coloured security overview, and collapsed technical/link/attachment lists. Per-lookup consent and unknown-verdict semantics remain. |
| Native capabilities were limited by a guest-container assumption | Settings/documentation assumed LiveContainer | Native periodic background refresh, permission-backed local new-mail notifications, and retained device-only Keychain. Installation is a standalone signed iOS app. |

## Data preservation

The existing SwiftData schema and storage URL are unchanged. Rich text uses optional Codable fields and `StoreMetadata` records keyed by draft UUID. Legacy drafts decode without formatting. Save, discard, account removal and queued sends retain formatting through the repository; metadata is removed alongside deleted drafts. Uncertain sends and externally modified Gmail drafts retain their existing protection against automatic overwrite or duplicate sending.

Done saves the draft without an extra prompt; swipe dismissal checkpoints it. Only explicit destructive discard asks for confirmation. No mailbox database or user credentials are included in the validation source snapshot.

## Native installation and provisioning

The app declares `UIBackgroundModes: fetch` and `BGTaskSchedulerPermittedIdentifiers` for `dev.freddiephilpot.dispatch.refresh`, with a SwiftUI background task handler. Refresh and local notifications are opt-in in Privacy & Intelligence. Notification authorization and Background App Refresh availability come from iOS, not simulated installation indicators. Background alerts hide mail content. iOS decides scheduling; this is not real-time push and scheduled-send times are not guaranteed.

Keychain continues to use the installed app's default access group, device-only items, and no iCloud synchronization. Simulator test entitlements are scoped to the simulator SDK. The unsigned device IPA must be re-signed by iLoader with a profile matching the installed bundle identifier. Keep that identity and Keychain group stable across updates to retain access to accounts.

App Groups require an explicitly registered group and a provisioning profile granting the group to every participating app/extension. This single-target app currently has no separate widget/share extension needing shared storage, so it does not request an unused group or move the existing database into a different container. A future extension must use a provisioned group and an explicit migration; simply adding a string to entitlements does not grant access. Group entitlement support depends on the account/profile iLoader uses.

APNs remote push requires `aps-environment`, valid push provisioning and a mail push delivery service. Gmail REST polling alone cannot deliver APNs. This build does not advertise push support or request an entitlement it cannot use. iOS local notifications do not require APNs.

Apple Intelligence depends on device eligibility, system configuration, region/language and model availability. Installing an IPA does not make unsupported hardware eligible. The 6 GB iPhone 14 Pro Max can use the optional Qwen writing model and source-passage summaries, but cannot use Apple's system model.

## Validation

Windows source parsing and YAML checks supplement the macOS/Xcode build and XCTest suite; they do not establish SDK type checking. Added tests cover rich-text persistence/reopen/discard, UTF-16/emoji formatting, escaping/active links, multipart MIME with attachments, external Gmail body hydration, long-body summary preparation, and writing-range isolation. The independent Python RFC parser verifies actual Swift-emitted rich MIME in CI. UI tests now exercise native tabs and reachable compact mailbox rows.

Device-only checks still include Google sign-in, model inference quality/memory, background scheduling, notification permission, and signing/Keychain continuity. Validate on a signed physical device before treating these as proven.

## API references

- [Apple Foundation Models generation and availability](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [Apple UITextView attributed text](https://developer.apple.com/documentation/uikit/uitextview/attributedtext)
- [Apple SwiftUI background refresh](https://developer.apple.com/documentation/swiftui/backgroundtask)
- [Apple App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)
- [Apple local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-and-handling-local-notifications)
