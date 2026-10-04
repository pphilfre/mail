# Dispatch — everyday feature wave

Implemented from the feature ideas and UI audit on 4 October 2026. Validation results are recorded separately below.

## Added capabilities

| Backlog | Capability | Scope |
| --- | --- | --- |
| IN01 | Conversation rows | Latest preview, message count, aggregate unread/star state. Grouping is optional. Provider thread IDs are scoped by account. Only messages matching the active loaded mailbox participate. |
| IN02 | Account nicknames and colours | Editable account preferences; accessible account names accompany colour indicators. |
| IN03 | Mailbox counts | Cached unread message counts and a deduplicated local/Gmail draft count. Counts are explicitly incomplete when older mail is not downloaded. |
| IN04 | Attachment indicator | Paperclip on conversations with cached attachment metadata. |
| TR01 | Bulk selection | Archive, Trash, restore, read/unread, star/unstar, Spam/not-spam, and add labels. Label assignment requires one selected account. |
| TR02 | Undo triage | Ten-second durable Undo record and ordered compensating operations. Only labels changed by the action are restored. No schema migration. |
| TR03 | Mark visible mail read | Select all then Mark read applies to loaded rows, with the exact message count shown. |
| TR06 | Spam | Dedicated mailbox, inbox context action, reader action, and bulk controls. Not spam moves messages to Inbox. |
| SE01 | Search filters | Unread, Starred, Attachments and account selection, combinable with text and operators. |
| SE02 | Search operators | from:, to:, subject:, label:, before:, after:, has:attachment and is:read/unread/starred. Quoted phrases and syntax feedback. Dates are local calendar dates; after is inclusive and before exclusive. |
| SE05 | Search coverage | Results explicitly cover mail downloaded to this device. |
| SE06 | Recent searches | Last ten submitted/opened searches, clear history and disable-history controls. No telemetry or network lookup. |
| OR03 | Saved searches | Up to twenty named query/filter/account combinations, reusable from Search and removable through their contextual menu. Versioned local representation; removed-account searches are hidden. |
| CO01 | Recipient chips | Unfocused addresses appear as removable chips; tap to edit the raw address field. Invalid input remains visible. |
| CO02 | Recipient autocomplete | Cached correspondents ranked by frequency and recency, scoped to the sending account; own accounts and already entered addresses excluded. No Contacts permission. |
| CO03 | Recipient validation | Invalid and duplicate addresses across To/Cc/Bcc prevent Send, with inline explanations. MIME validation remains the final boundary. |
| CO04 | Account signatures | Plain text inserted into new mail/replies before quoted content. Switching accounts replaces an intact signature; edited signatures are preserved. Existing saved drafts are not automatically rewritten. |
| CO05 | Default sending account | Selected inbox account takes priority; default preference is used from All accounts. Replies retain the receiving account. |
| CO09 | Attachment reminder | Attachment wording in the new message text prompts a Send without attachments choice. Quoted/forwarded content and the signature are excluded. |
| Audit P1 | Queued-operation recovery | Account-scoped pending actions and retry. Permanently rejected mailbox mutations pause that target while other messages and refresh can proceed. Outgoing-send uncertainty protections remain separate. |

The simultaneous UI redesign adds its own screen styling, quick filters, confirmation animations and haptics. The simultaneous Gmail fix adds its own request pacing and throttling recovery. Those changes share the combined validation snapshot.

## Boundaries

- Bulk actions use a fixed loaded-message snapshot, including multiple matching messages within each selected conversation. They do not search the whole provider mailbox.
- Undo appends compensation after the original queued operations so an in-flight request cannot finish after the inverse. An unrelated label is not overwritten. Expired records cannot be replayed; account removal clears the record.
- A failed operation remains visible and retains the optimistic cache overlay until an explicit retry succeeds. Later operations for the same provider message wait in order.
- Composer attachments, rich text, background scheduling, adaptive iPad navigation, other providers, AI and backend-dependent features remain separate work.
- Signatures and search history use local preferences. Account deletion removes its signature/default preference. Account nickname/colour use existing model fields.

## Acceptance and validation

New unit coverage checks conversation account isolation, empty thread IDs, batch scope and deduplication, Undo ordering and unrelated labels, Undo after acknowledgement/reopen/expiry, Spam scope, permanent rejection queue ordering, malformed/duplicate recipient inputs, autocomplete formatting, signature changes and quoted-content attachment detection, typed search operators/phrases/dates and account isolation.

New UI coverage uses the existing provider-free reader fixture for grouped bulk archive/Undo, filtered operator search, and invalid-recipient Send gating. Existing draft, reading and sample-mail workflows remain in the suite.

Local verification: diff whitespace checks. Native iOS compilation and XCTest require the macOS CI gate; signed-device Gmail, VoiceOver, large text, iPhone landscape and iPad checks remain required.
