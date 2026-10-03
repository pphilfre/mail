# Stage ledger

The brief requires implementation, build/test, fixes and documentation at each stage before starting the next. Workflows for Stage 2 are bootstrapped with Stage 1 because Windows cannot run the iOS compiler.

| Stage | Status | Evidence / next gate |
| --- | --- | --- |
| 1 — Foundation | Implemented, macOS validation pending | Native shell, opt-in sample inbox/reader, protected persistent draft file, tests. Must pass iOS CI. |
| 2 — Windows / Actions | Workflows implemented, validation pending | Simulator CI plus tag-driven unsigned IPA packaging. Must verify CI and device packaging. |
| 3 — SwiftData | Not started | Migrate foundation drafts; add shared mail models and Keychain. |
| 4 — Gmail | Not started | OAuth app client ID/redirect configuration and verified provider implementation. |
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
