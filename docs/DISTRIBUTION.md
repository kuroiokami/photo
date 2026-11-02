# Distributing Photo to other Mac users

Status: **local packaging foundation implemented; no public notarized download**. Updated 2026-11-02. Source builds remain available through [Installation](INSTALLATION.md). The local app/DMG pipeline and safe updater are implemented in [ADR 0054](decisions/0054-local-app-and-disk-image-packaging.md); Developer ID, notarization and clean-Mac acceptance remain separate milestones.

## Recommended first route

Distribute a **Developer ID-signed, Apple-notarized disk image (`.dmg`)** through a versioned GitHub Release or a download page. A user downloads it, opens it, drags Photo to Applications, and launches Photo. Recipients need no Swift, Xcode, Terminal or Apple Developer membership.

This is a recommendation for Photo’s initial public beta. Direct distribution fits its folder/card workflow and can be prepared before considering the Mac App Store. Apple supports notarization of Developer ID software distributed outside the store; see [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

## What exists today

| Item | Implemented and verified locally | Remaining acceptance |
| --- | --- | --- |
| Source provenance | Export selected Git commit; isolated source and SwiftPM scratch folders; omit working edits/untracked files | Public candidate must use the accepted source commit |
| App assembly | Fresh numeric version/build; worker, SwiftPM resources, minhwa magpie ICNS, both licenses/NOTICE and BuildInfo.json | Public-release presentation and final artifact acceptance |
| Architectures | Local package verifies app and helper are arm64; actual deployment metadata declares 14.0 | Native macOS 14, Intel/universal and broader platform checks |
| Identity | Packaged `com.kuroiokami.photo`; development retains `.development`; QA override for disposable settings | First packaged launch has separate preferences from development |
| Signing | Explicit ad-hoc worker → app signing; strict signatures and sealed-content verification | Developer ID, hardened runtime, timestamps and notarization |
| Disk image | UDZO read-only compressed HFS+, Applications shortcut, instructions and licenses; mounted-payload checks | Quarantined download, Gatekeeper and clean-Mac/offline checks |
| Receipts | App/worker UUIDs, architectures, hashes, file inventory, source pin, manifest and SHA256SUMS | No claim of bit-for-bit reproducible builds or publisher authentication from checksums |
| Local updates | Refuse running main/helper, links, overlap and wrong identity; fresh copy and atomic exchange; retain old app inode/bytes | Signed/public-update acceptance; automatic updates remain separate |
| Data preservation | Installer writes app folders only; disposable upgrade retains settings and saved decisions | Broader migrations, clean-machine and public-release acceptance |

No certificate, developer account or notarization credential was inspected. No app was submitted to Apple and no installer was uploaded or publicly released.

## Build a local installation package

Requirements: macOS, Apple Swift 6+, Python 3.9+ standard library, Git and Apple's `codesign`, `hdiutil`, `ditto`, `lipo`, `otool` and `dwarfdump` tools. `sips` and `iconutil` generate the native icon from the tracked artwork. No Python packages or signing credentials are needed. Photographers receiving a future packaged app will need none of these build tools.

From a reviewed source commit, first run `sh scripts/check.sh` and `python3 scripts/check-repository.py`, then:

```sh
python3 scripts/package-release.py --local \
  --revision HEAD --version 0.1.0 --build 1 \
  --output .build/packages/Photo-0.1.0-1-arm64-local

python3 scripts/verify-release.py .build/packages/Photo-0.1.0-1-arm64-local
```

The package builder uses the **committed** snapshot named by `--revision`. Working edits are preserved but are not included. Use a new output folder and increasing build number for another candidate; existing packages are never replaced. Version has three numeric components; build is a positive integer. The default packaged identity is stable. `--bundle-id` exists for disposable QA preferences and should not be changed between actual upgrades.

The output folder contains:

- `Photo.app` — the complete locally signed app and bundled preview worker.
- `Photo-<version>-<build>-macos-arm64-local.dmg` — the local installation image.
- `manifest.json` — source/version/signing status, exact executable/file inventory and image hash.
- `SHA256SUMS` — hashes for the DMG and manifest. Run `shasum -a 256 -c SHA256SUMS` from the output folder if checking manually.

Verification runs automatically before publication to the new output folder. It checks metadata, signatures, deployment/architecture agreement, hashes and UDZO format, then mounts a private read-only image, checks its app/guide/licenses/Applications shortcut and detaches it. Source/build staging is removed afterward. Neither command publishes a GitHub Release or contacts Apple's notary service.

These are **local development candidates**, not notarized public downloads. Open your local image in Finder, quit Photo, drag Photo.app onto Applications, eject and launch the installed copy. Do not disable Gatekeeper or strip quarantine to make a distributed candidate pass. Public distribution requires the acceptance below.

### Safe development and local installation

The existing `sh scripts/build-app.sh [--release]` command still produces `.build/Photo.app`, now with fresh staging, worker/resources/licenses, verification and stopped-app replacement. It requires Python 3.9+. A working-tree receipt records its base commit and dirty state. It never claims that an edited development build is a committed-source release.

To install or update a stopped local development copy:

```sh
python3 scripts/install-app.py --app .build/Photo.app \
  --destination ~/Applications/Photo.app
```

The source and destination must be separate, regular app folders with matching identities when replacing. The installer refuses a running app/helper, stages and verifies a complete new copy beside the destination, and atomically exchanges directories. It prints the retained `Photo.previous-….app` backup location. Keep backups until satisfied with the update; remove obsolete local build backups deliberately when no longer needed. A backup-naming error reports the retained staging location and never cleans up that only previous copy. Filesystem swap/exclusive-rename support is required; there is no unsafe in-place fallback.

Quit all Photo copies before updating or making installation-test decisions. Replacing an app leaves saved data and sidecars alone. Upgrades with the same packaged identity preserve settings. Development and packaged builds have separate preferences but currently share Application Support/Photo decisions, protection and operation journals. A QA identifier alone does not isolate that database. This foundation's installer/verifier supports local ad-hoc builds; signed/notarized public installation comes later.

## App icon

[Original minhwa-inspired artwork and exact generation prompt](../Assets/AppIcon/PROVENANCE.md) are tracked separately from sample photographs. The build creates a native `PhotoIcon.icns` with all standard 1x/2x representations from 16 to 1024 pixels, preserves alpha, declares it through `CFBundleIconFile` and seals it before signing. Both development and packaged apps use the same source. Verification checks the actual ICNS representations and its receipt/source hashes. Legacy local candidates with no icon remain verifiable and can upgrade to an icon-bearing app.

## Local acceptance evidence — 2026-11-02

[Recorded evidence](benchmarks/2026-11-02-packaging.json) identifies local 0.1.0 build 1002, source `42a0059`, app/worker UUIDs, exact 13-file inventory and a 3,997,375-byte DMG. It verifies signatures, hashes, arm64/macOS 14 metadata, UDZO format and mounted contents after temporary source/build removal. Reusing an existing output folder is refused without mutation. The stable local artifact remains under `.build/packages/Photo-0.1.0-1002-arm64-local` on the reference machine; generated installers are not tracked or uploaded.

Native disposable variants from those compiled inputs pass initial installation, bundled sample resources, owned-folder browsing, camera-JPEG helper and rendered RAW. A running installed app is refused. Stopped update 1001→1002 preserves settings, shared saved-data files, images/sidecars and the old executable inode/bytes; the new process restores the folder, Auto-advance and four-star Pick decision. Only owned test records/preferences are cleaned up; all other database rows remain unchanged. This QA identifier isolates preferences only, so shared-store cleanup is explicitly scoped. The app is quit normally and process exit verified.

Shared checks pass 307 registered Swift cases / 305 default executions, the endurance smoke and 17 Python cases. Native/portable packaging tests cover the safety failures described in ADR 0054. Provider startup delay is not app-latency evidence. No public-signing, hardened-runtime, quarantine/Gatekeeper, clean-Mac/offline, macOS 14/Intel or general camera acceptance is inferred.

The [app-icon follow-up](benchmarks/2026-11-02-app-icon.json) provides local **0.1.0 build 1003**, source `a54c690`, with the original minhwa magpie icon included in all ten native representations. Its 7,213,599-byte DMG and 14 sealed app files pass standalone verification, including the actual mounted contents. The stable local output is `.build/packages/Photo-0.1.0-1003-arm64-local`; development, packaged and disposable native QA icons match exactly. The standard About panel visibly loads the icon. The previous build-1002 package remains verifiable; signing/public-release limits above still apply.

## Owner prerequisites

- Apple Developer Program membership and a Developer ID Application signing identity on the release machine. See Apple’s current [membership details](https://developer.apple.com/programs/whats-included/) for enrollment and local pricing.
- Confirm the public app name, stable bundle identifier, support contact and intended hardware support. The owner selected MIT OR Apache-2.0; include LICENSE-MIT, LICENSE-APACHE and NOTICE in distributions.
- Configure notarization credentials through Keychain or protected CI secrets. Do not put passwords, certificate private keys or API keys into the repository or release artifacts.

No account purchase, agreement acceptance, certificate/private-key handling or public publishing is needed merely to implement the packaging scripts. Those owner-dependent steps occur when preparing the first signed release.

## Remaining public-release pipeline

1. **Choose the accepted source.** The local packaging foundation implements isolated committed-source app/DMG assembly. Run checks for the selected commit and retain the exact tested app/artifact. Add public presentation/versioning choices before signing.
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

These are the intended recipient steps for a future notarized download. Local candidates can already be installed this way on the build/test Mac; they do not establish Gatekeeper or clean-Mac acceptance.

## Why the App Store can follow later

The Mac App Store is a separate distribution track. App Sandbox is required there, and persistent user-selected-folder access needs appropriate security-scoped access handling. Current sidebar storage uses plain paths, so a sandboxed release needs a folder/bookmark and data-migration pass, plus store submission work. Developer ID notarization does not itself require choosing the App Store route. See [App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) and [user-selected file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

Do not add automatic updating, telemetry, a paid licensing system or store integration merely to produce the first installer. Those remain separate product choices.

## Smallest release milestones

- **Packaging foundation (implemented):** clean versioned local app/DMG, committed-source isolation, identity separation, worker/resource/signature and mounted-payload checks, safe local updates and artifact manifest/checksums. See ADR 0054 and the tracker for observed checks. No credentials used; no bit-for-bit reproducibility claim.
- **Signed beta candidate:** owner-provided signing/notarization setup; actual Accepted submissions, stapled tickets and Gatekeeper/clean-Mac acceptance. Not achievable from the existing ad-hoc signature alone.
- **Public beta:** both license texts and notices, verified supported machines, recipient installation/update instructions, honest limitations, signed artifact and checksum published through an explicit release action.
- **Wider release:** measured large-library performance, broader camera/macOS/accessibility/Intel coverage and, if desired, an independently reviewed update/store path.
