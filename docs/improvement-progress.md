# Audit implementation progress

## Batch 1 — Local search

Implemented native cached-mail search, account filtering, explicit Trash/Spam inclusion, an off-main-actor substring index, and sample/no-results states.

[First macOS CI run](https://github.com/pphilfre/mail/actions/runs/37212517327): app and test bundles compiled; all 36 unit tests passed. Three UI tests passed; the new search test queried the entire application and matched underlying inbox content. Its assertions now target the search list and result identifiers. Full CI is being rerun with Batch 2; search is not yet marked fully verified.

## Batch 2 — Draft safety, pagination, and inbox cleanup

- Draft edits checkpoint locally after 600 ms of inactivity and when the app leaves the foreground. Discard removes a new draft or restores the original saved draft.
- Draft saves reload current persisted draft state, preserving provider imports and preventing stale editors from reviving sent/unconfirmed messages.
- Existing Gmail drafts with HTML, attachments, or external bodies cannot be overwritten by the text composer. They remain editable in Gmail. Deletion has an independent confirmed action.
- Each account/mailbox/label has a durable pagination cursor using existing metadata storage. All Mail cursors remain compatible with previous versions.
- Inbox errors appear in one compact disclosure with retry/account actions. Unconfirmed sends open a dedicated recovery view instead of displaying bodies in the inbox.
- The active account appears below the mailbox title. Today’s mail shows the time; older mail shows a concise date. Sample previews respect Settings.
- Connected-account composing puts Send in the top bar and uses shorter helper text.

Added draft discard/persistence, stale-session, rich-draft protection, mailbox pagination, account cleanup, and send-confirmation tests plus an autosave relaunch UI test. macOS validation is pending. No schema version change, release, or merge has been performed.

## Still to implement

General attachment transfer; unified draft navigation; network-return/background sync; permanent queued-operation recovery; conversation rows; counts; bulk actions/Undo; recipient autocomplete and validation; signatures/default accounts; reader collapsing and scoped errors; adaptive iPad layout; later Zoho and push stages. Device visual/accessibility checks and live signed-device Gmail verification remain outstanding.

The [audit](ui-feature-audit.md) records the original findings. This page tracks implementation and verification separately.
