# Audit implementation progress

## Batch 1 — Local search

Implemented native cached-mail search, account filtering, explicit Trash/Spam inclusion, an off-main-actor substring index, and sample/no-results states.

[First macOS CI run](https://github.com/pphilfre/mail/actions/runs/37212517327): app and test bundles compiled; all 36 unit tests passed. Three UI tests passed; the new search test queried the entire application and matched underlying inbox content. Assertions were narrowed to the search list and result identifiers. [Batch 2 validation](https://github.com/pphilfre/mail/actions/runs/37213645715) then passed the simulator build, all 46 unit tests, and all five UI tests, including search.

## Batch 2 — Draft safety, pagination, and inbox cleanup

- Draft edits checkpoint locally after 600 ms of inactivity and when the app leaves the foreground. Discard removes a new draft or restores the original saved draft.
- Draft saves reload current persisted draft state, preserving provider imports and preventing stale editors from reviving sent/unconfirmed messages.
- Existing Gmail drafts with HTML, attachments, or external bodies cannot be overwritten by the text composer. They remain editable in Gmail. Deletion has an independent confirmed action.
- Each account/mailbox/label has a durable pagination cursor using existing metadata storage. All Mail cursors remain compatible with previous versions.
- Inbox errors appear in one compact disclosure with retry/account actions. Unconfirmed sends open a dedicated recovery view instead of displaying bodies in the inbox.
- The active account appears below the mailbox title. Today’s mail shows the time; older mail shows a concise date. Sample previews respect Settings.
- Connected-account composing puts Send in the top bar and uses shorter helper text.

Added draft discard/persistence, stale-session, rich-draft protection, mailbox pagination, account cleanup, and send-confirmation tests plus an autosave relaunch UI test. [macOS validation](https://github.com/pphilfre/mail/actions/runs/37213645715) passed the simulator build, all 46 unit tests, and all five UI tests for commit `349d1fb`. No schema version change, release, or merge has been performed.

## Batch 3 — Connectivity and reading states

- Returning connectivity retries queued mailbox operations while the app is active; the first network-path report and interface changes do not duplicate launch sync. Background scheduling remains deferred.
- Reader loading/failures have a scoped retry path while cached bodies remain visible. An unrelated shared provider error no longer appears in a message.
- The remote-image prompt checks image references and CSS image URLs rather than showing for every HTML message. Its override is clearly labelled for the whole conversation.
- Account/mailbox selection persists across launches. New composers use the selected account when available.
- Sample Unread and empty mailbox views now follow the selected mailbox instead of repeating all sample mail.

Added connectivity transition, image-prompt, cached-reader failure, and sample-mailbox tests. [macOS CI](https://github.com/pphilfre/mail/actions/runs/37214390140) passed the simulator build, all 49 unit tests, and all six UI tests for commit `039badf`. Results for later revisions are recorded in the [branch CI history](https://github.com/pphilfre/mail/actions?query=branch%3Acodex%2Flocal-mail-search).

## Review follow-up — Cancel obsolete indexing

Search index construction now checks cancellation between documents, and the cache-observing task forwards cancellation to its detached index build. This prevents obsolete builds from continuing when new cache batches arrive or search closes. An asynchronous unit test verifies that a cancelled build does not index its snapshot. Explicit send/upload also uses the editor's checkpoint so a provider error does not leave the local save indicator stuck on “Saving”. These follow-ups are included in the final CI gate.

## Still to implement

Outgoing attachments; background sync; permanent queued-operation recovery; conversation rows; counts; bulk actions/Undo; recipient autocomplete and validation; signatures/default-account settings; quoted-text collapsing; adaptive iPad layout; later Zoho and push stages. Device visual/accessibility checks and live signed-device Gmail verification remain outstanding.

## Batch 4 — Unified drafts and received attachments

- The Drafts mailbox and inbox shortcut use one account-scoped view of local edits and cached Gmail drafts. Durable provider draft/message links suppress duplicate Gmail rows without matching subjects. Local deletion explicitly preserves any Gmail copy.
- Received attachments download on demand, open in native Quick Look, and share/save through the system share sheet. Protected files reopen offline. Sync preserves stable attachment identities and cached files; changed attachment parts invalidate their cached references.
- Downloads are limited to 25 MB per file, with metadata and encoded/decoded size checks. Provider filenames cannot escape the account-specific cache directory. Account removal clears its files; unreferenced older files are pruned on storage open.
- Existing schema V1 remains unchanged. HTML/file-containing remote drafts remain protected from the text composer. Outgoing attachments and automatic inclusion when forwarding remain deferred.

Validation: [macOS CI for `d0458c7`](https://github.com/pphilfre/mail/actions/runs/37217569038) passed the simulator build, all 56 unit tests, and all seven UI tests, including six new unit tests and the Drafts-mailbox UI test. Signed-device preview/share/offline checks remain necessary. The network transport buffers the JSON response before enforcing attachment payload limits; streaming transport is still future work.

## Batch 5 — Conversation reader cleanup

Older thread messages start collapsed; the opened message starts expanded and receives initial scroll focus. Sender headers toggle each message with explicit expanded/collapsed accessibility state. Full recipient details expand separately. Reply remains the primary action; Reply all and Forward move into a menu. Drafts omit reply controls. Quoted text within an expanded message remains unchanged.

Draft rows also show their account, edit date, and local/Gmail-copy status. The inbox shortcut now uses the same Drafts name as the drawer. Pending/unconfirmed sends cannot be re-imported through cached Gmail drafts. A DEBUG-only in-memory, provider-free fixture supports a UI test for opening, expanding, and collapsing a cached conversation without live mail or modifying the normal database. Additional unit tests cover protected draft import, symlink escape, and orphan-file cleanup.

The first reader build caught a file-private date helper; it is now a shared design component. The next test run compiled and found a missing-leaf symlink path check and an ambiguous UI-test row query. Cache paths now resolve each parent independently, and the UI identifier is attached to the navigation link with a single-match query. The final gate is tracked in [PR #2](https://github.com/pphilfre/mail/pull/2) and the [branch CI history](https://github.com/pphilfre/mail/actions?query=branch%3Acodex%2Fdrafts-attachments), which record results after this entry was written.

The [audit](ui-feature-audit.md) records the original findings. This page tracks implementation and verification separately.
