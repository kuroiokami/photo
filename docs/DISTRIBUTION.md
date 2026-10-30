# Distributing Photo to other Mac users

Status: **release plan, not a shipped installer**. Reviewed 2026-10-20 against the repository and Apple’s documentation. Users currently build from source using [Installation](INSTALLATION.md).

## Recommended first route

Distribute a **Developer ID-signed, Apple-notarized disk image (`.dmg`)** through a versioned GitHub Release or a download page. A user downloads it, opens it, drags Photo to Applications, and launches Photo. Recipients need no Swift, Xcode, Terminal or Apple Developer membership.

This is a recommendation for Photo’s initial public beta. Direct distribution fits its folder/card workflow and can be prepared before considering the Mac App Store. Apple supports notarization of Developer ID software distributed outside the store; see [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

## What exists today

Read-only inspection of `.build/Photo.app` found:

| Item | Current state | Release work |
| --- | --- | --- |
| Native app bundle | `.build/Photo.app`, packaged by `scripts/build-app.sh` | Use a clean, separate release staging directory |
| Build | Optimized local app available | Build from a pinned, tested Git commit |
| Architectures | Current executable is `arm64` only | Label Apple silicon support honestly; add Intel only after building/testing it |
| macOS minimum | 14.0 declared | Verify the signed artifact on macOS 14 and current supported systems |
| Signing | Ad-hoc; no TeamIdentifier | Developer ID Application signature, hardened runtime and secure timestamp |
| Identity | `com.kuroiokami.photo.development` | Choose a stable release identifier before first distribution; keep development identity separate |
| Version | Hardcoded `0.1.0`, build `1` | Parameterize version/build and increase them for each published artifact |
| Resources | SwiftPM resource bundles copied into wrapper | Stage from scratch so removed/renamed resources cannot linger; verify all embedded code/resources |
| Camera Preview helper | Bundled, ad-hoc-signed `PhotoPreviewWorker`, launched for one requested photo | Build for the supported chips, Developer ID-sign before the app, and verify launch/cancellation/shared-memory transfer in the final quarantined artifact |
| Installer/download | None | Signed/notarized DMG with Applications shortcut, release notes and checksum |
| Updates | Manual rebuild/copy | First beta: quit, replace complete app; signed automatic updates can follow separately |
| License | MIT OR Apache-2.0, at the recipient’s option | Include LICENSE-MIT, LICENSE-APACHE and NOTICE with source and app distributions |

No signing certificate, developer account status or notarization credentials were inspected. No software was submitted to Apple and no installer was published during this design work.

## Owner prerequisites

- Apple Developer Program membership and a Developer ID Application signing identity on the release machine. Apple currently lists **US$99 per membership year**, with local currency where available: [membership details](https://developer.apple.com/programs/whats-included/).
- Confirm the public app name, stable bundle identifier, support contact and intended hardware support. The owner selected MIT OR Apache-2.0; include LICENSE-MIT, LICENSE-APACHE and NOTICE in distributions.
- Configure notarization credentials through Keychain or protected CI secrets. Do not put passwords, certificate private keys or API keys into the repository or release artifacts.

No account purchase, agreement acceptance, certificate/private-key handling or public publishing is needed merely to implement the packaging scripts. Those owner-dependent steps occur when preparing the first signed release.

## Release pipeline to implement

1. **Build cleanly.** Run the repository checks for the pinned commit. Stage an optimized app with the selected version/build, stable identifier, icon and complete resources in a fresh directory outside the running development bundle. Preserve the existing local-development build command.
2. **Sign the app.** Sign nested code explicitly from the inside out, then the app with Developer ID Application, hardened runtime and secure timestamp. Use only entitlements actually needed. Verify signatures; do not use blanket runtime exceptions or `--deep` as a substitute for signing nested items correctly. See [Apple’s notarization issue guide](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).
3. **Notarize and staple the app.** Create a temporary ZIP for submission with `notarytool`; wait for an Accepted result, inspect failures, then staple/validate the ticket on the app. ZIP is a transport here; the ticket is stapled to the app, not the ZIP. See [customizing notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
4. **Make the download.** Create a read-only DMG containing the stapled app and an Applications shortcut. Sign the DMG, submit that final DMG for notarization, require Accepted, and staple/validate its ticket. Notarizing/stapling the app and final container is an intentionally explicit pipeline; never alter the signed app afterward.
5. **Validate the actual artifact.** Check code signing, notarization tickets and Gatekeeper assessment for app and DMG. Download through a browser onto a separate/clean test Mac so quarantine behavior is exercised. Install in Applications and launch from there; also test offline launch, folder/card selection, embedded RAW previews, detail, SQLite saves and restart. Test upgrade without losing preferences, decisions or review sessions.
6. **Publish after acceptance.** Attach the DMG, checksum, clear macOS/chip requirements, release notes, known limitations and installation steps to a versioned Release. Promote only the exact tested artifact; do not rebuild after testing. Recipients never need to disable Gatekeeper or remove quarantine manually.

The first pipeline can run locally on a release Mac; ordinary untrusted pull-request CI must not have signing credentials. A protected/manual release job can follow after the local process works. No `.pkg` installer, login/background service, administrator prompt or privileged install service is needed for the proposed single-app layout. The bundled `PhotoPreviewWorker` is an on-demand child process, not a separately installed service. Its hardened-runtime, shared-memory and minimum-platform acceptance belongs in final-artifact testing.

## Hardware and installation support

Start with an explicitly labeled **Apple silicon beta** if Intel testing is unavailable. To support both chip families, build a universal `arm64` + `x86_64` app and verify both app and preview-helper binary slices, packaged resources, platform minimums and real Intel behavior before calling it universal. A universal executable contains code for both architectures: [Apple universal binary guidance](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary). Do not infer Intel support merely from shared Swift source.

Keep macOS 14 as the declared floor unless a deliberate change is needed. Apple’s installed RAW decoder affects camera/detail support, so release notes must distinguish recognized extensions, embedded previews and actually tested RAW rendering.

The user-facing installation guide for a shipped beta should be:

1. Download the version matching your Mac.
2. Open the disk image and drag Photo to Applications.
3. Eject the disk image and open Photo from Applications.
4. Choose Photo Home and grant normal access to chosen photo/card folders when macOS asks.
5. For an update, quit Photo and replace the complete application; local Photo data remains separate from the app bundle.

These steps become actionable only once a notarized download exists. Until then, the current source-build guide remains accurate.

## Why the App Store can follow later

The Mac App Store is a separate distribution track. App Sandbox is required there, and persistent user-selected-folder access needs appropriate security-scoped access handling. Current sidebar storage uses plain paths, so a sandboxed release needs a folder/bookmark and data-migration pass, plus store submission work. Developer ID notarization does not itself require choosing the App Store route. See [App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) and [user-selected file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

Do not add automatic updating, telemetry, a paid licensing system or store integration merely to produce the first installer. Those remain separate product choices.

## Smallest release milestones

- **Packaging foundation:** clean versioned release bundle and DMG scripts, development/release identity separation, resource/signature checks, documented secret inputs and a reproducible artifact manifest. No credentials required for implementing the unsigned/local checks.
- **Signed beta candidate:** owner-provided signing/notarization setup; actual Accepted submissions, stapled tickets and Gatekeeper/clean-Mac acceptance. Not achievable from the existing ad-hoc signature alone.
- **Public beta:** both license texts and notices, verified supported machines, recipient installation/update instructions, honest limitations, signed artifact and checksum published through an explicit release action.
- **Wider release:** measured large-library performance, broader camera/macOS/accessibility/Intel coverage and, if desired, an independently reviewed update/store path.
