# 0001: Native macOS foundation

- Status: accepted
- Date: 2026-10-19

## Context

The user selected macOS, SwiftUI, and Swift Package Manager for Phase 1. The initial goal is a runnable, testable foundation for a local photo browsing and culling tool.

## Decision

Use Swift 6 language mode, macOS 14 or newer, and a dependency-free Swift package. SwiftUI supplies the application shell; AppKit handles application activation and bundled image decoding. Build and launch with `swift run Photo`.

Keep models, observable workspace state, and read-only service protocols in PhotoCore. PhotoUI owns views and bundled sample images. PhotoApp owns process and scene lifecycle. File enumeration, preview loading, and metadata reading have separate asynchronous Sendable protocols; production adapters arrive in Phase 2. This foundation performs no user-file access or metadata writes.

Use built-in `swift format` and compiler warnings as errors. The check script supplies the selected toolchain’s installed Testing macro-plugin directory when present because some Command Line Tools builds omit it from plugin discovery. A local wrapper type alias disambiguates the SwiftUI State property wrapper from the newer SDK macro of the same name. Swift Testing covers state transitions, resource decoding, and shell rendering. Run the same check script locally and on a macOS GitHub Actions runner. Require Swift 6.0 or newer with `swift format` available.

## Alternatives considered

A Tauri desktop application or browser application would enable other platforms but does not match the chosen native macOS direction. An Xcode project is unnecessary for the current SwiftPM executable; an app bundle, signing, sandbox entitlements, and distribution packaging will be addressed before release.

## Consequences

No external dependencies means no Package.resolved is generated; commit it if dependencies are introduced. SwiftPM launches a development executable rather than an installable app bundle. RAW support, metadata persistence, and numerical performance targets remain unconfirmed product decisions. CI is configured now but cannot be observed remotely until the repository is committed and pushed.

## Validation

`sh scripts/check.sh` must pass on a clean checkout. Manually launch `swift run Photo`, select sample thumbnails, and navigate with arrow keys. The automated rendering smoke test covers both sample and empty state; it does not replace a real application launch test.

## References

- [SwiftPM package and target documentation](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html)
