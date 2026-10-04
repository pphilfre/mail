# Dispatch — UI and feature audit

Reviewed 4 October 2026 against the current source and product brief.

Goal: a calm, native mail app with clear navigation, dependable everyday actions, and minimal visual clutter.

This is a source review. Layout, animation, performance, and accessibility findings marked **Verify** need an iPhone/iPad simulator or signed device. No app code was changed and no iOS build was run.

Priority: **P1** = core usability or reliability; **P2** = everyday polish; **P3** = later capability. **Missing** means absent from the reviewed implementation. **Change** means existing behavior needs improvement. **Verify** means a runtime check is required.

## 1. Fix first

| Priority | Status | Item | Recommended change |
| --- | --- | --- | --- |
| P1 | Missing | Local search | Add instant search across cached sender, recipients, subject, preview, account, labels, and attachment names. Include clear/reset and useful no-results states. |
| P1 | Missing | General attachments | Add download, preview, share/save, and compose upload with progress, failure, and retry states. Inline raster images already have partial support. |
| P1 | Change | Incorrect pagination context | “Load older mail” always uses the All Mail cursor. Keep pagination per account and mailbox/label so older Sent, Trash, and label messages load predictably. |
| P1 | Change | Split draft navigation | Combine local and Gmail drafts in one Drafts destination, with small status indicators. The current drawer opens server drafts while local drafts have a separate inbox row. |
| P1 | Missing | Draft autosave | Save edits locally after a short debounce and at lifecycle transitions. The current composer persists on explicit save/send/upload, leaving later unsaved edits vulnerable to termination. |
| P1 | Change | Remote draft content preservation | Import converts server drafts to text and the composer emits text MIME. Preserve or explicitly warn before replacing rich content and attachments when editing an existing Gmail draft. |
| P1 | Missing | Network-return and background sync | Resume pending actions when connectivity returns and schedule supported background refresh. Current retries run on launch, foreground, and pull-to-refresh. |
| P1 | Change | Failed operation recovery | Expose account-scoped pending/failed actions and a retry path. A failed queued operation currently stops the flush before mailbox sync; define recovery for permanent failures so they do not indefinitely block fresh mail. |

Evidence: [Search](../Features/Search/README.md), [Inbox](../Features/Inbox/InboxView.swift), [Composer](../Features/Compose/ComposeView.swift), [Gmail coordinator](../Providers/Gmail/GmailCoordinator.swift), [Gmail limitations](../Providers/Gmail/README.md).

## 2. Make the inbox cleaner

| Priority | Status | Item | Recommended change |
| --- | --- | --- | --- |
| P1 | Change | Error clutter | Replace repeated global/account error text with one compact status banner, naming the affected account and offering Retry or Reconnect. Put technical details behind a disclosure. |
| P1 | Change | Send recovery dominates the inbox | Move unconfirmed outgoing messages to a dedicated recovery/outbox destination. Show a compact inbox indicator; retain the protection against automatic duplicate sends. |
| P2 | Change | Account context | Show the selected account beneath the mailbox title or as a small account indicator. Currently the title stays “Inbox” when the account changes. |
| P2 | Missing | Conversation rows | Group cached messages into conversation rows with a message count and latest preview. Currently every message gets its own row, although opening one displays its thread. |
| P2 | Change | Useful timestamps | Show time for today's messages and a concise date for older mail. Live rows currently always use a date; sample rows use time. |
| P2 | Missing | Attachment and account indicators | Add a subtle paperclip and distinguish accounts in the unified inbox. Account colour data exists but is not used in the rows. |
| P2 | Missing | Bulk actions and Undo | Add selection for archive, trash, read/unread, and labels; provide a brief Undo affordance for archive/trash. |
| P2 | Change | Empty/loading states | Separate an empty mailbox, initial loading, offline cache, and load failure. “No cached messages” currently covers all of them. |
| P2 | Change | Pagination and sync presentation | Use a compact loading footer with an end-of-list state. Avoid repeated account-email loading buttons and a separate sync row competing with messages. |
| P2 | Change | Sample mode consistency | Sample rows ignore the selected mailbox and preview-line preference. Make the demo reflect those controls, or keep its navigation explicitly scoped to sample mail. |

Evidence: [Inbox and rows](../Features/Inbox/InboxView.swift), [Account and thread models](../Core/Storage/MailModels.swift).

## 3. Simplify navigation and composing

| Priority | Status | Item | Recommended change |
| --- | --- | --- | --- |
| P2 | Missing | Mailbox counts | Add unread counts to Inbox, Unread, accounts, and relevant labels; add a draft count to Drafts. |
| P2 | Change | Account switching | Make account selection feedback immediate and predictable; restore the last selected account/mailbox on relaunch. Current selection is transient view state. |
| P2 | Missing | Spam destination | Add Spam with move-to-spam and not-spam actions. Spam is stored and excluded from common mailbox views, but has no destination. |
| P2 | Change | Compose action hierarchy | Put Send in the top bar, use a concise close/draft flow, and move the long technical footer into contextual help. Send currently sits below the body while Save draft occupies the top bar. |
| P2 | Missing | Recipient assistance | Add recipient chips, autocomplete, address validation before sending, and a clear indication of invalid addresses. Current entry is a raw text field; MIME validation occurs on send/upload. |
| P2 | Missing | Default sending account and signatures | Add a preferred account and per-account signature. Consider the active inbox account when opening a new composer. |
| P2 | Change | Reconnect account targeting | Reconnect currently starts generic Google sign-in. Guide it toward the chosen account and explain if the returned account differs. |
| P2 | Change | Local draft clarity | Show account, last-edited time, and local/server status in draft rows; respect the selected account when browsing drafts. Current local drafts are global. |

