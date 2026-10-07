# Dispatch UI redesign

The redesign takes the references' clear typography, light mail lists and compact controls into native SwiftUI. Liquid Glass sits on navigation and actions; messages remain readable paper surfaces. The old edge drawer is replaced with a system mailbox sheet, with a safe-area-aware close control and a consistent profile menu for Accounts and Settings.

## Design choices

- Native SF typography, a large mailbox heading, compact sender names, and restrained subject/preview hierarchy.
- Semantic grouped background and paper colours for light/dark appearance, blue `#2666EB` actions and green `#299E6E` success feedback.
- Small rounded sender marks, subtle unread dots, cached counts, and a floating compose control.
- Native scroll containers, sheets and glass controls. Filter selection uses a 220 ms snappy animation; confirmations use a short spring and five disappearing sparks.
- Dynamic Type, VoiceOver labels/announcements, minimum 44-point controls, Reduce Motion, and separate haptic/confirmation-animation preferences.

## Integrated behaviour

Conversation grouping, account scope, cached mailbox counts, local/remote drafts, bulk triage, Spam, pending-action recovery, search operators/filters/history/saved searches, recipient validation, account personalisation, signatures, and default sending-account fallback are retained.

Unread/Starred quick filters apply within the selected mailbox. Unread filters remain selected when returning from the reader. Changing filters or conversation grouping clears bulk selections.

Triage confirmations follow a committed durable undo record. Undo stays available until the ten-second deadline; ordinary confirmations dismiss after three seconds. Unexpired Undo is offered after relaunch. Automatic read marking stays quiet. Saving drafts and confirmed send operations show completion feedback; uncertain sending directs the user to Outbox. Native SwiftUI sensory feedback provides haptics. Physical device testing is required to judge their feel.

Server cooldowns display “Waiting for Gmail” with a countdown in the inbox dock and account status. Routine request pacing stays quiet.

## Validation

UI tests cover mailbox-sheet dismissal, profile navigation, unread-filter behaviour, saved-draft confirmation and persistence, bulk Undo, recipient validation and the existing reader/search flows. Screenshot attachments cover the inbox, mailbox sheet, settings, reader, confirmation, and feature/recipient states.

Windows source review and `git diff --check` completed. The [combined iOS simulator gate](https://github.com/pphilfre/mail/actions/runs/37234045937) compiled application source `6d8b12a` and passed all 78 unit tests and 14 UI tests, with no failures. The matching [PR gate](https://github.com/pphilfre/mail/actions/runs/37234049667) also passed.

Native iPhone 17e screenshots were reviewed for inbox density, initials contrast, mailbox counts, close-button placement, Settings hierarchy, confirmation placement and the complete reader body. One early reader capture preceded WebKit rendering; the matching successful PR run captured the full readable message. The [focused reader gate](https://github.com/pphilfre/mail/actions/runs/37235775228) on 743f2d9 then passed the added body-text assertion and exported a fully rendered reader screenshot. That commit changes test/CI support only; application source remains identical to the two successful complete gates.

Physical iPhone haptic feel, live-provider flows, dark appearance and the largest accessibility text sizes still need device QA; simulator success does not establish those results.
