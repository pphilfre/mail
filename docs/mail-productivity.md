# Dispatch v0.5.0 — email tasks and receipt organiser

Selected by the user on 5 October 2026 after comparing feature ideas. These capabilities join compose/forward attachments in the same release.

## Email tasks

Open a conversation, choose More → Make task, add a title, notes and an optional due date, then save. Find Tasks in the profile or mailbox menu. Open tasks are grouped into Overdue, Today, Upcoming and No due date. Complete/reopen tasks and open the linked cached conversation. Completed tasks remain in their own view; deleting a task does not change the email.

One open task per account/conversation avoids duplicate follow-ups. References include both message and thread identity so another cached message can reopen the conversation if the first was removed. Notes, dates and completion persist in versioned StoreMetadata rows without altering SwiftData V1. Account removal clears only that account's tasks. Due dates organise the local list; this release does not schedule notifications or sync tasks across devices.

## Receipt organiser

Receipts groups cached purchase/payment/invoice/refund emails by month. Rows show merchant, amount/currency, original subject, date and detected/reviewed status. Search the visible receipt details or filter to the current month. Open the original message, review/correct merchant and amount, or exclude a false match. More → Save receipt on a conversation can include a message the detector did not recognise.

Detection uses bounded cached text or sanitised HTML in a detached task. Strong total labels outrank subtotal/tax/shipping, and ambiguous unlabelled prices remain unknown. GBP/EUR symbols and common currency codes are recognised; bare $/¥ remain ambiguous rather than assuming a country. European and English decimal/thousands formats are supported. It does not read PDF attachments, infer purchase dates from arbitrary prose, verify merchants or convert currencies. Email dates are receipt arrival dates.

Corrections and exclusions are versioned and account-scoped. Export CSV writes the currently filtered receipts and distinguishes detected/reviewed values. CSV cells are quoted and formula-like text is escaped. No mail text is sent to an AI service and no third-party service is contacted for detection.

## Design and validation

The design uses Dispatch's semantic system background/paper colours, blue accent (#2666EB), green completion (#299E6E), secondary grey (#8E8E93), and automatic dark counterparts. SF headings/body and rounded, tabular amount text follow Dynamic Type. Tasks use a due-date checklist; receipts use chronological document rows. Colour always accompanies text or a checkmark. Native sheets, menus, forms and system export keep existing iOS 26 navigation conventions. The layout stays left aligned and adapts stacked receipt amounts when horizontal space is limited.

Unit coverage checks durable task notes/dates/completion, conversation deduplication, account deletion, calendar-day grouping, total/currency parsing, promotional/failed-payment exclusions, cached HTML, receipt corrections, and safe CSV cells. UI fixtures exercise task create/complete/reopen and receipt detection/review; screenshots are retained for inspection. Combined GitHub Actions validation is pending until the branch passes.
