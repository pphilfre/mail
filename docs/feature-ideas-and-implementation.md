# Dispatch — feature ideas and implementation backlog

Researched **4 October 2026**. **180 ideas across 18 areas**, with competitor references, implementation approaches, dependencies, and a suggested build order.

This is a planning document, not a promise to ship every feature. Competitor observations come from official product documentation. Dispatch implementation proposals are our own designs; a feature appearing in another company's app does not establish that its provider API exposes that feature.

## Product direction

Build a dependable, calm, native mail app: fast cached mail, clear account context, safe composing, and simple ways to organise and follow up. Keep the default inbox chronological and uncluttered. Offer advanced workflows through optional views, contextual actions, and settings.

The strongest potential identity for Dispatch is **private, dependable email with lightweight follow-up tools**. AI, team collaboration, and cloud services can be optional additions once the everyday experience is excellent.

## Current Dispatch baseline

The existing implementation includes Gmail OAuth, multiple Gmail accounts, cached mail and HTML reading, replies and text forwarding, read/star/archive/trash/label actions, a durable operation queue, local draft autosave, guarded Gmail draft editing, account/mailbox pagination, cached metadata search, account selection persistence, connectivity-return retries, and protected uncertain sends.

Unified local/Gmail draft navigation and received attachment download/preview/share are being developed in the main conversation. Treat them as **in progress**, not verified shipped features. This document does not change that implementation. Composer attachments, background refresh, conversation rows, bulk actions, signatures, recipient assistance, Zoho, and push notifications remain important gaps. The historical [audit](ui-feature-audit.md) and [implementation progress](improvement-progress.md) provide context; they may lag active branch changes.

## What other brands offer

These are selected examples, not exhaustive comparisons. Availability can vary by plan, platform, account type, and region; no pricing assumptions are used here.

