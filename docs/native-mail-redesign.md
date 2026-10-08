# Native mail redesign

The redesign uses system colours, SF typography, restrained separators and glass on navigation and action controls. The supplied Zoho screenshots guide the reader, action sheet and composer; screenshots are visual references, not instructions to change account authentication.

## Implemented

- Inbox rows always show a 3pt stripe in their receiving account’s saved accent colour. Existing account switching, colour preferences, compact rows, preview settings, swipes, selection, filtering, haptics and Undo remain available. Per-render attachment and account lookup tables avoid repeated scans for every row.
- Reader preserves conversations, HTML sanitisation, external-image blocking and attachment previews. Account identity, expandable recipients, sender profile and an unknown-security icon accompany circular native navigation controls and a floating bottom toolbar.
- Scrollable native grouped action sheet includes reply/reply-all/forward, flag, tags, pin, snooze, unread, move, archive, delete/restore, contact creation, sender mail, spam, translation, print, PDF export, original EML forwarding, Dispatch task reminders, calendar event creation, collections, receipts and Security Inspector.
- Pin and snooze are durable **device-local** preferences scoped to the account and conversation. Snoozed messages remain accessible under More mailboxes → Snoozed and All Mail. They return to Inbox on expiry while the app is active or next opened; no push notification or server snooze is implied.
- Composer uses a flat native layout, account accent, circular navigation controls, account/signature/draft menu and floating photo/file/signature/text-tools dock above the keyboard. Existing validation, local checkpoints, provider drafts, attachment importing and uncertain-send handling remain intact.
- Security Inspector always starts at `?`. Authentication, impersonation, attachment safety and reputation are explicitly not analysed. Cached links, URL spelling observations, external-image presence and possible 1px trackers are labelled as observations, never safety verdicts. SHA-256 is calculated only for already downloaded files, off the main actor. **VirusTotal is a placeholder; no requests or scores.**
- Outlook and Zoho appear as informational account placeholders. No provider or credentials are created for either.

## Existing Gmail integration

This checkout already implemented OAuth through ASWebAuthenticationSession with state validation, PKCE, refresh coalescing and device-only Keychain tokens, as well as account-scoped sync, actions, MIME and draft storage. These components are reused. OAuth and Keychain implementation files were not changed. Live Google sign-in still requires the configured iOS client, Gmail API permissions and a signed device build.

## Deliberate limitations

Sender blocking, scheduled sending and rich text are visibly unavailable. Plain-text bullets/quotes work; the UI does not claim rich HTML sending. Translation uses Apple’s native translation presentation rather than an app AI service. Create Reminder opens the existing Dispatch task editor, not Apple Reminders. Contact and calendar editors only save when the person confirms in the native editor. Print/PDF use a readable text copy; original EML forwarding downloads the actual original message and attachments. Security authentication headers, redirect traversal, malware scanning and verified identity verdicts remain future work. Zoho awaits provider guidance; Outlook linking is not implemented.

## Verification

The existing `.github/workflows/ios-ci.yml` is the macOS/Xcode build and unit/UI test gate. New tests cover honest security observations and hashes, account-scoped pin/snooze persistence and removal, move/Undo semantics, original Gmail bytes, PDF generation and reader/action-sheet screenshots. Existing OAuth, Keychain, drafts, attachments, HTML, inbox and sender tests remain enabled. Device OAuth and iPhone 14 Pro Max performance require a signed-device check; simulator success cannot establish those results.
