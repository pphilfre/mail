# Gmail sync investigation — 4 October 2026

Freddie reproduced this on Dispatch v0.3.1. Initial sync now succeeds, but **Load older messages** downloads some messages, waits, and eventually reports **Gmail temporarily limited syncing**. Previously, Sync now remained disabled until force-closing Dispatch.

The latest message confirms a rate-limit response recognised by Dispatch. We have not captured the device's underlying JSON, so we cannot yet distinguish a per-user quota response from another recognised throttle. The disabled control is a separate orchestration problem: Dispatch keeps it disabled while the account is marked busy, including retries and queued follow-up work.

## Google Cloud checks performed

Read-only inspection of project `mail-510512` established:

| Check | Observed result |
| --- | --- |
| Gmail API | Enabled |
| OAuth client | Dispatch iOS; client ID matches `Configuration/GoogleOAuth.plist` |
| Registered bundle | `dev.freddiephilpot.dispatch`; matches `project.yml` |
| Registered callback scheme | Matches the app configuration |
| Audience | External, Testing; Freddie's account listed as a test user |
| Declared consent scopes | All three Data Access scope tables empty |
| Current quota | 6,000 units per minute per user; 1,200,000 per project |
| Legacy quota also displayed | 15,000 units per minute per user |
| Project quota usage shown | 0.39%; not evidence of project-wide exhaustion |
| Per-user quota usage | Not displayed; cannot establish whether that specific limit was reached |

