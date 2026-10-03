# Connect Gmail and Zoho: registration guide

Checked against official documentation on 3 October 2026. Gmail registration supports the current integration; Zoho is deferred.

You can do the console steps in a browser on Windows. The app's current bundle identifier is **`dev.freddiephilpot.dispatch`**, set in `project.yml`. If you choose a different bundle identifier, update that file and register the same identifier with Google.

## Gmail — start here

1. Open [Google Cloud Console](https://console.cloud.google.com/), select or create a project named **Dispatch**, then enable **Gmail API** in **APIs & Services → Library**. [Google's Gmail quickstart](https://developers.google.com/workspace/gmail/api/quickstart/python) describes the console setup; its Python client instructions are not needed for this Swift app.
2. Open **Google Auth Platform**. Under **Branding**, enter the app name, your support email and developer contact email. Under **Audience**, choose **External** for a personal Gmail account, keep it in **Testing**, and add the Gmail address you will use under **Test users**. An organisation-owned internal app is a different option, available within Google Workspace. [Consent setup](https://developers.google.com/workspace/guides/configure-oauth-consent).
3. Under **Data Access**, add `https://www.googleapis.com/auth/gmail.modify`. It covers reading, changes, drafts and sending, including moving messages to Trash. Do not request `https://mail.google.com/`; we do not need permanent deletion that bypasses Trash. `gmail.modify` is a restricted scope, so wider distribution requires Google's applicable verification process. [Gmail scope reference](https://developers.google.com/workspace/gmail/api/auth/scopes).
4. Under **Clients**, create an OAuth client with application type **iOS**, name **Dispatch iOS**, and bundle ID **`dev.freddiephilpot.dispatch`**. Use your actual App Store ID or Apple team information only if applicable; this project is intended to support sideloading. Copy the public client ID ending in `.apps.googleusercontent.com` and the **iOS URL scheme** shown for that client. [Google's iOS setup](https://developers.google.com/identity/sign-in/ios/start-integrating).
5. Your supplied public client ID and URL scheme are already in `Configuration/GoogleOAuth.plist`, and the callback scheme is registered in `project.yml`. Verify that this Google client was registered for `dev.freddiephilpot.dispatch`. If you replace the client, update both files. You do not need to install Xcode, edit a generated project, create a Gmail password, or supply a Google client secret for an iOS client. The app will use browser-based consent, state checking and PKCE. [Native OAuth reference](https://developers.google.com/identity/protocols/oauth2/native-app).

Keep this app in Testing while developing. Testing-mode refresh-token expiry can require reconnecting; see [Google's token-expiration guidance](https://developers.google.com/identity/protocols/oauth2#expiration). A Workspace administrator may also need to allow the app.

## Zoho — find your data centre first

Log into Zoho Mail and copy the hostname in the address bar. Your country alone does not determine the account's data centre. Common examples:

| Region | Mail API origin |
| --- | --- |
| US | `https://mail.zoho.com` |
| EU | `https://mail.zoho.eu` |
| India | `https://mail.zoho.in` |
| Australia | `https://mail.zoho.com.au` |
| Japan | `https://mail.zoho.jp` |
| Canada | `https://mail.zohocloud.ca` |
| China | `https://mail.zoho.com.cn` |
| UAE | `https://mail.zoho.ae` |
| Saudi Arabia | `https://mail.zoho.sa` |

Zoho lists these origins in its [Mail API getting-started guide](https://www.zoho.com/mail/help/api/getting-started-with-api.html). OAuth Accounts domains and Mail API domains are separate; do not derive all endpoints by replacing `.com` with a regional suffix.

## Zoho — registration and the callback decision

Zoho's [mobile OAuth overview](https://www.zoho.com/developer/oauth/mobile-and-desktop-apps/overview.html) requires PKCE. However, its current [mobile token endpoint](https://www.zoho.com/developer/oauth/mobile-and-desktop-apps/get-access-token.html) also lists `client_secret` as required. Its [authorization endpoint](https://www.zoho.com/developer/oauth/mobile-and-desktop-apps/get-authorization-code.html) lists an HTTP/HTTPS redirect, while its [older iOS SDK guide](https://www.zoho.com/accounts/sdk/iosnative.html) describes an app URL scheme. These documents do not establish a consistent secret-free native configuration.

The proposed implementation is a small HTTPS OAuth broker that keeps the Zoho application secret on the server. It handles the code exchange; mail sync remains on the iPhone, and account tokens are kept in Keychain. The broker needs a deployed HTTPS callback before registration is final. This is an implementation recommendation based on the documented constraints, not a verified Zoho integration.

Once that callback is chosen:

1. Open [Zoho API Console](https://api-console.zoho.com/) using the region appropriate for your account.
2. Choose **Server-based application** for the proposed broker. Enter **Mail** as the name, the real project homepage, and the broker's exact HTTPS callback. Do not register an invented URL or use a Self Client for the interactive iPhone login. [Client registration reference](https://www.zoho.com/developer/oauth/register-app.html).
3. Record the public client ID and redirect URI. Put the **client secret only in the broker's deployment secret store**. It must not go into Swift source, an IPA, Git, or this chat.
4. Stage 5 will request the endpoint-specific mail scopes it actually uses. The expected starting set is `ZohoMail.accounts.READ`, `ZohoMail.messages.ALL`, `ZohoMail.folders.READ`, and `ZohoMail.tags.READ`. Attachment operations are documented under message scopes; do not assume a Gmail-style scope or endpoint. [Zoho Mail API index](https://www.zoho.com/mail/help/api/).
5. If you need accounts from multiple data centres, enable multi-DC support and honour the authenticated account's location. [Zoho Mail OAuth guide](https://www.zoho.com/mail/help/api/using-oauth-2.html).

When returning to Zoho, record your **Zoho Mail hostname**. We will settle the broker hosting and callback before creating the Zoho client. If Zoho confirms a supported secret-free native exchange for your registration, the implementation can use that instead.

## What may be shared

| Value | Location |
| --- | --- |
| Google iOS client ID / iOS URL scheme | Public app configuration; safe to share here |
| Zoho region / client ID / redirect URI | Public configuration; safe to share here |
| Zoho application client secret | Backend deployment secrets only |
| OAuth access and refresh tokens | Device Keychain; never SwiftData or Git |
| Apple signing certificate / APNs `.p8` key | Later signing/backend secret configuration; never the app source |

Account login and a real device test are required before provider support can be marked verified. After installing the Gmail build, open Accounts → Connect Gmail. Ensure the Gmail API is enabled and your Gmail address is an OAuth test user before signing in.
