Dispatch v0.6.0 adds sender profiles, an attachment library, project collections and a subscription centre, alongside the v0.5.0 tasks, receipts and composer improvements.

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

Tag builds now run the full iOS test suite before building and publishing the device IPA.

The IPA requires iOS 26 or later and is unsigned. Sign and install with your compatible sideloading tool and Apple account. Bundle identifier: dev.freddiephilpot.dispatch.
