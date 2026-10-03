# Stage ledger

The brief requires implementation, build/test, fixes and documentation at each stage before starting the next. Workflows for Stage 2 are bootstrapped with Stage 1 because Windows cannot run the iOS compiler.

| Stage | Status | Evidence / next gate |
| --- | --- | --- |
| 1 — Foundation | Complete | [macOS CI passed](https://github.com/pphilfre/mail/actions/runs/37123967712): simulator build, 4 unit tests and 3 UI tests. |
| 2 — Windows / Actions | Complete; Dispatch rename being revalidated | [Release workflow passed](https://github.com/pphilfre/mail/actions/runs/37124654886): tests, physical-device build, IPA packaging and GitHub Release upload. |
| 3 — SwiftData | Implemented, validation pending | Versioned local schema, one-time draft migration, repository transactions, device-only Keychain vault and tests. |
| 4 — Gmail | Next | Public OAuth configuration supplied and stored; native OAuth and Gmail sync follow the storage gate. |
| 5 — Zoho | Not started | OAuth client and data centre; verify official provider capabilities. |
| 6 — Unified inbox | Not started | Real cached account data and queued actions. |
| 7 — Reader / compose | Not started | Untrusted HTML, attachments, provider send/reply and drafts. |
| 8 — Search | Not started | Indexed local search without per-keystroke provider requests. |
| 9 — Offline sync | Not started | Durable queue, retries and lifecycle sync. |
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
