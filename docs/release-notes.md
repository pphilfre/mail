Dispatch is a native SwiftUI mail app for iOS 26 or later, with bundle identifier `dev.freddiephilpot.dispatch`.

This release adds Gmail: native Google OAuth with PKCE and Keychain tokens, cached messages/threads/labels, history-based incremental sync, read/star/archive/trash actions, sending, Gmail/local drafts, reply/reply-all and text forwarding. Open Accounts → Connect Gmail after installing. Your Google project must enable Gmail API, register this bundle ID and list your Gmail address as an OAuth test user; see docs/oauth-setup.md.

The inbox opens cached mail first. Initial sync stores recent All Mail and Inbox messages; mailbox selection fetches recent matching messages and Load older mail continues All Mail pagination. Offline changes are queued until launch, foreground sync or pull-to-refresh. Rich HTML and attachment transfer are pending; HTML is currently shown as native text with remote images blocked. Forwards contain text only. Zoho and push are deferred.

If sending has an unknown outcome, Dispatch preserves the copy and never automatically resends it. Use Check Sent or inspect Gmail before creating another message. CI uses fixture HTTP responses; a live sign-in/send smoke test remains necessary on your signed device.

The IPA is unsigned. Use a compatible sideloading tool to sign and install it with your own Apple account. It cannot be installed directly as downloaded. No signing certificate or private key is included. APNs is not configured; unsigned/re-signed apps may not support push entitlements.
