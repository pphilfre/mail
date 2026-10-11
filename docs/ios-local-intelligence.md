# Native iOS intelligence and privacy

Dispatch is designed for standalone installation as a signed IPA, including installation through iLoader. Native capabilities are not disabled based on LiveContainer.

See [the current audit and implementation](premium-native-mail-audit.md) for body-based inline summaries, writing tools, verified model installation progress, background refresh, notifications, data preservation, and provisioning requirements.

Apple Intelligence is used only when the system reports it available. Other supported devices can install Qwen3 0.6B for inline writing assistance and body-based paragraph summaries. Without a model, summaries explain how to enable one instead of presenting copied passages as a summary. See [the UI and AI polish notes](mail-ui-ai-polish.md) for the input pipeline and validation limits. No mail goes to an external inference service. Model files download over Wi-Fi from a pinned Hugging Face revision and are size/SHA-256 verified before installation is marked complete.

Refresh and local new-mail alerts are opt-in. iOS controls background scheduling, and app lock pauses background mail access. Real-time remote push still requires provisioned APNs plus a delivery service. App Groups are required for a future separate extension, not for the current single-target app; requesting an unprovisioned group would not provide functionality.

Existing accounts, device-only Keychain items, preferences, cached mail and on-device drafts remain in their existing storage. The SwiftData schema and database path are unchanged.
