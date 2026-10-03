Dispatch v0.3.0 refreshes the inbox and reader while keeping native iOS 26 Liquid Glass controls.

- New animated welcome screen with Google sign-in and a Zoho coming-soon placeholder.
- Compact inbox header, left-hand account/mailbox drawer, full-width message rows and company website icons with initials fallback.
- HTML email rendering, tappable links, selectable text and inline raster images.
- Remote-image controls in Settings and a per-message load option; scripts and active web content remain blocked.
- Custom left/right swipe actions, full-swipe preference, preview length and light/dark appearance.
- Bounded retries for Gmail read throttling and temporary server failures, clearer access-denied diagnostics, and preservation of partially downloaded mail.

Company icons are decorative website icons, not verified sender identities. Zoho, push notifications and general attachment transfer remain deferred. Forwards contain text only. Live Google sign-in and sync must still be checked on a signed device; CI uses fixtures and never sends personal mail.

The IPA requires iOS 26 or later and is unsigned. Sign and install it with your compatible sideloading tool and Apple account. Bundle identifier: dev.freddiephilpot.dispatch.
