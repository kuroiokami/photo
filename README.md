# Photo

A native macOS photo workflow application built with SwiftUI and Swift Package Manager.

For installation, usage, feature status, planned work, and the latest handoff, see the [project tracker](PROJECT_STATUS.md). AI contributors must follow [AGENTS.md](AGENTS.md).

## Status

Phase 1 foundation: a runnable sample workspace with three bundled synthetic images, selectable thumbnails, a large preview, and previous/next controls with arrow-key shortcuts. Opening real folders, RAW decoding, culling metadata, and persistence are planned for later phases.

## Requirements

- macOS 14 or newer.
- Swift 6.0 or newer with `swift format` available. Install a matching Xcode or Apple Command Line Tools toolchain.
- No external package dependencies or credentials.

## Run

For a fresh checkout:

```sh
git clone https://github.com/kuroiokami/photo.git
cd photo
```

From the repository root:

```sh
swift run Photo
```

Select a thumbnail or use the left/right arrow keys to navigate. Close the window and quit Photo using Command-Q. This launches a development executable; signed app-bundle distribution comes later.

You can also open `Package.swift` in Xcode and run the Photo scheme.

## Development checks

```sh
sh scripts/check.sh
```

This runs formatting checks, compilation with warnings as errors, and the test suite. Swift 6 language mode provides concurrency checking. To format code:

```sh
sh scripts/format.sh
```

CI runs the same check script on a macOS runner. Because the package has no external dependencies, SwiftPM does not generate `Package.resolved`. Commit that lockfile when dependencies are introduced.

## Structure

- **PhotoCore**: photo models, observable selection state, and asynchronous read-only file, preview, and metadata service interfaces.
- **PhotoUI**: SwiftUI workspace and bundled synthetic sample images.
- **PhotoApp**: application entry point and window lifecycle.
- **Tests**: selection behavior, image decoding, and sample/empty workspace rendering smoke tests.

See the [development plan](docs/DEVELOPMENT_PLAN.md), [architecture decision](docs/decisions/0001-native-macos-foundation.md), and [contribution guide](CONTRIBUTING.md).

## Validation limits

The render smoke test exercises the SwiftUI shell; manual launch remains the check for native window behavior and keyboard interaction. Synthetic fixtures do not establish real-photo performance or format support. Phase 0 product decisions about metadata, formats, and performance budgets remain open.

## File safety and privacy

The current sample workspace only reads bundled resources. It does not access personal photo libraries or write image metadata. Keep local photo libraries, catalogs, secrets, and generated previews out of Git.

## License

No license has been selected. Choose one before external distribution or accepting outside contributions.
