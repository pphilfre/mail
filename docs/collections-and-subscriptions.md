# Project collections and subscription centre

These are part of the unvalidated 0.6.0 development wave. Cloud build, tests and release packaging remain deferred at the user's request. The 0.5.0 release tag is unchanged.

## Project collections

Open **Collections** from the account menu or mailbox sheet. Create a named collection with private notes, then use **Add conversations** to select downloaded mail. Alternatively, use **More → Add to collection** in a reader to add that conversation to an existing or new collection. Search collections by name/notes and search candidate conversations by subject or sender.

Each collection has Mail, Files, Tasks and Receipts tabs. Membership includes the whole account-scoped thread and incorporates later downloaded messages in that thread. A message without a thread ID uses its own provider ID. Trash, spam and drafts are hidden. The selected account filter applies to contents and the conversation picker; collection names remain visible across accounts. Receipt corrections/exclusions and existing task links are reused. File rows link back to their original messages.

Membership and notes are local metadata with version and key validation. Duplicate thread membership is removed on save. Missing accounts cannot be added. Removing an account clears that account's links while retaining the collection and its notes, including an empty collection. Editing notes preserves the latest membership. Removing a conversation from a collection changes only membership. Deleting a collection confirms that mail, attachments, tasks and receipts are kept.

## Subscription centre

Open **Subscriptions** from the account menu or mailbox sheet. Sender groups show unread count, downloaded message count, the number received in the last seven calendar days and latest received date. Open a sender's profile for its history. Use sender search and the unread-only filter to review groups.

Suggestions use conservative newsletter/digest/roundup/bulletin terms, or unsubscribe/preferences language in a snippet or cached plain text. Transactional subjects such as invoices, receipts and shipping confirmations do not qualify solely through unsubscribe text. This is a heuristic, clearly labelled **Suggested newsletter**, and does not establish whether the user has formally subscribed. No remote mail is fetched just to classify a sender.

**Manage newsletter senders** lets the user explicitly Include, Exclude or Reset a sender. Choices are account-scoped and saved locally. With all accounts selected, a choice applies to connected accounts containing downloaded incoming mail from that sender. One excluded account does not hide a sender's mail in another included account. Removing an account clears its choices. Unreadable saved choices are preserved, reported, and cannot be silently overwritten.

**Archive downloaded inbox mail** takes a snapshot of eligible messages, confirms the count, then uses the existing account-scoped batch archive/pending-operation/Undo path. Already archived, sent, draft, trash and spam mail is excluded. It does not promise to affect messages absent from the device. The same sender group remains available after archiving because archived mail is included in its history.

Unsubscribe destinations and last-read timestamps are not currently stored, so the centre does not provide an unsubscribe button or invent last-read dates. Frequencies reflect downloaded messages rather than the complete server mailbox.

## Design and verification

Both tools follow the existing native paper/canvas styling, search and navigation. Collections use a short overview followed by a segmented content picker; subscriptions use sender rows with counts and explicit review actions. File and newsletter action buttons use borderless styles inside lists so adjacent controls remain independent.

Six new unit tests cover collection persistence, deduplicated thread membership, account boundaries, future downloaded thread messages, excluded folders, safe deletion, damaged metadata, account cleanup, newsletter suggestions, manual rule precedence and reset, and seven-day count boundaries including daylight-saving and future messages. Three new UI tests cover creating a collection from a conversation and viewing/removing its files, newsletter detection with exclusion/reinclusion, and confirmed archive with Undo while preserving other mail. These are authored but unrun. The full macOS build/unit/UI/MIME suite and attached screenshot review must pass before release; signed-device checks remain necessary for real downloads and provider actions.
