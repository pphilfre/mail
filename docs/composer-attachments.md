# Dispatch v0.5.0 — compose and forward attachments

Audited on 5 October 2026 against the released v0.4.0 source. The earlier everyday feature wave already supplies conversation rows, bulk actions/Undo, Spam, cached mailbox counts, account preferences/signatures, recipient assistance and saved/operator searches. The largest remaining everyday gap was sending files.

## Implemented

- Files picker and system Photos picker in the composer, with attachment names, sizes, Quick Look preview and removal.
- Up to 20 files and 20 MB of original attachment data per message. Encoded MIME is bounded to 28 MB, leaving space for encoding overhead. Larger files require a smaller copy or a sharing link; no automatic Drive upload.
- Protected copies in Application Support, independent of temporary file-picker access. Work and MIME encoding run on a file-store actor. Drafts reopen with attachment manifests and discarded edits restore the original attachment list.
- Multipart/mixed Gmail sending and server draft uploads, base64 bodies/binary parts and RFC 2231 Unicode filename continuations. Missing or changed originals prevent sending; attachments cannot be silently omitted.
- Gmail draft acknowledgements record the immutable provider message ID separately from refreshed mailbox links. Dispatch can update its own attachment drafts only while that revision still matches. Edits elsewhere block replacement; arbitrary rich/attachment drafts still remain in Gmail. Gmail does not expose an atomic compare-and-swap draft update, so a simultaneous edit between the check and update remains a provider limitation.
- Forward with attachments or Forward text only. File copies must all succeed before the new composer opens. Replies keep the existing text quoting behavior.
- Draft-list attachment counts, attachment-aware missing-file reminder, and previews in retained uncertain-send copies.
- Existing SwiftData V1 is unchanged: manifests and revision acknowledgements use StoreMetadata. Legacy JSON drafts decode with an empty attachment list. Deleting a local draft/account clears its metadata. Unreferenced draft directories are pruned after a 24-hour grace period on a later launch; retained outgoing copies keep their files.

## Verification

New unit tests cover protected file reopening, durable manifests, discard, legacy import, attachment-only drafts, exact binary and Unicode MIME data, injection resistance, size/count limits, missing/corrupted originals, revision isolation and attachment draft upload/re-upload. A UI fixture covers reopening a persisted attachment and removal across relaunch. CI additionally parses Swift's emitted MIME with Python's independent RFC email parser.

The full simulator build, unit/UI suite, and device IPA build run on macOS GitHub Actions. Validation is pending until the release branch's CI passes. CI uses fixtures; live photo/file-provider imports, forwarding, Gmail delivery and installation require an installed signed build.

## Remaining gaps

The next useful independent areas are reusable reply templates, label creation/rename, VIP/pinned conversations and adaptive iPad navigation. Background refresh and push need separate system/provisioning work; Zoho needs a provider implementation. Rich text, arbitrary remote attachment draft import and large-file cloud sharing remain outside this release.

Provider evidence: [Gmail draft IDs and immutable messages](https://developers.google.com/workspace/gmail/api/guides/drafts), [Gmail MIME sending](https://developers.google.com/workspace/gmail/api/guides/sending). Picker evidence: [Apple file importer](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)), [Photos picker items](https://developer.apple.com/documentation/photosui/photospickeritem).
