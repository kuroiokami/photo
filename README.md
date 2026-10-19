# Photo

A native macOS photo browser built with SwiftUI and Swift Package Manager.

For installation, usage, feature status, planned work, and handoff evidence, see the [project tracker](PROJECT_STATUS.md). AI contributors must follow [AGENTS.md](AGENTS.md).

## Status

Photo opens JPEG, PNG and Sony ARW folders directly in a contact sheet, with fast embedded RAW previews, EXIF sorting, independent flags/stars, local persistence with XMP synchronization, and on-demand Fit/100% inspection. Background workers keep decoding, metadata and persistence away from the UI. Original image bytes and embedded metadata are never written.

Other RAW formats, HEIC, batch selection and release distribution remain planned. Reference-machine browsing targets and before/after results are recorded in the [performance report](docs/PERFORMANCE.md). Wider hardware/library coverage remains open; this is a working development build.

## Requirements and installation

- macOS 14 or newer.
- Swift 6.0 or newer with `swift format` available, using a matching Xcode or Apple Command Line Tools toolchain (`xcode-select --install` if needed).
- No external dependencies, API keys, or environment files.

```sh
git clone https://github.com/kuroiokami/photo.git
cd photo
swift run Photo
```

Quit any running Photo development app before rebuilding its bundle. To build a local app that can be opened from Finder:

```sh
sh scripts/build-app.sh
open .build/Photo.app
```

This bundle is ad-hoc signed locally and unnotarized; it is for development, not distribution. Alternatively, open `Package.swift` in Xcode and run the Photo scheme.

## Usage

- Choose **File → Open Folder…** (Command-O) or use the Open Folder button. Only the selected folder's visible regular `.jpg`, `.jpeg`, `.png`, and `.arw` files are listed, in natural filename order. Subfolders and symbolic links are excluded.
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

## Performance checks

```sh
sh scripts/benchmark.sh --folder "/path/to/photo/folder" > /tmp/photo-benchmark.json
```

This release-mode benchmark measures folder/image loading, cached navigation, indexed selection, and sampled process memory. It verifies source hashes before/after and emits aggregate statistics only. See the [report and reproducibility notes](docs/PERFORMANCE.md) for corpus limits, targets, and synthetic-folder generation. Do not interpret pipeline timing as UI frame time.

## Structure

- **PhotoCore**: workspace/metadata/decision models, read-only file enumeration, actor-isolated SQLite and preserving XMP synchronization.
- **PhotoImaging**: ImageIO property/embedded-preview reads, bounded thumbnail/fit caches and a separate on-demand Core Image detail worker.
- **PhotoUI**: contact sheet, asynchronous image views, folder picker, menu commands, and bundled samples.
- **PhotoApp**: process startup and window lifecycle.

See the [development plan](docs/DEVELOPMENT_PLAN.md), [folder-browser decision](docs/decisions/0002-read-only-folder-browser.md), and [contribution guide](CONTRIBUTING.md).

## Current limits

No recursion, live folder watching, multi-selection, other RAW/HEIC formats, destructive editing, or installable release. Fit previews are capped at 2560 pixels on their longest edge; thumbnails at 480. ARW previews can be smaller than these caps. Full detail is requested separately and limited to a single decoded image of at most 256 MiB. Cached data can remain visible after external edits until Reload. Cache limits exclude visible view images and transient decoder/OS allocations; they are not a total application memory cap.

## License

No license has been selected. Choose one before external distribution or accepting outside contributions.

## Fast culling development

The current feature branch adds Sony `.arw` (case-insensitive) embedded previews alongside JPEG/PNG. Preview badges identify actual decoded resolution. The shooting information button reveals EXIF; Sort supports capture time, ISO, shutter speed, aperture and focal length. Metadata indexes in the background; EXIF sorting waits for indexing to finish. Missing values sort last. Capture times without offsets use consistent wall-clock ordering rather than the Mac's current timezone.

### Culling decisions

Use **P** to pick, **X** to reject, **U** to clear the flag, and **0–5** for stars. Flags and stars are independent. Hold Shift to apply and advance, or enable the remembered Auto-advance checkbox. Reject never deletes a photo. Use Decisions and Edit menus for commands and Undo/Redo (Command-Z / Shift-Command-Z). Filter by flag and minimum stars; Clear Filters restores the full folder. Rating sort places highest stars first.

Decisions save in `~/Library/Application Support/Photo/decisions.sqlite` and synchronize to XMP sidecars. ARW uses `name.xmp`; JPEG/PNG uses `name.jpg.xmp`/`name.png.xmp` (other apps may not read these). Original images are untouched. Saved locally / XMP pending means the local decision is durable; Retry XMP Sync retries the sidecar. A conflict offers Use My Decisions or Use External Decisions and never silently overwrites an external edit. Normal quit waits for queued saves; sudden process termination can lose a change still marked Saving. Samples are not persisted.

The local app bundle is now **ad-hoc signed**, without a distribution certificate or notarization, so macOS can validate native panel services. It remains a development build.

### Sharpness inspection

Choose **100%** or double-click the preview to inspect around the pointer. One image pixel maps to one physical display pixel, including Retina displays. Scroll with a trackpad/wheel or drag to pan; the navigator outlines the visible region. Double-click the detail image or choose **Fit** to return. Selection changes reset to Fit.

Ordinary ARW browsing uses the embedded JPEG; its badge shows its actual resolution. **100%** explicitly requests Apple RAW rendering and displays **Rendered RAW**. Unsupported cameras, missing previews and oversized full-detail requests have recoverable states. RAW rendering support depends on macOS; embedded JPEG appearance can differ from Apple rendering. The 256 MiB limit applies to the decoded detail image, not total app/transient decoder memory. RAW histograms, focus peaking and editing are not implemented.

See the [culling design and research](docs/CULLING_DESIGN.md) and [current tracker](PROJECT_STATUS.md) for validation and interoperability limits.

For optional real-camera integration checks, set `PHOTO_RAW_TEST_FOLDER` to a disposable folder containing supported Sony ARWs when running `sh scripts/check.sh`. That test checks embedded previews, full RAW detail and unchanged source hashes. CI skips it without the environment variable; personal files are never checked into the repository.
