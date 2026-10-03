# Dispatch

A native SwiftUI mail app for **iOS 26+**, maintained from Windows using XcodeGen and macOS GitHub Actions.

## Current status

Stage 1 is verified: [macOS CI](https://github.com/pphilfre/mail/actions/runs/37123967712) built the app and passed four unit tests and three UI tests. Stage 2's tag-driven IPA release is being validated before starting the storage stage. See [stage status](docs/stages.md).

Before the provider stages, follow the [OAuth setup guide](docs/oauth-setup.md) to register Gmail and prepare the Zoho configuration from Windows.

The foundation includes Inbox, Accounts, Settings, a sample message reader, and a compose sheet that saves real on-device drafts. Sample messages are opt-in under Settings and clearly labelled. Account connections and sending are not yet available; no provider functionality is simulated.

## Windows workflow

Edit `.swift` files and `project.yml` in your preferred editor. Commit and push to GitHub. Open **Actions → iOS CI** to see the simulator build and unit/UI test results. Download `ios-test-results-*` for logs and the Xcode result bundle. Never manually edit a generated `.xcodeproj`.

```powershell
git add .
git commit -m "Describe your change"
git push
```

The runner uses macOS 26 with Xcode 26.6, generates the project using XcodeGen, builds for an available iOS 26+ iPhone simulator and runs unit/UI tests. XcodeGen is installed through Homebrew; its resolved version appears in the build log. Xcode's version is pinned in `scripts/prepare-macos.sh` and should only change together with a passing CI run.

## Release an IPA

After the intended commit passes CI:

```powershell
git tag v0.1.0
git push origin v0.1.0
```

The release workflow reruns build/tests, builds for a physical iOS device, packages `Payload/Dispatch.app` into `Dispatch-v0.1.0.ipa`, and attaches the IPA and SHA-256 checksum to a GitHub Release. Tags must use `vMAJOR.MINOR.PATCH`.

The default IPA is **unsigned** and needs a compatible sideloading tool to re-sign it with your Apple account. Installation and push support depend on that tool and your provisioning. Signed releases and APNs are later stages; no signing secrets are required for this foundation.

## Structure

```text
App/                     App entry, navigation shell, privacy manifest
Core/                    Foundation state, local draft file, sample data
Providers/Gmail/         Stage 4 boundary
Providers/Zoho/          Stage 5 boundary
Features/Inbox/           Inbox and message rows
Features/Message/         Plain-text sample reader
Features/Compose/         Composer and on-device drafts
Features/Search/          Stage 8 boundary
Features/Accounts/        Account screen
Features/Settings/        Settings
DesignSystem/             Native styling constants
Tests/                    Unit and UI tests
scripts/                  macOS build, simulator selection, IPA packaging
```

Foundation drafts use an atomic, protected JSON file in Application Support. Stage 3 will migrate them to SwiftData before adding real mail. OAuth credentials will live in Keychain, never in this file or SwiftData. No remote network requests occur in the foundation.

## macOS commands used by CI

```bash
bash scripts/prepare-macos.sh
bash scripts/test-ios.sh
bash scripts/package-ipa.sh v0.1.0
```

## Reference documentation

- [Apple: SwiftUI's iOS 26 design](https://developer.apple.com/videos/play/wwdc2025/323/) — native bars and controls provide Liquid Glass automatically.
- [XcodeGen project specification](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md).
- [GitHub macOS 26 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).
- [Apple required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
