# Dispatch

A native SwiftUI mail app for **iOS 26+**, maintained from Windows using XcodeGen and macOS GitHub Actions.

## Current status

The consolidated v0.8.0 tree includes [productivity workflows](docs/productivity-workflows.md), [local intelligence and iOS integrations](docs/ios-local-intelligence.md), and [mail security checks](docs/security-and-livecontainer.md), alongside tasks, receipts, composer attachments and the compact native UI. See [release notes](docs/release-notes.md), [CI performance](docs/ci-performance.md) and the [signed device checklist](docs/oauth-setup.md).

Earlier releases remain available at their tags. Sender profiles, attachment library, project collections and subscriptions are included. Further proposals are in the [feature ideas](docs/feature-ideas.md).

Download the latest IPA from [Dispatch releases](https://github.com/pphilfre/mail/releases). The IPA requires re-signing with your sideloading tool.

Your supplied Google iOS client is configured. Follow the [OAuth setup guide](docs/oauth-setup.md) to confirm Gmail API access, your test user and the registered Dispatch bundle ID. Zoho is deferred.

The foundation includes Inbox, Accounts, Settings, a sample message reader, and a compose sheet that saves real on-device drafts. Sample messages are opt-in under Settings and clearly labelled. Connect Gmail in Accounts. Cached messages, threads, labels, incremental sync, read/star/archive/trash, sending, drafts, reply/reply-all forwarding, file/photo attachments, conversation rows, bulk actions and Undo, saved/operator searches, account signatures and recipient assistance are implemented. See [Gmail details and limitations](Providers/Gmail/README.md). Live login and mail delivery require an installed, signed device build and your configured Google test user.

## Windows workflow

Edit `.swift` files and `project.yml` in your preferred editor. Commit and push a pull request to GitHub. Open **Actions → iOS CI** to see the simulator build and unit/UI test results. Download `ios-test-results-*` for logs and the Xcode result bundle. Never manually edit a generated `.xcodeproj`. Main and releases run the full suite; core-only pull requests use all unit tests plus eight UI checks. Documentation-only changes skip CI, and weekly full runs collect coverage.

```powershell
git add .
git commit -m "Describe your change"
git push
```

The runner uses macOS 26 with Xcode 26.6, generates the project using XcodeGen, builds for an available iOS 26+ iPhone simulator and runs unit/UI tests. XcodeGen is installed through Homebrew; its resolved version appears in the build log. Xcode's version is pinned in `scripts/prepare-macos.sh` and should only change together with a passing CI run.

## Release an IPA

After the intended commit passes CI:

```powershell
git tag v0.2.1
git push origin v0.2.1
```

The release workflow runs the full iOS CI suite alongside the physical-device build, packages `Payload/Dispatch.app` into `Dispatch-v<version>.ipa`, and attaches the IPA and SHA-256 checksum to a GitHub Release only after both succeed. The simulator app/test bundles compile once and run on two separate test runners. Package downloads and compatible incremental compiler outputs are cached. Tags must use `vMAJOR.MINOR.PATCH`. Manual runs save artifacts; enable their publish input to publish the validated commit as a release. The historical `v0.1.0` tag predates the Dispatch rename.

The default IPA is **unsigned** and needs a compatible sideloading tool to re-sign it with your Apple account. Installation and push support depend on that tool and your provisioning. Signed releases and APNs are later stages; no signing secrets are required for this foundation.

The app's display name, target and scheme are Dispatch; its internal Swift module is `DispatchMail` to avoid colliding with Apple's `Dispatch` module.

Simulator builds are locally ad-hoc signed so CI can exercise Keychain. `App/Simulator.entitlements` uses the test-only `DISPATCHCI` namespace and applies only to the simulator SDK; it is excluded from app resources. No Apple certificate is needed for this test signing. Device IPA builds remain unsigned and do not use these simulator entitlements. The sideloading tool must give the installed app its valid signing identity and default Keychain access group.

## Structure

```text
App/                     App entry, navigation shell, privacy manifest
Core/                    SwiftData, Keychain, local drafts and runtime
Providers/Gmail/         OAuth, REST, incremental sync and MIME
Providers/Zoho/          Stage 5 boundary
Features/Inbox/           Inbox and message rows
Features/Message/         Cached threads and safe native text reader
Features/Compose/         Composer and on-device drafts
Features/Search/          Stage 8 boundary
Features/Accounts/        Account screen
Features/Settings/        Settings
DesignSystem/             Native styling constants
Tests/                    Unit and UI tests
scripts/                  macOS build, simulator selection, IPA packaging
```

The app opens its versioned SwiftData database in Application Support and loads cached drafts before any network work. Existing foundation JSON drafts are imported once with a durable marker; the protected original file is kept for recovery. Import failure preserves the original and surfaces a retry screen. Store failures never silently replace the database with an empty in-memory store.

Shared storage includes accounts, messages, threads, Codable mail addresses, folder/label metadata, attachment metadata, outgoing messages and pending operations. Account-local provider IDs are scoped by the account UUID. Account deletion clears associated rows in one transaction. CredentialVault stores OAuth tokens only in device-local Keychain items accessible after the first unlock; it disables iCloud synchronisation and redacts diagnostic descriptions. Gmail credentials never enter SwiftData.

## macOS commands used by CI

```bash
bash scripts/prepare-macos.sh
bash scripts/build-ios.sh
bash scripts/test-ios.sh
bash scripts/package-ipa.sh v0.2.0
```

## Reference documentation

- [Apple: SwiftUI's iOS 26 design](https://developer.apple.com/videos/play/wwdc2025/323/) — native bars and controls provide Liquid Glass automatically.
- [XcodeGen project specification](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md).
- [GitHub macOS 26 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).
- [Apple required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
