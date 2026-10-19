# Photo

A native macOS photo browser built with SwiftUI and Swift Package Manager.

For installation, usage, feature status, planned work, and handoff evidence, see the [project tracker](PROJECT_STATUS.md). AI contributors must follow [AGENTS.md](AGENTS.md).

## Status

The Phase 2 browsing slice opens real folders of JPEG and PNG images in a contact sheet with an adjustable thumbnail grid and resizable preview pane. Loading runs away from the main actor with cancellation and bounded decoded-image caches. Original images and metadata are never written.

Ratings, RAW/HEIC support, persistent catalogs, and release distribution are planned. Real-camera performance budgets and benchmarks remain open; this is a working development build.

## Requirements and installation

- macOS 14 or newer.
- Swift 6.0 or newer with `swift format` available, using a matching Xcode or Apple Command Line Tools toolchain (`xcode-select --install` if needed).
- No external dependencies, API keys, or environment files.

```sh
git clone https://github.com/kuroiokami/photo.git
cd photo
swift run Photo
```

For a local development app bundle that can be opened from Finder and inspected by UI automation:

```sh
sh scripts/build-app.sh
open .build/Photo.app
```

This bundle is unsigned and unnotarized; it is for local development, not distribution. Alternatively, open `Package.swift` in Xcode and run the Photo scheme.

## Usage

- Choose **File → Open Folder…** (Command-O) or use the Open Folder button. Only the selected folder's visible regular `.jpg`, `.jpeg`, and `.png` files are listed, in natural filename order. Subfolders and symbolic links are excluded.
- Click a thumbnail to select it. Left/right arrows move one photo; up/down arrows move one grid row. Home/End select the first/last image. On compact Mac keyboards, Fn-left/right provide Home/End.
- Space toggles the preview; Escape hides it. Double-clicking a thumbnail shows it. Drag the split divider to resize the contact sheet and preview.
- Adjust the thumbnail-size slider to change grid density. Click a thumbnail to return keyboard focus to the grid after using another control.
- **File → Reload Folder** (Command-R) rescans the folder, clears cached images, and preserves the selection if the file still exists. Filesystem changes are not watched automatically.
- Damaged, unreadable, or removed images show an error instead of blocking navigation. The preview provides **Try Again**; Reload also retries thumbnails. Folder failures offer Reload or another folder choice.
- **Show Sample Collection** returns to three bundled synthetic images. Quit with Command-Q.

## Development checks

```sh
sh scripts/format.sh
sh scripts/check.sh
```

The shared local/CI script checks formatting, compiles in Swift 6 language mode with warnings as errors, and runs the test suite. No `Package.resolved` exists without external dependencies; commit it when dependencies are introduced.

## Structure

- **PhotoCore**: models, observable workspace state, cancellation-safe folder sessions, and read-only file enumeration.
- **PhotoImaging**: ImageIO decoding, orientation handling, separate serial thumbnail/preview lanes, and cost-bounded caches.
- **PhotoUI**: contact sheet, asynchronous image views, folder picker, menu commands, and bundled samples.
- **PhotoApp**: process startup and window lifecycle.

See the [development plan](docs/DEVELOPMENT_PLAN.md), [folder-browser decision](docs/decisions/0002-read-only-folder-browser.md), and [contribution guide](CONTRIBUTING.md).

## Current limits

No recursion, live folder watching, multi-selection, 1:1 zoom, RAW/HEIC support, metadata writes, or persistence. Selected previews are capped at 2560 pixels on their longest edge; thumbnails at 480. Cached data can remain visible after external edits until Reload. Cache limits exclude visible view images and transient decoder/OS allocations; they are not a total application memory cap.

## License

No license has been selected. Choose one before external distribution or accepting outside contributions.
