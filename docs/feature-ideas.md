# Feature ideas to explore

Project collections and a subscription centre were selected and implemented in the current development wave alongside sender profiles and the attachment library. See [their implementation and current limits](collections-and-subscriptions.md). Other items below are proposals.

## Project collections

Implemented with local collections and explicit conversation membership. A later addition could suggest related mail that the user accepts. Account context and original source links remain visible.

## Follow-up radar

Keep a list of conversations where you sent the latest downloaded message and may be awaiting a response. Let the user set a follow-up date and dismiss resolved items. Mark it as a suggestion: incomplete cached threads cannot prove that someone has not replied. Explicit reminder scheduling would need a separate notification permission and settings flow.

## Subscription centre

Implemented with sender groups, downloaded frequency, unread counts, latest received dates, manual inclusion/exclusion and confirmed bulk archive. Last-read timestamps are not currently recorded. Unsubscribe actions would need to expose the sender's supplied destination and require an explicit user action, especially where a link opens a website.

## Reusable replies

Save frequently used text as named snippets, insert a snippet into the composer and edit it before sending. Examples include arranging a meeting, confirming receipt or requesting an invoice. Begin with plain text, account scope and a small searchable picker.

## VIPs and quiet hours

Pin important sender profiles and let the user find their unread mail quickly. A later notification phase could have quiet hours and VIP exceptions once push and local reminder support exist. Pins alone are useful without changing notification delivery.

## Decisions and promises

Manually mark a message as a decision or commitment and give it a short note. A sender or project timeline can then surface what was agreed without rereading an entire thread. Keep the source link visible and leave interpretation to the user.

## Duplicate file finder

After downloading files, compare verified hashes to show repeated attachments and their source messages. Let the user keep one offline copy while retaining all email links. Do not delete provider attachments or infer duplicates from filenames alone.

## Delivery and return dates

Let the user record an expected delivery date or return deadline on a saved receipt. Group upcoming dates and overdue deliveries with direct links to the order email. Begin with manually reviewed dates rather than treating email text detection as authoritative.
