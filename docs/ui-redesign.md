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

Triage confirmations follow a committed durable undo record, with a bounded Undo deadline. Unexpired Undo is offered after relaunch. Automatic read marking does not celebrate. Saving a draft and confirmed provider send/save operations show completion feedback; uncertain sending directs the user to Outbox. Haptics use [SwiftUI sensory feedback](https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)). Physical-device testing is required to judge the feel.

Server cooldowns display “Waiting for Gmail” with a countdown in the inbox dock and account status. Routine request pacing stays quiet.

## Validation

UI tests cover mailbox-sheet dismissal, profile navigation, unread-filter behaviour, saved-draft confirmation and persistence, bulk Undo, recipient validation and the existing reader/search flows. Screenshot attachments cover the inbox, mailbox sheet, settings, reader, confirmation, and feature/recipient states.

Windows source review and `git diff --check` completed. A combined macOS/Xcode simulator build and test run is being coordinated with the feature and Gmail work; simulator screenshots and native haptic feel remain to be verified.
