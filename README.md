# Photo

A native macOS photo browser built with SwiftUI and Swift Package Manager.

For installation, usage, feature status, planned work, and handoff evidence, see the [project tracker](PROJECT_STATUS.md). AI contributors must follow [AGENTS.md](AGENTS.md).

## Status

Photo opens JPEG, PNG, Sony ARW, Canon CR2/CR3/CRW and Olympus/OM System ORF folders directly in a contact sheet, with fast embedded RAW previews, EXIF sorting, independent flags/stars, local persistence with XMP synchronization, and on-demand Fit/100% inspection. Background workers keep decoding, metadata and persistence away from the UI. Original image bytes and embedded metadata are never written.

The Workflow panel adds verified dual-destination ingest, multi-selection and RAW+JPEG grouping, reviewed bulk rename/Undo, IPTC presets and hierarchical keywords, and a Lightroom Classic handoff. See the [workflow guide](docs/WORKFLOW.md) for usage, recovery and verified camera coverage. Other RAW formats, HEIC and release distribution remain planned. Reference-machine browsing targets and before/after results are recorded in the [performance report](docs/PERFORMANCE.md). Wider hardware/library coverage remains open; this is a working development build.

The current follow-up adds pinned comparison, selected-only review, optional EXIF labels, automatic verified ingest arrivals and persistent metadata batch Undo/Redo. Delivery status is recorded in the tracker. See the [Photo Mechanic review](docs/PHOTO_MECHANIC_REVIEW.md) for adopted interactions and the prioritized remaining work.

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
sh scripts/build-app.sh --release
open .build/Photo.app
```

Omit `--release` for a faster debug build when developing. Use `--release` when judging browsing responsiveness.

This bundle is ad-hoc signed locally and unnotarized; it is for development, not distribution. Alternatively, open `Package.swift` in Xcode and run the Photo scheme.

## Usage

- Choose **File → Open Folder…** (Command-O) or use the Open Folder button. Only the selected folder's visible regular `.jpg`, `.jpeg`, `.png`, `.arw`, `.cr2`, `.cr3`, `.crw`, and `.orf` files are listed, in natural filename order. Expand a sidebar arrow and click a subfolder to display its images. Opened roots and the last folder survive restarts until you remove the sidebar shortcut; removing it leaves files on disk. Symbolic links and hidden directories are excluded.
- Click a thumbnail to select it. ⌘-click adds/removes individual photos; Shift-click or Shift-arrow extends a range from its anchor. Drag a rectangle across visible thumbnails to select a group (⌘/Shift adds; no edge auto-scroll). Use the selection flag buttons or P/X/U to flag them together, preserving stars. ⌘A selects all, ⌘D deselects, ⇧⌘O inverts, T toggles picks and ⌘T selects visible picks. Left/right arrows move one photo; up/down arrows move one grid row. Home/End select the first/last image. On compact Mac keyboards, Fn-left/right provide Home/End.
- **Preview** shows a large image above a horizontal bottom filmstrip. **Contact Sheet** shows the full thumbnail grid; use the segmented control or Space to switch. Escape returns to the contact sheet. Double-clicking a thumbnail opens Preview. The shooting-information toggle opens a separate right-hand pane.
- Adjust the thumbnail-size slider to change filmstrip or grid density; each view retains its own size for the current session. In the filmstrip, arrows move one photo and Shift-arrows extend selection. Scroll horizontally with a trackpad or the scrollbar; the focused photo is revealed automatically. Click a thumbnail to return keyboard focus to the grid after using another control.
- **File → Reload Folder** (Command-R) rescans the folder, clears cached images, and preserves the selection if the file still exists. Filesystem changes are not watched automatically.
- Damaged, unreadable, or removed images show an error instead of blocking navigation. The preview provides **Try Again**; Reload also retries thumbnails. Folder failures offer Reload or another folder choice.
- **Show Sample Collection** returns to three bundled synthetic images. Quit with Command-Q.

## Ingest, organize and hand off

Open **Workflow…** in the toolbar. Ingest a card to separate working/backup roots with a job folder; each copy is SHA-256 verified. Use **Continue Browsing** during ingest and **Reload** for arrivals. Browse individual card subfolders. The backup is an ingest snapshot; later edits require your normal backup system.

Command/Shift-click select multiple thumbnails; Command-A selects all visible photos. Enable **RAW+JPEG** to represent a unique same-stem pair as one item and apply decisions to both files. Batch decisions undo together.

In **Bulk Rename**, choose Selection/Visible/All files, set a naming template and sequence, then **Preview Names** before **Apply Reviewed Rename**. Paired images and matching XMP/ACR companions follow together. Rename before Lightroom import; after import use Lightroom's rename/move commands.

In **IPTC & Keywords**, check fields to apply; blank unchecked fields stay untouched. **Clear** is explicit. Preview changes before applying. Save layered author/shoot/subject presets. Use keyword Append/Replace/Remove/Clear; `Wildlife|Birds|Heron` records a hierarchy and its leaf keyword.

**Lightroom** prepares an optional verified copy of non-rejected photos and companions. Its JPEG/PNG copies can embed prepared metadata without recompressing pixels; original library bytes stay untouched. In Lightroom Classic, import that folder with **Add**. Actual Lightroom application round trips remain unverified. Follow the [workflow guide](docs/WORKFLOW.md) before working on an existing catalog.

### Batch IPTC and discoverability

Select your photos, then press **⌘I** (or I / ⌘K) for IPTC & Keywords. Values come from the first selected photo in contact-sheet order. Edit a field such as Copyright notice, then click its **Preview Field** button to preview only that field across the target set. Review the before/after values and click **Apply Reviewed Fields**. Other fields retain each photo's values. Typing automatically checks a field for the combined preview; **Clear** explicitly removes a value. Applying metadata keeps the group selected. RAW+JPEG grouping expands targets to both files; the editor shows the physical target count.

**⌘G** opens Ingest and **M** opens Bulk Rename. ⌘M remains macOS Minimize. Hover over controls for explanations; choose **Help → Photo Quick Start & Shortcuts** or the sidebar Quick Start button for an optional guide. Browser shortcuts yield to native text editing while the workflow panel is open. See the [workflow review and remaining gaps](docs/PHOTO_MECHANIC_REVIEW.md).

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

To measure EXIF/decision indexing and first-preview latency while indexing runs:

```sh
sh scripts/benchmark.sh --workspace "/path/to/photo/folder" > /tmp/photo-workspace.json
```

The workspace mode uses a fresh temporary SQLite database and never writes input images or sidecars. It records initial/repeat decision loading, EXIF indexing, ISO/rating sorting and a sampled main-actor timer gap. The gap includes scheduler delays and is not frame time.

For a read-only full-detail comparison (three passes, aggregate statistics only):

```sh
sh scripts/benchmark.sh --detail "/path/to/photo/folder" --baseline > /tmp/detail-before.json
sh scripts/benchmark.sh --detail "/path/to/photo/folder" > /tmp/detail-after.json
```

The baseline includes the old deferred image's first viewport draw; its offscreen pixels may remain deferred, so only the progressive run reports full completion. Run the commands sequentially without other heavy work; process initialization and shared OS caches affect results. See the performance report for measured evidence and memory limits.

The original release-mode benchmark measures folder/image loading, cached navigation, indexed selection, and sampled process memory. It verifies source hashes before/after and emits aggregate statistics only. See the [report and reproducibility notes](docs/PERFORMANCE.md) for corpus limits, targets, and synthetic-folder generation. Do not interpret pipeline timing as UI frame time.

## Structure

- **PhotoCore**: workspace/metadata/decision models, read-only file enumeration, actor-isolated SQLite and preserving XMP synchronization.
- **PhotoImaging**: ImageIO property/embedded-preview reads, bounded thumbnail/fit caches and a separate on-demand Core Image detail worker.
- **PhotoUI**: contact sheet, asynchronous image views, folder picker, menu commands, and bundled samples.
- **PhotoApp**: process startup and window lifecycle.

See the [development plan](docs/DEVELOPMENT_PLAN.md), [folder-browser decision](docs/decisions/0002-read-only-folder-browser.md), and [contribution guide](CONTRIBUTING.md).

## Current limits

No recursive photo collection, live folder watching, additional RAW formats beyond those listed above, HEIC, destructive editing, or installable release. Multi-selection and clickable subfolder navigation are implemented. Fit previews are capped at 2560 pixels on their longest edge; thumbnails at 480. ARW previews can be smaller than these caps. Full detail is requested separately and limited to a single decoded image of at most 256 MiB. Cached data can remain visible after external edits until Reload. Cache limits exclude visible view images and transient decoder/OS allocations; they are not a total application memory cap.

## License

No license has been selected. Choose one before external distribution or accepting outside contributions.

## Fast culling development

The current feature branch adds Sony `.arw` (case-insensitive) embedded previews alongside JPEG/PNG. Preview badges identify actual decoded resolution. The shooting information button reveals EXIF; Sort supports capture time, ISO, shutter speed, aperture and focal length. Metadata indexes in the background; EXIF sorting waits for indexing to finish. Missing values sort last. Capture times without offsets use consistent wall-clock ordering rather than the Mac's current timezone.

### Culling decisions

Use **P** to pick, **X** to reject, **U** to clear the flag, and **0–5** for stars. Flags and stars are independent. Hold Shift to apply and advance, or enable the remembered Auto-advance checkbox. Reject never deletes a photo. Undo history is per folder session and resets on Reload/new folder. Use Decisions and Edit menus for commands and Undo/Redo (Command-Z / Shift-Command-Z). Filter by flag and minimum stars; Clear Filters restores the full folder. Rating sort places highest stars first.

Decisions save in `~/Library/Application Support/Photo/decisions.sqlite` and synchronize to XMP sidecars. Supported RAW formats use `name.xmp`; JPEG/PNG uses `name.jpg.xmp`/`name.png.xmp` (other apps may not read these). Original images are untouched. Saved locally / XMP pending means the local decision is durable; Retry XMP Sync retries the sidecar. A conflict offers Use My Decisions or Use External Decisions and never silently overwrites an external edit. Normal quit waits for queued saves; sudden process termination can lose a change still marked Saving. Samples are not persisted.

The local app bundle is now **ad-hoc signed**, without a distribution certificate or notarization, so macOS can validate native panel services. It remains a development build.

### Sharpness inspection

Choose **100%** or double-click the preview to inspect around the pointer. One image pixel maps to one physical display pixel, including Retina displays. Scroll with a trackpad/wheel or drag to pan; the navigator outlines the visible region. Click the overview to center there, or drag its white frame without losing your grab position. While the navigator is focused, arrows pan a quarter view, Shift-arrows pan a full view, and Home/End jump to opposite corners. Its accessible actions also pan or center the image. Double-click the detail image or choose **Fit** to return. Selection changes reset to Fit. For RAWs, genuine 100% focus detail appears around the zoom point first, then the full image finishes in the background at the same quality. The ready region is labeled; surrounding pixels remain black while loading. Pan position is preserved as the full image arrives. **Cancel** returns immediately to Fit and cancels subsequent work; an in-progress Apple render call finishes before the worker can stop.

Ordinary ARW browsing uses the embedded JPEG; its badge shows its actual resolution. **100%** explicitly requests Apple RAW rendering and displays **Rendered RAW**. Unsupported cameras, missing previews and oversized full-detail requests have recoverable states. RAW rendering support depends on macOS; embedded JPEG appearance can differ from Apple rendering. The combined 256 MiB limit covers the decoded full image plus its temporary focus region, not total app/transient decoder memory. RAW histograms, focus peaking and editing are not implemented.

See the [culling design and research](docs/CULLING_DESIGN.md) and [current tracker](PROJECT_STATUS.md) for validation and interoperability limits.

For optional real-camera integration checks, set `PHOTO_RAW_TEST_FOLDER` to a disposable folder containing supported RAW files when running `sh scripts/check.sh`. That test checks every supported RAW directly inside the supplied folder for embedded previews, full RAW detail and unchanged source hashes; it does not recurse. CI skips it without the environment variable; personal files are never checked into the repository.

## Compare and review

In Preview, choose **Compare** (**C**) to pin a reference beside the active photo. Arrows move the active photo; **G** pins it, **L** links Fit/100% and normalized pan, and **O** returns to Single Image. Decisions follow the thumbnail selection. Photo changes return both panes to Fit. Comparison can retain two 256 MiB detail images; normal viewing retains one.

Select a burst, then choose **Review Selection** to freeze that shortlist while rating individual photos. **End Selected Review** restores the full collection. Existing filters still apply. The **Labels** menu adds up to two remembered EXIF rows beneath filenames using already indexed metadata.

During Photo ingest, verified image families appear automatically in the currently browsed destination folder. Other source changes still require Reload. In **Workflow → IPTC & Keywords**, explicit **Undo Metadata Batch** / **Redo Metadata** controls reverse only the fields/keywords owned by a reviewed batch, preserving other values. The latest 20 batches survive restart. See the [workflow guide](docs/WORKFLOW.md) for conflict and recovery behavior.