Evidence: [Inbox drawer](../Features/Inbox/InboxView.swift), [Composer](../Features/Compose/ComposeView.swift), [Drafts](../Features/Compose/DraftsView.swift), [Accounts](../Features/Accounts/AccountsView.swift), [App shell](../App/AppShell.swift).

## 4. Improve the reader

| Priority | Status | Item | Recommended change |
| --- | --- | --- | --- |
| P2 | Change | Long conversations | Collapse older messages and quoted text; initially focus the opened/unread message. Every cached thread message currently expands with its own full body and reply controls. |
| P2 | Change | Action density | Use a consistent primary reply affordance and an action menu or bottom toolbar. Repeated Reply / Reply all / Forward button rows make long threads busy. |
| P2 | Change | Recipient details | Show a compact summary that expands to full To/Cc details and date. Long recipient lists currently render directly as header text. |
| P2 | Change | Remote-image prompt accuracy | Show the prompt only when remote images are actually blocked. It currently appears for any thread with cached HTML, including HTML without external images; “Load images” applies to the whole thread. |
| P2 | Change | Reader error recovery | Add a scoped loading/retry state for fetching the full thread. Avoid displaying an unrelated shared Gmail error at the bottom of a message. |
| P2 | Change | Sender icon privacy and clarity | Keep initials as the dependable fallback. Clearly explain that company icons fetch from sender domains independently of remote email images; consider an explicit opt-in or shared privacy preference. |

Evidence: [Reader](../Features/Message/GmailMessageView.swift), [HTML renderer](../Features/Message/MailHTMLView.swift), [Sender avatars](../DesignSystem/SenderAvatar.swift), [Settings](../Features/Settings/SettingsView.swift).

## 5. Visual and accessibility checks

These are checks to perform, not confirmed rendering defects.

| Priority | Status | Item | What to verify |
| --- | --- | --- | --- |
| P1 | Verify | Small screens and large text | Welcome screen fit, sender/date collisions, drawer email truncation, compose field labels, and wrapping of reply buttons. Test landscape and keyboard-visible layouts too. |
| P1 | Verify | Drawer accessibility | VoiceOver focus enters the drawer, underlying inbox/toolbar controls cannot receive focus while it is open, selected rows announce selection, and closing restores focus. |
| P1 | Verify | HTML layout and appearance | Wide tables, fixed-width newsletters, dark-mode colours, delayed image height updates, text scaling, and links. The web view disables internal scrolling, so content must remain readable within the reader width. |
| P2 | Verify | iPad layout | Use available width deliberately. The project supports iPad but currently uses the same NavigationStack and full-width inbox/reader rather than an adaptive split layout. |
| P2 | Verify | Large mailbox performance | Measure scrolling/filtering with thousands of cached messages and long HTML threads. Inbox and reader query all messages and filter in memory; move filtering and pagination into storage when measurements justify it. |
| P2 | Verify | Touch targets and transitions | Check icon-only drawer controls, captions used as buttons, reduced motion, keyboard dismissal, sheet transitions, and light/dark contrast. |

Evidence: [App shell](../App/AppShell.swift), [Inbox](../Features/Inbox/InboxView.swift), [Reader](../Features/Message/GmailMessageView.swift), [HTML renderer](../Features/Message/MailHTMLView.swift), [Device targets](../project.yml).

## 6. Later features

- **P3 — Zoho support:** implement the deferred provider and complete the cross-provider unified inbox. Keep the current unavailable sign-in treatment explicit.
- **P3 — Push notifications:** implement the notification backend, device registration, and properly provisioned APNs support; preserve sync fallback.
- **P3 — Organisation:** label creation/rename, account colours/nicknames, saved searches, and optional snooze or custom views.
- **P3 — Sending tools:** aliases, richer formatting, and optional scheduled send or delayed send cancellation.

These are roadmap items; label assignment, custom swipes, remote-image blocking, HTML reading, and light/dark preferences already exist.

## Completion checks

- Signed-device Google sign-in, refresh, sync, send, reply, reply-all, and Gmail draft lifecycle still need the documented live verification.
- Expand UI fixtures beyond sample mail: connected accounts, thread reader, empty/loading/error states, account filters, remote drafts, and send recovery.
- Reconcile documentation with the current 0.3.0 source: README/stage ledger still describe the reader as text-only in places, while HTML rendering is implemented.

Evidence: [Device checklist](oauth-setup.md), [UI tests](../Tests/UI/DispatchUITests.swift), [README](../README.md), [Stage ledger](stages.md), [Release notes](release-notes.md).

## Visual direction

Keep one compact mailbox/account header, one consistent message-row layout, semantic system colours, and restrained glass on navigation controls. Keep settings and diagnostics out of the normal reading flow. Introduce new controls only where they help the current task; avoid adding permanent badges and banners for every state.

Recommended order: core search/attachments/draft safety → pagination and recovery → inbox/navigation/compose cleanup → reader polish → device accessibility and layout checks → later providers and notifications.
