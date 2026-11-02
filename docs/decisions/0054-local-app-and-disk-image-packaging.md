# 0054: Versioned local app and disk-image packaging

- Date: 2026-11-02
- Status: Implemented local packaging foundation; public distribution remains gated

## Decision

Use Python 3.9+ standard-library helpers and Apple's installed tools. `package-release.py --local` exports an explicitly selected Git commit into a private temporary directory, rejects links/special paths in that export, and builds both app and camera-preview worker with a separate SwiftPM scratch directory. Working edits, private/untracked files and stale build resources are excluded from the source snapshot. This is repeatable source provenance, not bit-for-bit reproducible Mach-O/DMG output.

Assemble a fresh Photo.app with numeric version/build, macOS 14 declaration, source receipt, exactly the required SwiftPM resource bundle and both license texts/NOTICE. Sign the worker, then the app explicitly; use `--deep` only for verification. The initial package is **ad-hoc signed and unnotarized**, labelled local-only. Developer ID credentials are neither inspected nor used. The stable packaged identifier is `com.kuroiokami.photo`; development retains `com.kuroiokami.photo.development`. QA may use a separate identifier for disposable preferences. Identifiers do not isolate DecisionStore's shared Application Support data.

Create a UDZO read-only compressed HFS+ disk image with Photo.app, an Applications shortcut, plain-language instructions and licenses. Verify signatures, source/version/identity metadata, app/helper architectures and deployment targets, exact file hashes, installer-guide/license hashes and actual mounted payload. The package retains the app, DMG, manifest and SHA256SUMS together. New output folders publish with an exclusive directory rename and never overwrite an existing package. The current package pipeline permits only arm64; development assembly still accepts matched arm64/x86_64 slices without claiming Intel acceptance.

## Local installation and updates

Keep `sh scripts/build-app.sh [--release]`, now backed by the shared assembler and safe installer. Development receipts explicitly identify working-tree builds and dirty state rather than claiming committed-source provenance. Installing a local app verifies a fresh sibling copy, refuses a running main/helper executable, different destination identity, links or overlapping/nested app paths, and swaps complete directories atomically. Retain the old app and its original executable inode/bytes as a named backup. A backup-naming failure retains the old app in its staging container instead of deleting it. No in-place executable overwrite, mixed old/new resources, automatic app Quit or personal data migration occurs.

The installer touches app directories only. Updates with the same identifier retain preferences; development and packaged preferences are separate. Both currently share Application Support/Photo decisions, protection and journals, so quit other Photo copies before file decisions or installation checks. Public signed apps/notarized updates and hardened-runtime preview-worker acceptance are a later milestone; this foundation's verifier/installer intentionally accepts local ad-hoc packages only.

## Validation

Portable tests exercise version/identity/path rules, pinned exports versus dirty/untracked files and tracked links, checksum failure before mounting and process-path parsing. macOS tests compile a tiny owned CLI fixture with the declared deployment target, then check real signing, complete upgrade/obsolete-file removal, retained inode/bytes, running main/helper refusal, wrong identities/links/overlap, missing/tampered content and backup failure recovery. The shared check runs these tests on macOS; repository CI also runs portable cases on Linux.

Actual disk-image/native installation/update observations, pinned source and artifact identities belong in [the tracker](../../PROJECT_STATUS.md) and [distribution guide](../DISTRIBUTION.md). No Developer ID, notarization, browser quarantine/clean-Mac, minimum-platform/Intel or public-beta acceptance is implied. Apple's [packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) and [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) guidance informs the later distribution stage.
