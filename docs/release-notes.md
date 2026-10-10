Dispatch v0.8.0 consolidates mail productivity, local intelligence and security improvements.

- Native mail navigation, advanced search dropdowns and saved-search smart folders.
- Device-local scheduled delivery with cancellation and Undo; organisation rules,
  multiple signatures, templates/snippets, scanned PDF attachments and local file OCR.
- Explicit List-Unsubscribe actions and original EML export.
- App lock, incoming file sharing and optional on-device mail intelligence, with account
  and search scope preserved. Model downloads remain optional.
- Evidence-based attachment/QR inspection, original DKIM verification and aligned DMARC
  checks with consent. Incomplete checks retain observed concerns and never imply safety.
- Faster CI through shared simulator compilation, parallel UI shards, incremental build
  caches and device compilation alongside full validation. Publication remains gated on
  every release test, device build and checksum check.

Scheduled delivery requires Dispatch to be open, unlocked and online. The unsigned IPA
requires re-signing with a compatible sideloading tool; automated fixtures do not verify
live Gmail delivery, push notifications or installation on a physical device.

Included from v0.7.0: standalone tasks and faster mail controls and reader.

- Create a task from a title without linking an email or connecting an account. Add status, priority, due date, notes, a list and checklist steps; search tasks and filter by list, progress or due date. Personal tasks survive account removal.
- Use a single icon row for inbox search, All, Unread, Starred and selection. Sync status floats above the dock without increasing header height.
- Emails/Tasks and Compose share a 56-point height. Company logos use more of their compact avatars, with bounded caching and shared requests.
- Both mail controls open the smaller mailbox sheet. Darker tiles separate tools and folders; the profile button opens Accounts directly beside Settings. Secondary folders expand the sheet when needed.
- Accounts uses consistent action typography and icons for connection, reconnect, account preferences and queued changes.
- Cached plain-text messages render natively with selectable text and links. The reader fetches the selected conversation rather than the whole mailbox, uses lazy cards, reuses warm HTML renderers and briefly caches successful thread refreshes. Explicit Retry bypasses that cache.
- HTML reports the actual rendered body height instead of the viewport height, avoiding sizing feedback. Mark read/unread now includes an icon.

Included from v0.6.1:

- Inbox and other mailbox titles now live in the top bar. A Liquid Glass Emails / Tasks pill replaces the bottom tagline.
- The mailbox menu puts frequent folders and tools in a compact grid, keeps Settings beside the profile icon, and folds secondary folders and labels into expandable groups.
- Sender profiles put identity, compose, private notes and icon shortcuts first. Activity charts and detailed history are available on demand.
- Compact inbox reduces padding, avatar size and previews. Preview line settings now reduce actual row height.
- Tasks has an All view alongside Open and Completed, with a direct shortcut from the inbox.
- Receipt detection recognises more transaction confirmations and uses HTML when plain text is empty or incomplete.
- Fixed-width HTML emails fit the reader and resize with the available width. Email scripts remain disabled.

Manual GitHub Actions builds run the full test suite alongside packaging. Publication is gated on both succeeding; artifacts from a failed run are not a validated release. Tag builds also publish a release, and manual builds can opt into publication.

Included from v0.6.0: sender profiles, an attachment library, project collections and a subscription centre, alongside the v0.5.0 tasks, receipts and composer improvements.

- Explore sender history, correspondence counts, weekly activity, files, linked tasks and receipts. Save private nicknames and notes on this device.
- Search downloaded attachment metadata and local draft files, filter by category, and open the source conversation or draft. Offline availability reflects whether the file is present.
- Group account-scoped conversations into named project collections with private notes and Mail, Files, Tasks and Receipts views.
- Review suggested newsletter senders, explicitly include or exclude them, and archive downloaded inbox messages with confirmation and Undo.

These views cover downloaded mail. Newsletter suggestions are heuristic; no automatic unsubscribe action is provided. Private notes, collection membership and newsletter choices stay on this device. Live provider actions and installation require signed-device checks.

Included from v0.5.0:

- Attach files or photos, review names/sizes, preview with Quick Look and remove files before sending.
- Attachments persist with local drafts and survive relaunch or discarding edits.
- Send attachments and save/update Dispatch-created attachment drafts in Gmail.
- Choose whether a forwarded message includes its original attachments.
- Gmail draft revision checks protect copies edited elsewhere from replacement.
- Missing-file reminders now recognise attached files; uncertain-send copies retain attachment previews.
- Turn conversations into tasks with notes and due dates, grouped by Overdue/Today/Upcoming. Complete, reopen and link back to the email.
- Find receipts and invoices in downloaded mail, review detected merchant/amount details, exclude false matches and export filtered receipts as CSV.

Up to 20 files and 20 MB total attachment data per message. Larger files need a smaller copy or sharing link. Arbitrary Gmail drafts containing attachments or rich formatting remain protected and should be edited in Gmail. Background refresh, push notifications and Zoho remain deferred.

Tasks and receipt corrections stay on this device. Task due dates do not schedule notifications. Receipt detection uses cached text and may need correction; no AI service or currency conversion is used.

The release retains the v0.4.0 conversation inbox, bulk actions/Undo, search filters/saved searches, account signatures, recipient assistance, UI redesign and Gmail pacing fixes. Automated tests use fixtures and do not send personal mail.

Tag builds run the full iOS test suite and device build; publication requires both to pass.

The IPA requires iOS 26 or later and is unsigned. Sign and install with your compatible sideloading tool and Apple account. Bundle identifier: dev.freddiephilpot.dispatch.
