# Native iOS integration and local intelligence

This build targets LiveContainer guest execution. It retains the SwiftData schema,
Gmail synchronisation, credential vault and provider action queue. Zoho is a
provider enum and roadmap placeholder in this checkout, not a working connector.
Analysis and semantic search use provider-independent cached records, so future
Zoho records can participate without a separate AI service.

## Compatibility decision

| Requested integration | LiveContainer guest build |
| --- | --- |
| Interactive Home / Lock Screen widgets | Unavailable. WidgetKit needs a registered extension process and app identity. |
| App Intents / Siri mail actions | Unavailable. Guest metadata cannot be relied on for system discovery or launching. Use LiveContainer's own Launch App shortcut to launch Dispatch. |
| Spotlight cached email indexing | Disabled. Guest app identity/launch routing is not independently registered; indexing under the host risks incorrect routing and content exposure. |
| Share extension | Unavailable as a Dispatch extension. Use LiveContainer's Share extension to forward files/links to Dispatch, or its URL launcher. Dispatch handles forwarded file, HTTP(S) and mailto URLs and saves a draft before presenting it. |
| Account Focus Filters | Unavailable as a registered system filter. Existing manual account selection remains available. |
| Face ID lock | Implemented with LocalAuthentication, device-passcode fallback, explicit authentication to change the setting, background relock and a separate privacy window covering presentations in app-switcher snapshots. |
| Actionable remote push | Unavailable. Guest apps cannot receive APNs. A normally installed app also needs a provisioned push entitlement plus a Gmail/Zoho push delivery service; provider mail APIs are not an APNs backend. |

No extension targets, APNs requests, phantom widgets, guest intent donations or
host Spotlight indexing are included. A normal installation is necessary for the
unavailable integrations but does not automatically implement them. A future
normal-install configuration must supply app/extension provisioning, app groups,
extension lifecycles and account-safe notification routing before enabling them.
Local notifications are not presented as remote push.

Primary compatibility references, checked 9 October 2026:

- [LiveContainer limitations](https://github.com/LiveContainer/LiveContainer#limitations)
- [LiveContainer app settings](https://livecontainer.github.io/docs/guides/app-settings)
- [LiveContainer Home Screen launch shortcut](https://livecontainer.github.io/docs/guides/add-to-home-screen)
- [Apple App Intents integration](https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework)

Actual guest behavior can depend on LiveContainer version, host permissions and
its file-picker settings. Validate forwarded files/URLs and Face ID on the user's
device. This lock protects the app UI, not the host from reading guest storage.

## Local analysis

- Search offers Keywords and Meaning modes. Meaning uses Apple's
  NaturalLanguage sentence embeddings; unsupported languages/assets fall back
  visibly to keyword search. Existing account, unread, starred, attachment and
  structured query restrictions apply before ranking. It examines at most
  1,000 eligible cached messages, ranks at most 50 matches, debounces keystrokes
  and maintains a disposable 1,000-vector LRU. Text is bounded to 1,000 characters
  per message; this is not full-body search over all remote mail.
- Inbox links show automatic category suggestions and important unread catch-up.
  Categories combine provider category labels with NLTokenizer word hints. They
  are heuristics, not a trained classifier, and never move mail on the server.
  Catch-up considers the latest 300 cached incoming messages and at most 20
  account-qualified threads. Importance uses stars, provider importance and
  action words, so it may miss mail the user considers important.
- Reader Local insights selects original sentences from up to 30 cached messages
  in the thread, plus dates and possible deadlines. Missing bodies use previews.
  Summaries are extractive rather than generative by default. Dates initially
  require an explicit year to avoid presenting relative dates resolved against
  today's clock as dates belonging to an old email. Suggestions never create
  calendar events/tasks automatically.
- Analysis runs on utility tasks over Sendable snapshots, stops on cancellation
  and never fetches remote email bodies for AI. There is no background polling or
  continuous inference. NaturalLanguage supplies relevant built-in text
  functionality; no custom Core ML classifier or Vision OCR model is bundled.

## Optional generation

Settings → Privacy & intelligence provides explicit Wi-Fi download, cancel and
delete controls for Qwen3 0.6B (4-bit, Apache-2.0), using pinned
[MLX Swift LM 2.29.1](https://github.com/ml-explore/mlx-swift-lm/tree/2.29.1)
and MLX Swift 0.29.1. MLX is used for generation because these weights have a
maintained iOS decoder/tokenizer runtime; a general Core ML model alone would not
provide that runtime. This does not use Foundation Models, Apple Intelligence,
cloud inference, Python execution or JIT.

Weights/config/tokenizer download from the public
[model repository](https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/tree/73e3e38d981303bc594367cd910ea6eb48349da8)
at revision 73e3e38d981303bc594367cd910ea6eb48349da8. The required files total about
347 MB. Each file's size and SHA-256 are checked before publishing an installation
marker; partial downloads do not enable inference. Files are excluded from
device backups. A model download contacts Hugging Face/CDN endpoints but contains
no mail or prompts. Generation loads only the local model directory.

Physical Metal devices with at least 6 GB RAM are eligible, including iPhone 14
Pro Max. Simulator generation is explicitly unavailable. Low Power Mode and high
thermal pressure block generation. One job runs at a time; the input is bounded
to 4,000 characters and 1,536 tokens, output to 192 tokens, KV cache to 2,048
tokens, and generation to about 45 seconds after prefill. GPU cache is 16 MB;
weights are released after each request. Backgrounding and memory warnings
cancel model work. These limits are conservative design bounds, not measured
peak-RAM or battery guarantees on LiveContainer.

The reader can request a generative thread summary. Composer options offer
polishing, shortening and suggested replies (reply drafts already contain the
quoted message). Generated text is previewed; Use in draft is explicit and checks
that the source draft has not changed. It never sends mail. Small-model output
can be wrong, truncated or follow malicious instructions despite prompt
separation; review it before use.

## Validation

The existing iOS CI workflow generates the Xcode project and runs the existing
unit/UI suites plus LocalIntelligenceTests on macos-26. It also compiles the
optional MLX integration without downloading weights or using network inference.
Unit coverage includes source-only summary extraction, category labels, account
scoping/thread identity, explicit date extraction, semantic-filter invariants,
safe incoming URL routing, thought removal and cancellation.

Device checks still needed: Face ID success/cancel/passcode/lockout, backgrounding
with sheets/previews open, LiveContainer forwarding with file-picker fixes,
Wi-Fi interrupted download/delete, offline generation, cancellation, thermal
pressure and actual peak RSS/energy on iPhone 14 Pro Max.
