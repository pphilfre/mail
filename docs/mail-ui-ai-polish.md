# Mail UI and on-device AI polish

## Changes

- Drafts use a navigation-bar switch between **On this device** and **In Gmail**. Both have deletion actions with captured confirmation targets; Gmail deletion uses its draft API. Scheduled and uncertain sends stay protected. Local deletion leaves the Gmail copy intact; Gmail deletion warns that linked local edits are also removed.
- Search opens with focus and a keyboard, with a horizontally scrollable filter bar. Explicit Close returns to Emails/Inbox. Interactive sheet dismissal preserves the underlying tab and mailbox. Plain lists and section backgrounds share the native system background in both appearances.
- Mailboxes slide in from the left with reduced-motion support, a dimmed dismissal area and a left swipe to close. Four frequent destinations use a small grid; accounts, remaining mailboxes, labels, smart folders and tools use lists. Ordinary labels are neutral, and selection has an accent and accessibility trait.
- Sender logos try the exact domain, then its registrable domain. The bundled Mozilla Public Suffix List includes country and private suffixes, wildcard rules and exceptions. Invalid images fall through rather than entering the successful cache. Requests are shared, image sizes bounded, successes cached, and failures temporarily cached. Category SF Symbols remain visible during loading or failure. Existing sender-picture opt-out remains effective.
- Reader headers, subject, recipient disclosure and body spacing are compact. The redundant Conversation title is gone. Share uses a centred 44-point target. Summarise is a text action beside the current message's security icon. Unknown/stale analysis stays neutral; positive checks are green, observed concerns amber or red by the existing risk score. A logo is never a security signal.
- Message actions share fixed icon columns, neutral ordinary labels and 44-point touch targets. Destructive actions retain red.
- Composer assistance is inline, with rewrite, shorten, expand, proofread and professional/friendly tone. It exposes model availability, Wi-Fi download progress, generation and errors. Suggestions can be accepted, rejected or regenerated. A stale suggestion cannot overwrite a changed draft. Accepted edits update only the captured range, preserve outside formatting and selection, and register Undo without replacing the UITextView.

## Summary root cause and repair

The previous code intentionally prohibited Qwen summarisation and only generated prose on Apple Intelligence hardware. On iPhone 14 Pro Max, its fallback instead extracted sentences, prefixed each with the sender and a received date, and displayed them as bullets under “Key passages”. Changing only the prompt would not repair that path.

The summary path now accepts full cached text/HTML bodies rather than subjects or previews. Gmail's existing external body hydration remains in place. MIME charset matching is case-insensitive. Preparation strips HTML clutter, hidden preheaders, standard signature delimiters and subscription footer lines. Quoted history is removed only when an earlier downloaded body is present; otherwise it is retained as context. Inputs are stably ordered by message date without including received timestamps in the generated text.

Every bounded chunk reaches generation. Long threads use ordered hierarchical reduction rather than dropping late messages or falling back to copied sentences when intermediate outputs are long. Preparation rejects inputs exceeding 2 MB or 40 model chunks rather than starting an unbounded operation. Both available on-device model paths can generate summaries. The prompt requests one paragraph of roughly two to four sentences with concrete decisions, requests and deadlines. Output normalisation removes list markers and summary labels. Missing bodies, model errors and incomplete generations are shown honestly, with setup/retry paths; they are not labelled successful summaries.

## Validation and limits

Regression tests cover registrable domains, missing/HTML/long bodies, chronology and duplicate quotes, complete reduction input, error propagation, stale composer suggestions, UTF-16 selections and retained formatting, and unknown security status. UI coverage exercises draft switching/deletion, search focus and close versus swipe, compact reader actions and inline composer availability in dark mode with large text.

The first macOS run compiled successfully and passed 176 unit tests and 28 of 33 UI tests. Its screenshots and accessibility trees exposed a missing SF Symbol/hit target, hidden search toolbar controls, an unstable draft-confirmation presenter, and collection navigation that did not open. These were corrected. Simulator model availability now explicitly reports unsupported instead of attempting an unusable Foundation Models service.

The Windows tree-sitter check is supplementary syntax checking, not Swift SDK type checking. The macOS GitHub Actions build and XCTest results are recorded below when complete. Deterministic summary tests validate the input/reduction/output contract; they do not measure model factuality. Real Qwen quality, latency, thermal behavior, memory use and keyboard gestures still need a signed iPhone 14 Pro Max run with the downloaded model. The small local model can make mistakes; this change does not claim parity with a larger model.

Gmail authentication, account storage and database schema remain unchanged. Zoho is a documented future-provider boundary in this repository, not a working integration to replace. No new entitlements are introduced.

## References

- [Apple Mail search scopes](https://support.apple.com/en-hk/guide/iphone/iphb2eab8035/ios)
- [Outlook iOS favourites](https://support.microsoft.com/en-us/outlook/how-do-i-add-a-folder-to-my-favorites)
- [Apple's native SwiftUI design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Mozilla Public Suffix List](https://publicsuffix.org/list/), bundled snapshot `2026-10-07_07-28-19_UTC`, MPL 2.0 (license notice retained in the resource).

- [SwiftUI search toolbar visibility](https://developer.apple.com/documentation/swiftui/view/searchpresentationtoolbarbehavior(_:)), used to keep the explicit Close action available while search has keyboard focus.
