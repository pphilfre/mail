# Stage ledger

The brief requires implementation, build/test, fixes and documentation at each stage before starting the next. Workflows for Stage 2 are bootstrapped with Stage 1 because Windows cannot run the iOS compiler.

| Stage | Status | Evidence / next gate |
| --- | --- | --- |
| 1 — Foundation | Complete | [macOS CI passed](https://github.com/pphilfre/mail/actions/runs/37123967712): simulator build, 4 unit tests and 3 UI tests. |
| 2 — Windows / Actions | Complete | [Dispatch release passed](https://github.com/pphilfre/mail/actions/runs/37125945882), including device build, IPA packaging and upload. |
| 3 — SwiftData | Complete | [Storage CI passed](https://github.com/pphilfre/mail/actions/runs/37127210621), including actual simulator Keychain access. |
| 4 — Gmail | Implemented and CI verified; live device check pending | [CI passed](https://github.com/pphilfre/mail/actions/runs/37130336912): simulator build, 26 unit tests and 3 UI tests. OAuth console/provisioning and actual delivery need the device checklist. |
| 5 — Zoho | Not started | OAuth client and data centre; verify official provider capabilities. |
| 6 — Unified inbox | Gmail subset implemented | Multiple Gmail accounts, account/mailbox/label filtering and native swipe actions. Zoho unification remains deferred. |
| 7 — Reader / compose | Gmail text subset implemented | Cached threads, safe HTML-to-text, replies/forwarding, MIME sending and local/server drafts. Rich HTML and attachment transfer remain. |
| 8 — Search | Not started | Indexed local search without per-keystroke provider requests. |
| 9 — Offline sync | Gmail subset implemented | Durable optimistic queue, launch/foreground/pull retries and protected uncertain sends. Network-return and background scheduling remain. |
| 10 — Notification backend | Not started | Deployment choice and current official Zoho capability research. |
| 11 — APNs | Not started | Apple signing, provisioning, backend device registration. |
| 12 — Polish | Not started | All functional gates must pass first. |

## Design decisions

System SF typography, semantic system backgrounds/text colours, iOS accent blue, standard 16–20 point spacing, and native navigation/list/form/tab controls. The inbox is left-aligned with sender/date, subject and two-line preview; native bars supply Liquid Glass without translucent message content. Dynamic Type, text selection and VoiceOver read-state labels are included at the foundation.

## Validation boundaries

Windows can inspect source and validate workflow/manifest syntax. It cannot compile SwiftUI or run an iOS simulator. Neither static checking nor a submitted workflow counts as a successful build. Record the actual CI URL and conclusion here after the first macOS run.

- [Initial run](https://github.com/pphilfre/mail/actions/runs/37123680169): project generation passed; build could not start because Xcode 26.0.1's iOS platform is absent from the current runner. Pin updated to Xcode 26.6 and stderr included in build logs.
- [Foundation verification](https://github.com/pphilfre/mail/actions/runs/37123967712): Xcode 26.6, XcodeGen 2.46.0, simulator build and all seven tests passed. Tag `v0.1.0` points to verified commit `4052df2`.
- App renamed to **Dispatch**, with bundle identifier **`dev.freddiephilpot.dispatch`**, after the original foundation tag. Project, target, scheme, test module and IPA names updated together; rename requires a new CI run. The original tag remains historical.
- [Release verification](https://github.com/pphilfre/mail/actions/runs/37124654886): all build/test/package/upload steps passed and the original foundation IPA was attached to [v0.1.0](https://github.com/pphilfre/mail/releases/tag/v0.1.0). This historical version uses the original Mail name and identifier. Current work uses Dispatch.
- [Dispatch verification](https://github.com/pphilfre/mail/actions/runs/37124979822): renamed project, module, app and test targets build successfully; all seven tests pass. `v0.1.1` is the Dispatch foundation tag. Swift module is `DispatchMail` to avoid Apple's system `Dispatch` module.

## Stage 3 implementation

- SwiftData schema V1 has account-scoped identities and external body blobs, plus pending-operation and outgoing-message records. Future schema changes use an explicit migration plan.
- Model access is confined to a main-actor repository. Provider actors will transfer value DTOs, not SwiftData objects.
- Draft writes and account-data deletion are transactional. A persistent import marker prevents deleted legacy drafts from reappearing.
- Keychain items use `AfterFirstUnlockThisDeviceOnly`, with no synchronisation or shared access group. Actual vault round-trip/rotation/isolation tests run on the simulator.
- Tests cover database reopening, bodies/recipients/attachment metadata, account isolation and cleanup, successful and corrupt draft migration, and persisted composer edits.
- [First Stage 3 run](https://github.com/pphilfre/mail/actions/runs/37126136774): compiler, SwiftData tests and UI tests passed; live Keychain tests exposed `errSecMissingEntitlement` in the unsigned simulator app. Simulator-only ad-hoc signing and explicit test entitlements added, with built signing metadata captured in CI logs. Device signing is unaffected.
- [Stage 3 passed](https://github.com/pphilfre/mail/actions/runs/37127210621): simulator build and all 15 tests, including live Keychain round-trip and account isolation.

## Stage 4 implementation

- Public Google iOS client and reverse-client callback are included through XcodeGen. Native browser OAuth checks state and uses PKCE S256; tokens remain in device-only Keychain.
- Gmail REST runs behind a transport protocol with Sendable DTOs. Views read SwiftData, and history sync commits its cursor only after the last successful page. Expired history IDs trigger reconciliation of cached mail.
- Read/star/archive/trash/restore and custom-label changes are durable optimistic operations. Local drafts, Gmail drafts, text MIME sending, replies, reply-all and text forwarding are implemented. Interrupted or uncertain sends remain protected from automatic resend.
- Initial All Mail/Inbox fetch and mailbox selection cache recent mail; older All Mail pages load on demand. Rich HTML and attachment transfer remain Stage 7. Zoho and push are deferred at the user's request.
- [First Gmail test run](https://github.com/pphilfre/mail/actions/runs/37129179809): app compiled; 23 of 24 unit tests and all three UI tests passed. A header-injection test found Swift's CRLF grapheme handling could bypass character checks. Scalar-based control-character validation replaces those checks; the full suite must pass before release.
- Real Google consent and email delivery require the signed device smoke test in [OAuth setup](oauth-setup.md); CI never logs into a personal account or sends real mail.
- [Gmail validation passed](https://github.com/pphilfre/mail/actions/runs/37130336912) for commit `3e48f59`: simulator build, all 26 unit tests (including 14 Gmail tests) and all three UI tests. Header control characters, Unicode MIME folding, history pagination/failure recovery, expired cursors, draft-create uncertainty and reply recipient handling are covered. Tag `v0.2.0` points to this exact verified commit.
- [Gmail release passed](https://github.com/pphilfre/mail/actions/runs/37131447707): exact-commit CI gate, physical-device build, unsigned IPA packaging and release upload. [Dispatch v0.2.0](https://github.com/pphilfre/mail/releases/tag/v0.2.0) contains the IPA and SHA-256 checksum. Live OAuth and mail delivery remain the device verification boundary.
