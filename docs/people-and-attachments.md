# Sender profiles and attachment library

This development wave lives on `codex/next-feature-wave`, separately from the preserved `v0.5.0` tag. The marketing version is 0.6.0; it is not a tested release. Cloud builds and simulator tests are deferred at the user's request during the GitHub outage. No local iOS compilation or UI rendering is available on Windows.

## Sender profiles

Open **People** from the account menu or mailbox sheet, or **Sender profile** inside an expanded message. The directory searches sender names, email addresses and private nicknames. Email addresses are normalised for matching; incoming history is grouped by exact address rather than display name.

Profiles include received, sent-to-them, unread and file counts; first/latest received dates; eight calendar weeks of received activity, including empty weeks; conversation history; frequent subjects; exchanged attachments; tasks linked to correspondence; and detected or manually saved receipts from that sender. Use the account picker to see one account or all connected accounts. Dates reflect when messages were received, including for receipts, rather than a guessed transaction date.

All counts and history cover downloaded mail. Spam, trash and drafts are excluded. Sent history matches To, Cc or Bcc recipients on sent messages. Conversation IDs and task links remain scoped to an account even when Gmail reuses provider IDs. Receipts use the existing detector and saved corrections; excluded receipts remain hidden. Unknown amounts remain unknown and currencies are not combined into an inferred spending total.

Nicknames and free-text notes are stored on this device in the existing versioned metadata store, requiring no SwiftData schema change. Notes apply to a sender across connected accounts. A profile remembers the accounts owning its correspondence when notes are saved. Removing an account drops that owner; removing the last owner removes the notes. Unreadable metadata is preserved and cannot be silently overwritten. No social identity lookup or reply-time estimate is added.

## Attachment library

Open **Attachments** from the account menu or mailbox sheet. Search by filename, correspondent, subject or account, filter Documents/Images/Archives/Other, and sort Newest/Largest/Name. Inline images such as signatures are hidden by default and can be included through Library options.

The library includes attachment metadata from downloaded non-draft messages and files in local drafts, scoped to the selected account. It excludes spam and trash. Provider draft attachments enter the library after importing the draft locally, avoiding duplicate provider and local copies. Original email links open the conversation; local draft links reopen the composer. Existing download, Quick Look and share controls are reused.

**Saved for offline use** checks that the backing file is present, rather than trusting a stale cache path. Local draft files use the draft store's integrity verification. The library does not download every listed attachment automatically.

## Design

Keep the existing native paper/canvas surfaces, semantic text, accent-blue controls and system navigation. Profiles give the sender name and private notes their own space; rounded, tabular counts and a compact native chart provide an overview. A segmented control switches between history, files, tasks and receipts. The attachment library uses document rows with the source directly below each file. Both views keep system search, account context and accessibility text; statistics wrap vertically when horizontal space is limited.

## Verification to run when cloud builds resume

The new unit tests cover sender/address and account scoping, sent recipients, excluded folders, directory naming/unread counts, zero-filled calendar weeks and future-date exclusion, subject grouping, account-scoped task links, notes reopening and owner cleanup, damaged metadata preservation, attachment categories and offline/account filters, and deterministic sorting.

Three new UI tests cover opening a profile from a conversation, saving a nickname and notes and viewing sender files, and library search with a source conversation link. A debug-only library fixture adds metadata for a document and inline image; it never makes provider requests. Screenshots are attached by the UI tests for visual review. These tests are authored but unrun. Resume the full existing macOS build/unit/UI/MIME suite before tagging or publishing 0.6.0. Live downloads and Quick Look/share still require signed-device checks.