| Brand | Observed features | Useful direction for Dispatch | Official evidence |
| --- | --- | --- | --- |
| Gmail | Category tabs, snoozing, scheduled sending | Optional categories and a later/scheduled workflow; distinguish Gmail's interface from API capabilities | [Inbox layout](https://support.google.com/mail/answer/18522?hl=en), [Snoozing and organisation](https://support.google.com/mail/answer/9259770?hl=en), [Scheduled sending](https://support.google.com/mail/answer/9214606?co=GENIE.Platform%3DDesktop&hl=en) |
| Apple Mail | Undo Send delay, Remind Me, Mail Privacy Protection | Native interactions, deliberate send cancellation, and privacy controls | [Undo Send](https://support.apple.com/en-gb/guide/iphone/iph0e7288015/ios), [Reading and reminders on iOS 26](https://support.apple.com/en-al/guide/iphone/iph461684497/26/ios/26), [Privacy protection](https://support.apple.com/en-ph/guide/iphone/iphf084865c7/ios) |
| Outlook | Focused/Other inbox, sender-based Sweep, rules, conversation display | Optional prioritisation and predictable batch cleanup | [Focused Inbox on mobile](https://support.microsoft.com/en-us/outlook/what-is-focused-inbox), [Sweep and rules](https://support.microsoft.com/en-us/outlook/officeweb/organize-your-inbox), [Message display](https://support.microsoft.com/en-us/outlook/mail/change-how-the-message-list-is-displayed-in-outlook) |
| Spark | Gatekeeper, configurable inbox groups, batch card actions, shared drafts | Sender screening, optional grouping, and a later collaboration track | [Inbox customisation](https://sparkmailapp.com/help/manage-your-inbox/customize-your-inbox) |
| Superhuman | Custom Split Inboxes, snippets, conditional follow-up reminders, keyboard commands | Saved views, reusable replies, and fast follow-up workflows | [Custom splits](https://help.superhuman.com/hc/en-us/articles/46005636204941-Custom-Split-Inbox), [Remind Me](https://help.superhuman.com/hc/en-us/articles/46005666142733-Remind-Me), [Snippets workflow](https://help.superhuman.com/hc/en-us/articles/46005781481741-Sales) |
| HEY | Screener, Imbox, newsletter Feed, receipt Paper Trail, Reply Later | Separate reading, transactions, and actionable conversations without deleting mail | [How HEY works](https://www.hey.com/how-it-works/), [Product updates](https://www.hey.com/new/) |
| Shortwave | Splits, bundles, email-linked todos, AI-enhanced search | Group repetitive messages and connect conversations to lightweight tasks | [Features](https://www.shortwave.com/), [Splits and bundles](https://www.shortwave.com/blog/split-email-inbox-by-importance/) |
| Proton Mail | Enhanced tracker protection and hide-my-email aliases | Strong privacy defaults and provider-backed identity controls | [Tracker protection](https://proton.me/support/email-tracker-protection), [Aliases](https://proton.me/support/aliases-mail) |
| Fastmail | Masked Email, permanent aliases, a documented JMAP API | Sending identities and a later standards-based provider adapter | [Masked Email](https://www.fastmail.com/features/masked-email/), [Developer API](https://www.fastmail.com/dev/) |
| Edison Mail | Unsubscribe tools, focused inbox, extracted travel/receipt/package information | A subscription centre and optional useful detail cards | [Features](https://www.edisonmail.com/features), [Assistant](https://www.edisonmail.com/features/edison-mail-assistant) |
| Canary Mail | Tracking-pixel read receipts and SecureSend with recipient access links | Evaluate secure sharing separately; avoid treating image opens as proof someone read a message | [Read receipt implementation](https://canarymail.io/help/how-does-canary-mail-implement-read-receipts), [SecureSend](https://canarymail.io/help/securesend-what-is-it-how-does-it-work-canary) |

The backlog below adapts these broad patterns and adds Dispatch-specific ideas. It does not claim every listed idea exists in every named app.

## How to read the backlog

**Route:** `L` = local app/storage work; `P` = mail-provider API work; `S` = Apple system integration or permission; `B` = backend service; `A` = AI model. Combined codes mean multiple dependencies.

**Size:** `S` = contained change; `M` = several components; `L` = substantial feature; `XL` = new subsystem or product track. These are relative complexity estimates, not delivery dates. Even small features need appropriate verification.

All entries are proposals or extensions of existing work. **In progress** appears where the main implementation already overlaps. The build sequence later in this document supplies prioritisation.

## 1. Inbox and navigation

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| IN01 | Conversation rows | Project messages by account plus provider thread ID; show latest preview, unread state, and message count. Keep individual-message mode optional. | L | M |
| IN02 | Account colours and nicknames | Use existing account colour/name fields; add Settings editing and a subtle row indicator with an accessible text equivalent. | L | S |
| IN03 | Mailbox unread counts | Compute cached counts in storage; fetch provider counts when supported and distinguish cached counts from complete mailbox totals. | L/P | M |
| IN04 | Attachment indicator | Add a small paperclip when attachment metadata exists; announce it with the row's accessibility label. | L | S |
| IN05 | Optional Focused view | Begin with explicit VIPs and sender rules; explain why a thread appears and support moving it back to the regular view. | L | M |
| IN06 | Gmail category views | Map existing CATEGORY_* label IDs into optional views; keep the ordinary inbox available and scope pagination by category. | L/P | M |
| IN07 | Pinned conversations | Persist a user pin separately from provider stars; place pins in an optional section and allow simple removal. | L | M |
| IN08 | Adaptive iPad layout | Use NavigationSplitView for accounts/mailboxes, conversations, and reader; retain compact navigation on iPhone. | L | L |
| IN09 | Favourite mailboxes | Persist a small ordered list of mailbox/label references; expose reorder/hide controls in Settings. | L | S |
| IN10 | Restore reading position | Save account, mailbox, selected thread, and list anchor; restore only if the destination still exists. | L | M |

## 2. Triage and bulk actions

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| TR01 | Multi-select mail | Add native list selection and a contextual toolbar; batch archive/trash/read/star/label over a fixed selected-ID snapshot. | L/P | M |
| TR02 | Undo archive and trash | Save previous labels and action state; cancel unsent operations or enqueue a compensating action after provider acknowledgement. | L/P | M |
| TR03 | Mark all visible mail read | Show the exact scope and count; apply only to loaded matching messages unless a full-mailbox job is explicitly selected. | L/P | M |
| TR04 | Sender cleanup / Sweep | Offer archive all cached mail from this sender; add provider search and a preview before acting on older messages. | L/P | L |
| TR05 | Domain cleanup | Group senders by domain, preview affected messages, and allow exclusions before a batch archive operation. | L/P | M |
| TR06 | Spam and not-spam actions | Add Spam navigation plus SPAM label modifications; support moving legitimate mail back and preserving account scope. | L/P | M |
| TR07 | Thread mute | Start with a Dispatch notification/view preference; expose provider-native mute only after verifying an API-supported equivalent. | L/P | M |
| TR08 | Auto-advance after action | Let users choose next, previous, or return to inbox; base selection on the current filtered list snapshot. | L | S |
| TR09 | Triage-only session | Open an optional focused stack of unread conversations with consistent action controls and a clear exit. | L | M |
| TR10 | Retention cleanup preview | Find old promotions or large mail locally/provider-side; show a reviewable selection before archive/trash and never silently delete. | L/P | L |

## 3. Organisation and custom views

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| OR01 | Create and rename labels | Add label management through the provider adapter; validate names and refresh cached folders after success. | L/P | M |
| OR02 | Label colours | Store local presentation colours first; optionally read/write provider label colours where supported. | L/P | S |
| OR03 | Saved searches / smart folders | Persist a versioned filter expression; render through the same search engine and show whether coverage is cached or online. | L | M |
| OR04 | Project collections | Link unrelated threads into a local collection without changing provider threading; allow notes and removal. | L | M |
| OR05 | VIP sender list | Persist normalised addresses per account; use it for filters, optional prioritisation, and notification preferences. | L | S |
| OR06 | Sender screening | Put first-time senders in an optional local review view; accept/block choices should not modify server mail without an explicit rule. | L/P | L |
| OR07 | Local rule builder | Match sender/domain/subject/labels and preview classification; initially change local views, then add explicit queued provider actions. | L/P | L |
| OR08 | Provider-side rules | Offer Gmail filters through documented settings endpoints and required consent; state that server rules apply outside Dispatch too. | P | L |
| OR09 | Sender bundles | Group newsletters/alerts into expandable rows; keep messages individually accessible and offer scoped batch actions. | L | M |
| OR10 | Work and personal workspaces | Save account sets, default sender, favourite views, and notification preferences as named profiles. | L/S | L |

## 4. Search and discovery

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| SE01 | Search filter chips | Add sender, recipient, account, date, attachment, unread, and label controls using a shared typed search expression. | L | M |
| SE02 | Search operators | Parse from:, to:, subject:, before:, after:, has:attachment and quoted phrases; show syntax errors without discarding the query. | L | M |
| SE03 | Cached body search | Index decoded cached plain text and sanitised HTML text off the main actor; update only changed/deleted message documents. | L | L |
| SE04 | Search older mail online | Provide an explicit Search Gmail action; issue debounced requests and merge cached results by account/provider identity. | L/P | M |
| SE05 | Coverage indicator | Explain that local results cover downloaded mail; expose date ranges and a route to fetch more. | L | S |
| SE06 | Recent searches | Store a capped local history with clear-all and private-mode options; avoid placing mail queries in telemetry. | L | S |
| SE07 | Match highlighting | Return field ranges from the search engine; highlight subject/snippet matches while respecting Unicode offsets and Dynamic Type. | L | M |
| SE08 | Attachment library search | Build a file view over attachment metadata with type/sender/date filters, download state, and links back to messages. | L | M |
| SE09 | OCR attachment search | Use Vision on explicitly downloaded images/PDF pages; index extracted text locally with file-size and page limits. | L/S | L |
| SE10 | Natural-language query translation | Turn phrases into a visible editable filter expression; keep deterministic search available when AI is unavailable. | L/A | L |

## 5. Reading and conversations

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| RE01 | Collapse older messages | Initially expand the selected/unread/latest message; retain per-thread expansion state and a Show all control. | L | M |
| RE02 | Fold quoted replies | Detect conventional quoted text and HTML quote blocks; preserve the full original behind an explicit expandable control. | L | M |
| RE03 | Compact recipient details | Show a short recipient summary with a sheet for full To/Cc, date, sender, and reply-to details. | L | S |
| RE04 | One consistent reply toolbar | Place primary Reply in a stable location; move reply-all, forward, print, and organisation actions into contextual menus. | L | M |
| RE05 | Reading font and spacing | Add reader-only font size/line spacing preferences; apply safe HTML styling without overriding essential message content. | L | M |
| RE06 | Newsletter reading mode | Extract readable text/article structure from cached HTML; offer Original view so extraction mistakes are recoverable. | L | L |
| RE07 | Find within a conversation | Search loaded message bodies, navigate matches, and expand the relevant message automatically. | L | M |
| RE08 | Print and PDF export | Render selected message/thread through a print formatter; include sender/date and clearly identify exported attachments. | L/S | M |
| RE09 | Sender history panel | Query cached conversations by normalised sender; show recent mail, files, and contact actions in a sheet. | L | M |
| RE10 | Read aloud | Offer AVSpeechSynthesizer for sanitised text with pause/stop controls; stop when the reader closes or account changes. | L/S | M |

## 6. Composer and recipients

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| CO01 | Recipient chips | Parse entered addresses into editable chips; retain invalid input visibly and allow keyboard/accessibility editing. | L | M |
| CO02 | Recipient autocomplete | Rank cached correspondents locally; optionally add Contacts suggestions after permission with account-aware identity exclusion. | L/S | M |
| CO03 | Validation before Send | Show invalid/duplicate recipients inline; keep final MIME validation as a second boundary. | L | S |
| CO04 | Per-account signatures | Persist plain-text signatures first; insert once and track the signature region so switching sender does not duplicate it. | L | M |
| CO05 | Default sending account | Add an explicit preference; prefer the selected account for new mail and the received account for replies. | L | S |
| CO06 | Snippets and templates | Store named reusable text with explicit placeholders; preview substitutions and insert at the cursor. | L | M |
| CO07 | Rich-text composing | Use a constrained attributed editor; serialise multipart/alternative HTML plus text and test round-trip preservation. | L/P | L |
| CO08 | Sending alias picker | Fetch verified provider send-as identities; make the selected From clear and include all own aliases in reply-all exclusion. | P/L | L |
| CO09 | Missing-attachment reminder | Detect common attachment phrases when no files are attached; offer Send anyway rather than blocking legitimate messages. | L | S |
| CO10 | Recipient groups | Store user-defined groups or import authorised Contacts groups; expand to explicit recipients and preview To/Cc/Bcc placement. | L/S | M |

## 7. Attachments and files

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| AT01 | Download, preview, share/save — in progress | Finish protected file caching, Quick Look, native sharing, retries, and offline reuse; preserve attachment identity across sync. | L/P/S | M |
| AT02 | Attach from Files | Use fileImporter with security-scoped access; copy bytes into protected draft-owned storage before persisting references. | L/S | L |
| AT03 | Attach photos | Use PhotosPicker; optionally choose image size, preserve filename/type, and show the actual encoded send size. | L/S | M |
| AT04 | Camera/document scan | Present a native scan flow; save a bounded PDF as a draft attachment and allow preview/remove before Send. | L/S | M |
| AT05 | Forward with attachments | Let users choose retained files; download missing bytes and construct fresh MIME instead of relying on provider attachment IDs. | L/P | L |
| AT06 | Transfer progress and cancellation | Add a transport path that reports bytes; persist completed files only and clean partial downloads after cancellation. | L/P | L |
| AT07 | Cache storage management | Show per-account disk use; remove downloaded files while preserving mail/attachment metadata and enable a retention budget. | L | M |
| AT08 | Save several attachments | Stage a user-selected group and export through a native document flow; report individual failures instead of losing successful files. | L/S | M |
| AT09 | Attachment warnings | Identify suspicious executable types, oversized files, and filename/type mismatches; keep viewing optional and avoid unsupported malware claims. | L | M |
| AT10 | Large-file link sharing | Integrate an explicit cloud upload service with authentication, access controls, expiry, revocation, and an upload-before-send state. | P/B | XL |

## 8. Drafts and delivery

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| SD01 | Unified Drafts — in progress | Combine local and Gmail copies using stable draft-to-message links; retain local edit access offline and clarify delete-local versus delete-server. | L/P | M |
| SD02 | Draft sync status | Track last successfully uploaded content digest/time; distinguish Saved here, Gmail up to date, Local changes, and Upload failed. | L/P | M |
| SD03 | Draft conflict resolution | Compare local base/version with fetched remote MIME; offer Keep local, Use Gmail, or Save separate copy without silent overwrite. | L/P | L |
| SD04 | Recent draft versions | Keep a small protected version history; restore explicitly and prune by age/size without resurrecting sent messages. | L | M |
| SD05 | Undo Send delay | Persist a queued-but-not-submitted message; cancellation returns it to editing, and provider submission closes the undo window. | L/P | L |
| SD06 | Scheduled send while app is closed | Use a backend-owned scheduled job and one sending authority; expose cancellation, credential failure, and ambiguous-delivery states. | B/P | XL |
| SD07 | Offline outgoing queue | Explicitly accept a pending-send state; submit only after validation, preserve stable Message-ID, and never automatically replay uncertain POSTs. | L/P | L |
| SD08 | Outbox delivery timeline | Show Queued, Submitting, Sent, Rejected, or Unconfirmed with safe actions; avoid claiming recipient delivery or reading. | L/P | M |
| SD09 | Rich Gmail draft preservation | Preserve supported MIME parts and raw content; otherwise keep a view-only original and offer a separately created text draft. | L/P | L |
| SD10 | Provider vacation responder | Add account-level setup using documented settings APIs, required scopes, dates, and explicit server-side activation. | P | L |

## 9. Follow-ups and lightweight tasks

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| FU01 | Snooze / Later | Persist thread reference and wake time; locally hide it from the normal view and resurface due items on foreground. | L/S | M |
| FU02 | Remind if no reply | Record outgoing Message-ID, thread, and deadline; cancel only when a qualifying incoming reply is synced. | L/P/S | L |
| FU03 | Reply Later list | Give conversations a local action-needed state independent of unread; expose it as an optional destination. | L | M |
| FU04 | Waiting for reply view | Group explicitly tracked sent conversations; show the expected date and an easy route to draft a follow-up. | L | M |
| FU05 | Convert mail to task | Create a local task with title, due date, completion, and a deep link to the original conversation. | L | M |
| FU06 | Personal conversation notes | Attach protected local notes to account/thread identities; separate them visually from actual email content. | L | M |
| FU07 | Task groups/projects | Group tasks and linked threads; support basic reorder/completion without building a full project-management system. | L | M |
| FU08 | Deadline suggestion | Detect explicit dates in selected mail; show source text and ask the user to choose timezone/time before creating a reminder. | L/S/A | M |
| FU09 | Follow-up draft suggestion | Generate or insert a template after a deadline; leave it as a reviewable draft and never send automatically. | L/A | M |
| FU10 | Daily follow-up review | Offer a manually opened Today view over due tasks and waiting conversations; add optional notifications later. | L/S | M |

## 10. Newsletters and subscriptions

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| NL01 | Newsletter view | Identify mailing-list headers and sender preferences; create an optional reading destination without deleting or moving mail automatically. | L/P | M |
| NL02 | Safe unsubscribe action | Parse List-Unsubscribe and List-Unsubscribe-Post; show the destination, confirm, and use standards-aware provider/HTTP handling. | L/P | L |
| NL03 | Subscription centre | Group cached list mail by list ID/sender; show frequency, recent subjects, and explicit unsubscribe or classification actions. | L | M |
| NL04 | Batch unsubscribe review | Let users select subscriptions, preview each destination, and report results individually; never fire hidden requests on classification. | L/P | L |
| NL05 | Newsletter reading queue | Bookmark issues for later reading, save local reading position, and make removal distinct from server deletion. | L | M |
| NL06 | Scheduled reading digest | Produce a local list of new newsletter issues at chosen times; notifications can point to it without altering provider delivery. | L/S | M |
| NL07 | Bundle by publication | Group issues under list identity rather than spoofable display name; expand to ordinary messages. | L | M |
| NL08 | Save useful excerpts | Save selected text with sender/date/source link; preserve context and allow export to Notes or a file. | L/S | M |
| NL09 | Quiet noisy senders | Add local notification suppression and a dedicated view; clearly distinguish quieting from unsubscribe or blocking. | L/S | S |
| NL10 | Subscription review suggestions | Use local frequency/interaction signals only with opt-in tracking; suggest review and avoid treating unopened mail as unwanted by default. | L | M |

## 11. Useful detail cards

These are inspired by the general assistant-card pattern. Extraction accuracy and usefulness need testing; begin with user-opened messages rather than continuous inbox-wide scanning.

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| DE01 | Receipt details | Extract merchant/date/currency/amount from known formats; show source and uncertainty, with correction and original-message access. | L/A | L |
| DE02 | Invoice due dates | Parse explicit invoice/due fields; offer a reminder after user confirmation and avoid equating extraction with payment status. | L/S/A | L |
| DE03 | Package tracking cards | Detect supported tracking references; open carrier links first and add live carrier APIs only under a separate integration. | L/P | M |
| DE04 | Travel itinerary view | Collect confirmed booking details from cached mail; preserve departure-local timezones and link each field back to its message. | L/A | L |
| DE05 | Reservation details | Extract venue/date/time/reference; offer calendar entry or directions only after reviewing parsed fields. | L/S/A | M |
| DE06 | Calendar invitation preview | Parse text/calendar attachments into an event preview; implement RSVP MIME/provider behavior as a separately verified step. | L/P/S | L |
| DE07 | Meeting links panel | Extract meeting URLs from a conversation; display host/domain and avoid automatic connection or URL fetching. | L | S |
| DE08 | One-time code copy | Recognise likely codes in opened messages; provide explicit Copy with no automatic use or persistent extra code store. | L | M |
| DE09 | PDF invoice collection | Add a saved attachment filter for likely invoices with original-message links; make classification editable. | L | M |
| DE10 | Purchase reference view | Group related receipts/order/shipping mail using explicit order IDs plus account; avoid subject-only merging. | L/A | L |

## 12. Privacy and security

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| PR01 | Face ID / app lock | Use LocalAuthentication and a lifecycle lock policy; obscure the app-switcher snapshot and offer system passcode fallback. | L/S | M |
| PR02 | Private notification previews | Default to generic account/new-mail text; let users opt into subject/sender and hide content while locked where supported. | L/B/S | M |
| PR03 | Tracker inspection | Explain blocked remote resources and known pixel patterns locally; keep remote images off by default and label heuristics accurately. | L | M |
| PR04 | Image privacy proxy | Build a hardened proxy with no user-identifying upstream requests, SSRF protection, bounded downloads, and defined retention. | B | XL |
| PR05 | Link destination preview | Show actual host alongside visible link text; warn on suspicious mismatch without fetching the destination automatically. | L | M |
| PR06 | Tracking-parameter cleanup | Remove only recognised optional tracking parameters; preview the cleaned URL and preserve signed/authentication links. | L | M |
| PR07 | Sender identity details | Expose From/Reply-To and provider-supplied authentication data; do not equate domain icons or raw untrusted headers with verification. | L/P | L |
| PR08 | Account data controls | Provide remove-account, clear-downloads, and clear-local-cache flows with exact consequences and protected draft handling. | L | M |
| PR09 | Identity masking integration | Connect to a provider's supported alias service; list/create/disable aliases only with appropriate authentication and capability checks. | P | L |
| PR10 | Secure expiring message links | Separate hosted encrypted content from ordinary email; require recipient authentication, expiry/revocation, and independent security review. | B/P | XL |

## 13. Optional AI assistance

AI must be user-controlled. Use on-device models when available, explain cloud processing before sending mail content, and preserve a complete non-AI mail experience.

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| AI01 | Thread summary | Summarise selected cached messages; cite message/date references, show incomplete coverage, and invalidate summaries after new replies. | L/A | L |
| AI02 | Rewrite selected draft text | Offer Shorter, Clearer, and Tone options; present a diff/preview and replace only after acceptance. | L/A | M |
| AI03 | Reply suggestions | Generate several editable drafts from the selected conversation; preserve quoted facts and keep sending explicit. | L/A | L |
| AI04 | Translation | Translate selected text with a visible original and language selector; distinguish model translation from original content. | L/S/A | M |
| AI05 | Action-item extraction | Propose tasks with source text and tentative dates/owners; require acceptance before creating records. | L/A | L |
| AI06 | Ask about selected mail | Restrict retrieval to user-selected accounts/messages; return source links and abstain when evidence is missing. | L/A | L |
| AI07 | Optional automatic labels | Start with suggestions and user corrections; make every classification explainable and keep provider mutations a separate opt-in. | L/A/P | L |
| AI08 | On-demand inbox briefing | Summarise a chosen time range/filter; exclude Spam/Trash by default and show which cached messages were considered. | L/A | L |
| AI09 | Recipient/context checks | Suggest possible wrong-recipient or missing-context issues; keep warnings dismissible and avoid unsupported certainty. | L/A | L |
| AI10 | Personal writing preferences | Use explicit examples/preferences rather than silently reading all Sent mail; offer reset/export and isolate data by account. | L/A | L |

## 14. Notifications and attention

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| NO01 | New-mail push foundation | Register devices and APNs tokens; connect provider changes to backend fan-out, then let the app reconcile its history cursor. | P/B/S | XL |
| NO02 | VIP-only notifications | Apply explicit sender rules to new-mail events; sync preferences to the backend if filtering occurs while the app is closed. | L/B/S | M |
| NO03 | Per-account notification controls | Separate enablement, preview content, sound, and badge scope; show when OS permission prevents delivery. | L/B/S | M |
| NO04 | Quiet hours | Store timezone-aware windows and override preferences; suppress backend/local alerts while continuing permitted sync. | L/B/S | M |
| NO05 | Digest notifications | Aggregate new-mail IDs into a short count-based alert; avoid persisting message bodies in the notification service unnecessarily. | B/S | L |
| NO06 | Notification actions | Register archive/read/reply categories; verify account/message identity, queue changes durably, and protect inline replies from duplicate sends. | L/P/B/S | L |
| NO07 | Badge policy | Offer unread-all, selected accounts, VIP, or off; document cached versus backend-authoritative counts. | L/B/S | M |
| NO08 | Follow-up notifications | Schedule local notifications for explicit reminders; cancel them after qualifying replies are synced and handle stale alerts. | L/S | M |
| NO09 | Focus filters | Expose account/workspace filters through App Intents; maintain a visible active filter and easy return to all accounts. | L/S | M |
| NO10 | Notification health screen | Show permission status, token registration, last provider signal, and safe retry controls without exposing secrets. | L/B/S | M |

## 15. Offline, sync, and reliability

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| SY01 | Opportunistic background refresh | Register BGAppRefreshTask, cancel on expiry, checkpoint history safely, and retain foreground/pull sync fallbacks. | L/P/S | L |
| SY02 | Failed-actions centre | List account-scoped queue items with attempt/error state; support retry or cancel and isolate permanently failing operations. | L/P | L |
| SY03 | Queue compaction | Coalesce redundant read/star/label operations without crossing delete/send boundaries; test net-state equivalence and ordering. | L | L |
| SY04 | Sync conflict handling | Keep optimistic overlays until acknowledged; reconcile changed provider labels with recorded intent and expose unrecoverable conflicts. | L/P | L |
| SY05 | Download coverage settings | Let users choose recent days/mailboxes and file limits; show estimates and never evict unsent drafts. | L/P | L |
| SY06 | Download for offline trip | Explicitly cache a selected mailbox/project plus chosen files; show progress, disk estimate, and availability after completion. | L/P | L |
| SY07 | Data-saver mode | Defer files/icons and nonessential prefetch on expensive/constrained connections; keep manual downloads available. | L/S | M |
| SY08 | Cache eviction budget | Evict least-recently-used downloaded files and reproducible bodies under a configured cap; preserve drafts, queue intent, and message metadata. | L | L |
| SY09 | Scoped refresh controls | Refresh selected account/mailbox rather than always all accounts; coalesce concurrent requests and retain independent failures. | L/P | M |
| SY10 | Safe diagnostic export | Export version, timings, counts, and redacted errors; exclude tokens, mail bodies, addresses, and query contents by default. | L/S | M |

## 16. Providers and sending identities

These are separate provider projects. A provider name in this section is a proposed integration, not a statement that a compatible mobile API is already available.

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| PV01 | Provider capability layer | Define sync/read/compose/draft/attachment/label capabilities behind adapters; retain Gmail-specific logic where semantics differ. | L/P | L |
| PV02 | Zoho Mail support | Implement data-centre-aware OAuth, account discovery, folders/messages/drafts/files; verify pagination, threading, and push capabilities independently. | P | XL |
| PV03 | Outlook/Microsoft 365 support | Research Graph delegated permissions and tenant consent; implement delta sync, MIME sending, folders, and refresh-token lifecycle. | P | XL |
| PV04 | Fastmail JMAP support | Use session discovery, capability negotiation, state-based changes, blob transfer, and submission rather than translating Gmail labels literally. | P | XL |
| PV05 | iCloud/custom IMAP feasibility | Prototype a standards client plus SMTP submission; validate authentication, app-password needs, TLS, IDLE, and background limitations. | P | XL |
| PV06 | Unified cross-provider inbox | Combine account-scoped view models; keep folder/label terminology and action availability faithful to each provider. | L/P | L |
| PV07 | Multiple sender identities | Store verified From/reply-to/display-name/signature combinations; associate each with an account capability and validation policy. | L/P | L |
| PV08 | Guided reconnect | Target the selected account where OAuth supports a login hint; reject accidental identity replacement and preserve cached mail. | P/L | M |
| PV09 | Shared/delegated mailboxes | Research provider-specific delegation and access models; implement explicit account ownership and permission-limited actions. | P/B | XL |
| PV10 | Provider capability explanations | Show why a feature is unavailable and any supported alternative; avoid inert controls or false parity promises. | L | S |

## 17. System integrations and collaboration

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| EX01 | Reminders export | Create a reminder from selected mail through EventKit after permission; include a durable Dispatch link back to the conversation. | L/S | M |
| EX02 | Calendar event creation | Fill a native event editor from user-selected details; confirm date/timezone and do not write automatically. | L/S | M |
| EX03 | Share availability | Read authorised calendar free/busy ranges locally; insert reviewed time slots with timezone and no private event titles. | L/S | L |
| EX04 | Share extension for composing | Accept text/URLs/files from other apps; persist imports in an App Group handoff and open a draft without sending. | L/S | L |
| EX05 | App Intents and Shortcuts | Expose compose, open mailbox, and create follow-up intents; make destructive/sending actions explicitly interactive. | L/S | L |
| EX06 | Widgets | Show selected-account unread counts or due follow-ups from a redacted shared snapshot; open the app for richer content. | L/S | M |
| EX07 | Spotlight indexing | Index opt-in cached metadata with account-scoped identifiers; delete entries on removal and avoid body indexing by default. | L/S | M |
| EX08 | Internal mail deep links | Route opaque account/thread/message IDs through a resolver; fail safely for removed accounts and never put credentials/content in URLs. | L | M |
| EX09 | Shared threads and private team comments | Build authenticated workspace membership, scoped copies/references, audit history, revocation, and a clear boundary between comments and email. | B/P | XL |
| EX10 | Collaborative drafts and assignment | Add backend versioning, edit-conflict resolution, roles, and one submission authority; prevent two teammates sending the same draft. | B/P | XL |

## 18. Accessibility, polish, and power use

| ID | Feature / user benefit | First implementation | Route | Size |
| --- | --- | --- | --- | --- |
| UX01 | Dynamic Type layout completion | Test every inbox/reader/composer state at accessibility sizes; wrap controls and use meaningful minimum touch targets. | L | M |
| UX02 | VoiceOver navigation | Manage drawer/sheet focus, announce selection/download/save changes, and provide concise row/action descriptions. | L/S | M |
| UX03 | Keyboard shortcuts | Add compose/search/reply/archive/navigation commands on iPad/external keyboards; support discoverable system shortcut presentation. | L/S | M |
| UX04 | Command palette | Build an optional searchable action registry; filter by current account/view capabilities and reuse action handlers. | L | M |
| UX05 | Drag and drop | Support dragging files into drafts and moving selected mail into local collections/labels with clear drop previews. | L/P/S | L |
| UX06 | Multiple windows | Open another mailbox/conversation/draft scene on iPad; guard duplicate draft editing and send ownership. | L/S | L |
| UX07 | Density and preview settings | Extend existing preview-line preferences with comfortable/compact row spacing and optional sender icons; honour Dynamic Type. | L | S |
| UX08 | RTL and localisation | Move strings into catalogues, test long translations/RTL, and localise dates/counts without translating provider identifiers. | L | L |
| UX09 | Contextual onboarding | Introduce features only when used; preserve sample mode and avoid a long mandatory tour before viewing mail. | L | S |
| UX10 | Large-mailbox performance | Move filtering/pagination into repository queries, instrument scroll/search latency, and limit simultaneous HTML readers. | L | L |

## Recommended implementation sequence

Ship complete, reviewable slices. Features sharing data foundations should be grouped, but successful validation of one slice should not be mistaken for validation of the next.

| Wave | Scope | IDs | Exit criteria |
| --- | --- | --- | --- |
| 0 — Finish active work | Received files and unified drafts | AT01, SD01 | CI passes; downloads survive resync/relaunch; account removal clears files; local and server draft actions remain distinct. |
| 1 — Everyday completeness | Compose files, signatures/default sender, validation, Spam, counts and indicators | AT02–03, CO03–05, TR06, IN02–04 | A real daily mail workflow needs no avoidable switch to Gmail; no draft/content loss; signed-device checks pass. |
| 2 — Calm inbox and reader | Conversations, collapse, recipient sheet, reply toolbar, bulk selection and Undo | IN01, RE01–04, TR01–02, TR08 | Actions stay predictable across account/filter changes; long threads and large text remain usable. |
| 3 — Reliability and finding mail | Failed queue recovery, scoped/background refresh, filters/operators/body search, coverage | SY01–04, SY09, SE01–05, UX10 | Permanent operation failure does not block fresh mail; offline/search coverage is honest; index/update performance is measured. |
| 4 — Dispatch's distinctive workflow | Follow-up list, Later, waiting-for-reply, snippets, subscriptions | FU01–04, FU10, CO06, NL01–03, OR03–05 | Clear task states, useful defaults, and no permanent UI clutter; scheduled local work catches up on foreground. |
| 5 — Native power and privacy | iPad, keyboard, app lock, deep links, Reminders, widgets, accessibility | IN08, UX01–04, PR01, EX01, EX06, EX08 | iPhone/iPad and VoiceOver checks pass; private content stays out of unintended surfaces. |
| 6 — Provider expansion | Capability layer then Zoho; evaluate Graph/JMAP separately | PV01–04, PV06, PV08, PV10 | Adapter contract tests, real provider fixtures, migration/account-isolation tests, and provider-specific device verification. |
| 7 — Explicit service choices | Push, reliable scheduled send, optional AI; collaboration only if wanted | NO01–10, SD06, AI01–06, EX09–10 | Backend ownership/cost/privacy choices are agreed; cancellation/recovery and permission boundaries are tested. |

**Best next ten after the active branch:** AT02, CO04, CO05, CO03, TR06, IN01, RE01, TR01, TR02, SY02. Counts/indicators are small useful companions. I would prioritise these before implementing AI or a full calendar inside the mail app.

## Implementation foundations

### Keep account and provider identities explicit

Use UUID account IDs plus opaque provider message/thread/draft IDs throughout storage and actions. Never merge threads or drafts solely because subjects match. Use a provider capability contract so unsupported actions are omitted or explained. Mail folder semantics and threading differ across providers.

### Add persistent features through real schema migrations

Dispatch currently uses SwiftData schema V1 and an explicit migration plan. Freeze the old schema representation before introducing V2 models; do not mutate V1 definitions and call that a migration. Test reopening an actual V1 database after upgrade.

Likely new records include `SavedView`, `SenderPreference`, `FollowUp`, `LocalCollection`, `ComposerAttachment`, `DraftRevision`, `AccountPreferences`, and eventually `ScheduledSubmission`. Small compatibility metadata can remain in StoreMetadata, but substantial queryable state deserves typed models with versioned schemas.

### Reuse durable operations instead of bypassing them

Views request actions through a service/coordinator. Provider mutations become persisted intent with account, target, operation, ordering, retry classification, and completion state. Incoming sync must preserve pending overlays. Batch operations need a fixed selection snapshot and individual outcomes. Sending remains a separate state machine because replaying an ambiguous submission can duplicate email.

### Separate local preferences from provider state

Pins, collections, personal notes, custom views, and Reply Later can start locally. Labels, read state, server drafts, and server rules affect the provider. Tell users which changes stay in Dispatch and which appear in other mail apps. Cross-device synchronisation of local features is its own project, not an automatic benefit of Gmail sync.

### Share a typed search expression

Filter chips, search operators, smart folders, command shortcuts, and optional AI query translation should all produce one validated expression tree. Evaluate it locally where supported; translate only supported nodes into provider queries. Label scope and data coverage explicitly. Never claim cached search covers undownloaded mail.

### Keep heavy work away from the main actor

SwiftData model access remains in the main-actor repository. Transfer immutable DTOs to indexing, MIME parsing, file handling, extraction, and AI tasks. Cancel outdated searches/downloads and bound work by message/file/page counts. Prefer incremental indexes over rebuilding every cached body after a small sync.

## Detailed implementation notes for the highest-impact features

### Conversation rows and reader collapsing — IN01, RE01–04

1. Build a repository projection keyed by account ID and remote thread ID, with latest message, participants, count, unread count, labels, and attachment presence.
2. Define which message opens initially: explicit search result first, otherwise earliest unread or latest message.
3. Keep selected-message actions distinct from whole-conversation actions. Compute the latter from a stable ID snapshot and explain the scope.
4. Collapse historical bodies and quoted content; instantiate WebKit only for visible expanded messages.
5. Test same thread IDs across accounts, deleted messages, mixed read states, drafts in a thread, and deep links to older messages.

### Compose files without losing drafts — AT02–05, SD09

1. Add durable draft attachment references through a migration. Record generated file ID, protected relative path, original display filename, MIME type, size, and optional content ID.
2. Import from security-scoped URLs into app-owned storage before checkpointing a draft. Copy on a worker actor and protect writes atomically.
3. Build multipart/mixed with multipart/alternative when rich text is supported; base64-encode files and escape/fold filename headers correctly. Calculate encoded size, not only raw size.
4. Keep remote IDs separate from usable local bytes. A forward/send needs actual content or a verified provider-native mechanism.
5. Preserve files needed by current drafts, discard restoration, revision history, queued sends, and unconfirmed sends. Delete only when no durable owner remains.
6. Test crash during import, discard after adding/removing a file, relaunch, expired security access, Unicode filenames, account switching, unsupported imported MIME, and ambiguous sending.

### Undo actions and bulk selection — TR01–02

1. Snapshot selected account/message IDs and the exact previous label state before changing the cache.
2. Persist an undo record alongside the operations. If the operation has not been submitted, cancel it; if acknowledged, enqueue a compensating change.
3. Restore only fields changed by the action so Undo does not erase unrelated incoming provider changes.
4. Report partially failed batches and permit retry of failed items without repeating successful ones.
5. Test undo before/during/after a provider request, app termination, selection across accounts, and Trash/Inbox state combinations.

### Snooze and conditional follow-up — FU01–04

1. Add a `FollowUp` record with account/thread, anchor message, mode, due date, timezone/display preferences, and state.
2. Start with local visibility: a Later view and foreground due-item reconciliation. Optional local notifications provide a reminder without requiring inbox mutation.
3. If users want provider-visible snooze, define label/archive semantics explicitly and persist compensating operations. Do not imply parity with Gmail's native snooze.
4. For no-reply reminders, identify a new incoming reply after the tracked send; exclude own identities, bounces, and auto-replies where detectable. Expose ambiguous cases rather than silently cancelling.
5. Test offline replies arriving late, timezone/DST changes, a changed device clock, removed accounts, and repeated resnoozing.

### Queued send, Undo Send, and scheduled send — SD05–08

Use explicit states such as `draft`, `queued`, `scheduled`, `submitting`, `sent`, `rejected`, and `unconfirmed`. Exact names can follow the current models, but transitions must be durable.

- **Undo Send** is a pre-submission cancellation window; it cannot recall an email already accepted by the provider. Persist the due time and preserve local content until submission ownership is settled.
- **Offline sending** should visibly queue mail. Any ambiguous POST becomes unconfirmed and requires reconciliation, preserving Dispatch's existing protection.
- **Precise scheduled sending while the app is closed** requires a supported server-side mechanism or a backend. An iOS refresh request does not guarantee execution at a selected time. [Apple's scheduling constraint](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate).
- A backend scheduler needs encrypted authorised credentials, job ownership/leases, cancellation before submission, account revocation, stable Message-ID, and reconciliation after an unknown result. It must never race a device sender. Gmail offers no general submission idempotency key to assume here.

The documented Gmail REST surface contains send/draft operations but no general native scheduled-send or snooze method. **Planning inference:** implement these as Dispatch features or verified provider-specific capabilities, rather than assuming Gmail UI features are callable APIs. Recheck the API before implementation. [Gmail REST reference](https://developers.google.com/workspace/gmail/api/reference/rest).

### Search expansion — SE01–10

Extend `MailSearchDocument` with typed metadata and a content digest. Use incremental add/update/delete operations, with cancellation on obsolete builds. Body indexing needs a disk/memory budget; a separately managed local full-text index is an option if benchmarks justify it, rather than forcing all text into the current trigram structure. OCR and embeddings should be optional later indexes with explicit retention and removal.

Provider search is an explicit extension, not a hidden network call per keystroke. Keep online result cursors account/filter-specific, merge by identity, and preserve the exact message selected from a conversation. Test operator escaping, Unicode/diacritics, cache removal, online failures, and incomplete coverage.

### Newsletter controls and unsubscribe — NL01–04

Cache the relevant mailing-list headers in a versioned representation. Prefer a list ID over a display name for grouping. Treat header URLs as untrusted; show the destination and user action before sending an unsubscribe request. Standards support, redirects, mailto handlers, phishing messages, and provider API availability need verification. A local quiet/reading rule is a useful fallback when no safe unsubscribe mechanism exists.

### Push and background refresh — NO01, SY01

Background refresh is opportunistic. Schedule the next request after each run, honour expiration cancellation, and never advance the history cursor before a complete successful batch.

For Gmail push, mailbox changes go through Cloud Pub/Sub to a backend, not directly to APNs. Renew watches before expiry; Google requires renewal at least every seven days and recommends daily renewal. Treat notifications as sync signals because events can be delayed or dropped, and retain reconciliation/polling fallbacks. Choose whether the backend receives only change signals or also fetches mail to construct previews; the latter changes its credential/data responsibilities. [Google's push guide](https://developers.google.com/workspace/gmail/api/guides/push).

### AI that remains optional — AI01–10

Introduce an `AIService` contract with availability, cancellation, structured output, and source references. An on-device adapter can use Foundation Models when the model/device/language capabilities are available; support a disabled/unavailable state and avoid assuming every iOS 26 device can run it. Cloud processing needs a separate explicit setting, data-retention policy, and credentials/service design. [Apple's model availability guidance](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models).

Email content is untrusted input. It must not override application instructions or authorise sending, deleting, opening arbitrary URLs, or reading other accounts. Generate reviewable suggestions. Use source-backed summaries, output validation, and a fixture set with hallucination/prompt-injection examples. An AI summary is never a replacement for the original mail.

## Choices to make before larger service features

| Choice | Default recommendation | Why it matters |
| --- | --- | --- |
| New organisation features | Local first, with clear labels | Useful functionality without storing another server-side copy of mail. |
| Search | Instant cached results plus explicit online extension | Keeps latency and data coverage understandable. |
| AI | Optional; on-device first where suitable | Preserves the normal app and limits unnecessary content transmission. |
| Snooze | Local Later view first | Avoids pretending local scheduling is provider-native snooze. |
| Precise scheduled send | Defer until backend ownership is decided | Submission timing and duplicate prevention need a reliable authority. |
| Cross-device local state | Separate encrypted sync design | Provider sync does not transport Dispatch notes, pins, tasks, or local rules. |
| Read receipts | Defer; if added, opt-in with accurate wording | Image proxies/blocking can produce false/missing opens; an open event is not proof of reading. |
| Shared inbox/collaboration | Separate later product track | Requires authorisation, sharing/revocation, concurrency, and sending ownership. |
| Secure expiring messages | Separate service plus security review | Expiry can revoke hosted access, but cannot erase copies/screenshots already taken. |

## Validation and rollout

For each selected feature, write a short acceptance checklist and test failure cases that can lose mail, duplicate sends, leak account data, or confuse action scope. Avoid tests that merely duplicate presentation code.

- **Storage:** real V1-to-new-schema migration, reopening, account isolation/removal, disk-full/corruption behavior, and preservation of protected outgoing states.
- **Provider:** paginated fixtures, expired tokens/cursors, rate limits, partial batches, removed messages, offline transitions, and ambiguous write outcomes. Tests must not send personal mail.
- **UI:** connected-account fixtures as well as samples; VoiceOver, large text, light/dark, keyboard, iPhone landscape, and iPad navigation.
- **Performance:** large caches, long threads, huge HTML, many attachment rows, incremental search updates, and cancellation under repeated sync.
- **Device:** signed-device OAuth and real delivery/draft/file workflows after CI; notification and background behavior on hardware.
- **Release:** feature flags for new provider/backend/AI tracks; staged adoption and a rollback path that preserves stored data.

## Technical references for implementation

These sources establish starting points, not permission to assume every operation is supported with current OAuth scopes. Verify scopes, account restrictions, and platform availability when turning an idea into work.

- [Gmail send-as identities](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs) — sender aliases require provider-backed identities, not arbitrary From text.
- [Gmail filters](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.filters) — server-side filtering is a settings capability with its own permissions.
- [Apple background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) — select refresh, processing, or transfer work based on the actual task.
- [Fastmail API documentation](https://www.fastmail.com/dev/) — JMAP session discovery and provider extensions.
- [Zoho API getting started](https://www.zoho.com/mail/help/api/getting-started-with-api.html), [Zoho OAuth](https://www.zoho.com/mail/help/api/using-oauth-2.html) — authentication and data-centre-aware integration.

## Turning this document into work

Pick a small wave and convert each selected ID into an implementation issue with: user outcome, exact scope, affected components, data migration, provider/permission dependencies, acceptance cases, and validation evidence. Re-check the active branch before classifying an idea as missing. Keep this backlog broad, and keep the shipped interface restrained.