The enabled-API dashboard showed 901 requests with a 5% error rate for its displayed day. The API detail page, using a different 30-day window and all listed credentials, showed HTTP 403 traffic and errors across message retrieval, threads, history, labels, listings and mutations. These totals should not be compared as the same interval or treated as the detailed reason for a particular device request. [Project metrics](https://console.cloud.google.com/apis/api/gmail.googleapis.com/metrics?project=mail-510512), [project quotas](https://console.cloud.google.com/apis/api/gmail.googleapis.com/quotas?project=mail-510512).

The missing declared `gmail.modify` scope is a configuration gap. The app already requests that scope and validates the returned grant. Declaring scopes is distinct from granting permission to an installed app; the empty console list does not prove it caused intermittent throttling. No Cloud settings, scopes or permissions were changed. [Google consent setup](https://developers.google.com/workspace/guides/configure-oauth-consent), [scope documentation](https://developers.google.com/workspace/gmail/api/auth/scopes).

## Why around 100 messages

`GmailAPI.messages()` explicitly asks for 100 IDs. This is a page size, not an account restriction. Gmail supplies `nextPageToken` for further pages and permits list pages up to 500 IDs. A list response contains IDs and thread IDs; each body requires a separate retrieval. Increasing page size would increase the download burst. [Google messages.list reference](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list).

Google's current table charges 20 units per `messages.get`, 5 per `messages.list`, 2 per `history.list`, and 40 per `threads.get`. A 100-message page therefore costs about 2,005 units. Initial All Mail and Inbox retrieval, followed by another 100-body mailbox load, can approach or exceed 6,000 units if they occur in one minute with little overlap. This is a plausible mechanism, not a measured device trace. Current quota changes apply to newer projects; some previously used projects retain earlier quotas. [Google quota reference](https://developers.google.com/workspace/gmail/api/reference/quota).

## Source findings

The v0.3.1 implementation has useful safeguards: sequential message downloads, durable mailbox-specific cursors, small transactional cache writes, incremental history sync, and bounded read retries. However:

1. Sequential downloads had no request pacing. Fast individual responses can still exceed a minute's quota.
2. `GmailAPI` is an actor, but actor methods can interleave at `await`. Thread reads, attachments and mailbox mutations could overlap account sync without a shared transport limit.
3. `loadMailbox()` fetched the same full bodies again, including after `syncAll()` in pull-to-refresh.
4. Read retries used roughly 1, 2, 4 and 8 seconds; their server `Retry-After` delay was clamped to 60 seconds, and HTTP-date values were ignored.
5. A refresh queued during failing work could launch immediately from `finishWork()`, extending the busy state and producing another burst.
6. Mutation 403s became generic HTTP errors. Opening an unread message automatically queues a mark-read mutation; that can explain a generic 403 appearing during reading or downloading, although that particular sequence has not been reproduced here.
7. Retrying a partly cached older page downloaded the already successful bodies again.

## Google’s recommended pattern

Retrieve enough recent messages for a responsive interface, cache their full content, and use `history.list` for later changes. For previously cached content, Google suggests `format=minimal` when only labels need refreshing. An expired history cursor returns 404 and requires a full reconciliation. [Google sync guide](https://developers.google.com/workspace/gmail/api/guides/sync).

Batching reduces HTTP overhead, but each inner request still counts separately. Google recommends no more than 50 calls per batch. It does not remove quota costs. [Google batch guide](https://developers.google.com/workspace/gmail/api/guides/batch).

Retry rate-limit and temporary server failures with exponential backoff and jitter; distinguish quota failures from missing permissions and domain policies using Google's error reason. Google also limits concurrent requests and bandwidth, so quota-unit pacing alone cannot guarantee zero throttling. [Google error handling](https://developers.google.com/workspace/gmail/api/guides/handle-errors).

For later real-time/background support, Gmail `watch` publishes changes through Cloud Pub/Sub; consume those notifications and then drain history. Renew watches at least every seven days; Google recommends daily renewal. Dispatch would need backend delivery and an iOS notification path for this architecture. Push helps ongoing updates but does not eliminate the initial historical download. [Google push guide](https://developers.google.com/workspace/gmail/api/guides/push).

## How other clients approach it

Notion's indexed official Mail help described real-time Gmail sync with specific exclusions. It does not document its internal throttling, batch sizes or transport sufficiently to claim that it bypasses limits or uses a particular Gmail mechanism. Some Mail help pages now redirect to the main help centre, limiting live verification. [Notion's published Mail help](https://www.notion.com/help/create-a-notion-mail-account).

Nylas publishes a more concrete architecture: throttle each mailbox, cap concurrency, honour Retry-After, add jitter, perform one initial historical backfill, checkpoint it, and handle ongoing changes through events. Its API's pagination sizes and request counts are specific to Nylas and should not be copied as Gmail quota arithmetic. [Nylas sync architecture](https://developer.nylas.com/docs/cookbook/email/scale-email-sync/).

IMAP is another supported Gmail interface, using OAuth and persistent connections, but it has session and bandwidth limits too. My recommendation is to keep the Gmail API for Dispatch and fix request scheduling and cache reuse; replacing the provider would add a separate synchronization implementation rather than guarantee unlimited downloads. [Google IMAP documentation](https://developers.google.com/workspace/gmail/imap/imap-smtp), [Google Workspace bandwidth limits](https://knowledge.workspace.google.com/admin/gmail/gmail-bandwidth-limits?hl=en).

## Changes prepared in this checkout

- One transport request at a time per Gmail client, shared by sync, reader, attachment and mutation calls.
- Weighted pacing at 60 quota units per second, leaving headroom under the current user limit. Message downloads run at approximately three per second, before extra latency or backoff.
- Shared account cooldown; honour numeric and HTTP-date Retry-After, including delays beyond a minute.
- Recognise documented legacy and structured Google reason codes without exposing arbitrary server content.
- Keep throttled mailbox mutations queued as temporary failures. Preserve explicit send/draft rejections and prevent automatic replay of sends or draft creation.
- Clear coalesced refresh/mailbox work after a failed operation, releasing the busy state.
- Reuse cached immutable bodies on older-page retries. Mailbox selection processes history before reusing cached bodies; drafts remain eligible for full retrieval.
- Clear stale download errors after a successful retry, and expose a waiting deadline for the UI's Gmail cooldown countdown.

Regression tests cover weighted costs, HTTP-date and long retry delays, shared cooldown across mutation/read calls, concurrent transport serialization, temporary queued-operation failures, partial-page resume, busy-state release and cached mailbox reuse.

The combined macOS CI snapshot `46800f90eb6aecf66ceceb9ef2175584615e59a8` compiled successfully. All 78 unit tests passed, including all seven `GmailRateLimitTests`, all five `GmailPaginationTests` and all 21 existing `GmailTests`. The complete run failed because four of 14 UI tests failed in recipient editing, Undo accessibility and mailbox navigation; the feature and UI chats own those corrections and the final combined gate. [CI run 37224234619](https://github.com/pphilfre/mail/actions/runs/37224234619), [combined draft PR #3](https://github.com/pphilfre/mail/pull/3).

Local whitespace validation passed; Windows cannot run Xcode/iOS tests. The tested provider changes are prepared in source, but no updated signed build has been verified on Freddie's iPhone. The installed v0.3.1 cannot demonstrate these fixes until it is replaced with a build containing them. This report and the provider README are to be included in the final snapshot.

A further improvement would refresh only labels on known messages during history processing while preserving cached content and attachments. Full expired-history reconciliation remains intentionally conservative. Continuous background delivery and automatic resumable whole-mailbox backfill are later architecture work.
