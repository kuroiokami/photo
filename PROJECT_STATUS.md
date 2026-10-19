# Project tracker

Last updated: 2026-10-19

This is the current handoff for humans and AI contributors. Update it in the same change as any implementation, setup, validation, or roadmap change. Read [AGENTS.md](AGENTS.md) before working. The [development plan](docs/DEVELOPMENT_PLAN.md) contains milestone acceptance criteria; architecture decisions live in `docs/decisions/`.

## Current state

Photo is a native macOS photo workflow application using SwiftUI, Swift 6 language mode, and Swift Package Manager. The Phase 2 read-only JPEG/PNG browsing slice is implemented. It opens real folders in a contact sheet with a selected preview; samples remain available. The development app bundle is unsigned and is not an installable release. The browsing slice now has paired real-camera measurements, mixed-format/large-folder validation, and reference-machine targets recorded in [PERFORMANCE.md](docs/PERFORMANCE.md). Wider hardware/camera coverage remains open. The chunk is published in [draft PR #1](https://github.com/kuroiokami/photo/pull/1) on `codex/folder-browser`; it has not been merged into `main`.

## Installation and first run

1. Use macOS 14 or newer and install Xcode or Apple Command Line Tools with Swift 6.0 or newer. For Command Line Tools, run `xcode-select --install` if they are not already installed. A full Xcode installation is optional for command-line development.
2. Confirm that the selected toolchain provides `swift --version` and `swift format --version`. If not, select or update the Apple toolchain before building.
3. Clone and enter the repository:

   ```sh
   git clone https://github.com/kuroiokami/photo.git
   cd photo
   ```

4. Build and launch:

   ```sh
   swift run Photo
   ```

There are no external package dependencies, API keys, or environment files to configure. SwiftPM generates `.build/` locally. No `Package.resolved` exists while there are no external dependencies; commit it if dependencies are introduced. Alternatively, open `Package.swift` in Xcode and run the Photo scheme.

For a native local app bundle, run `sh scripts/build-app.sh`, then `open .build/Photo.app`. This unsigned, unnotarized development bundle supports Finder launch and UI inspection. There is no DMG, signed release, installer, or release download yet.

## How to use the current app

- Launch with three synthetic samples. Choose File → Open Folder… (Command-O) or the toolbar/sidebar button to browse a real folder.
- The contact sheet includes visible regular JPEG/PNG files in that folder only, in natural filename order. No recursion or symlink following.
- Click to select; double-click to show the preview. Left/right arrows move one photo, up/down move a grid row, and Home/End select the first/last photo. Compact Mac keyboards use Fn-left/right for Home/End.
- Space toggles preview; Escape hides it. Drag the split divider to resize the preview. Use the thumbnail-size slider to adjust density.
- Command-R reloads the folder, clears caches, and retains selection if possible. There is no automatic filesystem watching; externally edited or removed cached images may remain visible until Reload.
- Errors have explicit states. Use Try Again in the preview, Reload for thumbnails/folders, or choose another folder. Cancelling the picker preserves the current collection.
- Show Sample Collection returns to bundled samples. Quit with Command-Q or stop the launching terminal with Control-C.
- Browsing does not write original image bytes or metadata. Selections and folder history are not persisted between launches.

## Features and delivery status

| Capability | Status | Notes |
| --- | --- | --- |
| Native SwiftUI macOS shell | Implemented | macOS 14+, SwiftPM executable and local dev bundle |
| Bundled sample collection | Implemented | Three generated PNGs with recorded provenance |
| Contact sheet and selected preview | Implemented | Real JPEG/PNG folders and samples; density slider and split pane |
| Keyboard navigation | Implemented and interactively checked | Arrow keys, Home/End, Space, Escape, Command-O/R |
| File and preview adapters | Implemented | Actor-based enumeration and ImageIO downsampling; EXIF orientation |
| General metadata reader/persistence | Interfaces/planned | Original dimensions shown; no metadata writes |
| Formatting, build, and automated tests | Locally verified | Shared script passed all 18 tests; extension test has eight argument cases |
| GitHub Actions | Verified for Phase 2 code | [Folder-browser run passed](https://github.com/kuroiokami/photo/actions/runs/39261955925) for `6904965` |
| Real-folder browsing and asynchronous previews | Implemented | Separate serial decode lanes, LRU caches, session cancellation, retry |
| Reference-machine performance targets | Verified | 17 real 50 MP JPEGs, 2,000 mixed JPEG/PNG files, 50,000-item selection stress; see performance report |
| Ratings, flags, filtering, undo, persistence | Planned: Phase 3 | Metadata ownership and semantics need decisions |
| Broader format support and performance validation | Planned: Phase 4 | No RAW/HEIC/color-management claims yet |
| Accessibility review and release packaging | Planned: Phase 4 | Signing and distribution not implemented |

## Checks and validation evidence

Run the same checks as CI:

```sh
sh scripts/check.sh
```

Format Swift sources before checking:

```sh
sh scripts/format.sh
```

Phase 2 local evidence, 2026-10-19: `sh scripts/check.sh` passed formatting, compilation, and all 13 tests in the actual repository with Apple Swift 6.4 on arm64. This includes retry after restoring read permission. Coverage includes initial/invalid/cleared selection, clamped navigation, empty collections, natural sorting and filtering, late folder results, sample reset during a pending load, selection restoration, removed folders, image decoding/orientation, source-byte preservation, cancellation, and cache budgets.

Native UI inspection using a local development `.app` verified selection/scroll retention on Reload, grid focus after picker cancellation, and launch, Command-O folder selection, immediate arrow-key navigation after launch/folder load, scrolling to the final item with End, corrupt-file error presentation, empty-folder state without stale previews, picker cancellation preserving the collection, Command-R error recovery for a moved folder, return to samples, and the accessible thumbnail-size increment action. The disposable collection held 240 synthetic PNGs and one corrupt JPEG. UI testing found and fixed lost focus after folder loading and split-pane resets. This is functional evidence, not a real-camera performance benchmark. Minimum macOS version, Intel architecture, and production-size libraries remain untested.

The check script discovers the selected toolchain's installed Testing macro plugin when present; this handles a Command Line Tools plugin-discovery issue. The local toolchain also emitted linker search-path warnings for absent developer framework directories; builds and tests completed successfully.

Phase 2 remote evidence, 2026-10-19: [Swift checks run 39261955925](https://github.com/kuroiokami/photo/actions/runs/39261955925) passed on `codex/folder-browser` for implementation commit `6904965`, including all 13 tests. [Draft PR #1](https://github.com/kuroiokami/photo/pull/1) contains the reviewable chunk. Later documentation-only commits record this observed code-revision result; inspect their own checks before merging.

Historical initial remote evidence, 2026-10-19: [Swift checks run 39257940587](https://github.com/kuroiokami/photo/actions/runs/39257940587) passed on `main` for commit `e297d22`. Formatting, build, and tests completed successfully on the macOS runner. This records that specific code revision; later commits must be checked against their own runs.

## Performance validation follow-up — 2026-10-19

The user reported that their real folder generally worked and authorized measurement, fixes, and merge of PR #1. The current check script passes all 18 tests, including eight Unicode filename/extension variants. Paired release runs found and fixed redundant same-image decoding and linear selection scans. Image workers now persist across sessions, temporary decoder objects have local autorelease pools, and cached previews bypass the cold-load debounce.

Median real-camera results across three alternating runs: concurrent identical previews 1628.8 → 203.1 ms, selection lookup p95 7.1260 → 0.0009 ms in a virtual 50,000-item collection, and sampled CLI peak RSS 531.2 → 418.6 MiB. All source hashes matched. The 2,000-file folder loaded below the local 250 ms target; individual cold 50 MP previews remained about 0.24 seconds. See [aggregate evidence and limits](docs/PERFORMANCE.md).

The rebuilt native app loaded a temporary mixed folder containing copies of 17 real-camera JPEGs plus six generated PNGs with Unicode names and `.jpg`/`.jpeg`/uppercase/mixed-case variants. Rapid navigation, portrait preview, and selection retention on Reload passed. The native app also opened and scrolled the 2,000-file mixed corpus. Its sampled debug RSS ranged from 216.9 to 312.3 MiB, ending at 296.1 MiB; this is not a matched-lifetime comparison with the earlier native sample. UI testing found and fixed selected-tile visibility after preview/grid reflow. The final native check kept photo 2,000 visible after hiding/reopening the preview. Grid reflow now coalesces intermediate layouts and reveals the selected item after layout settles. Latest remote CI and PR merge status remain pending. Preserve the pre-existing local edit in `docs/DEVELOPMENT_PLAN.md`; it is unrelated to this change and must not be included in the commit.

## Next work and open decisions

1. Finish final rebuilt-app validation and review/merge [PR #1](https://github.com/kuroiokami/photo/pull/1) after its updated checks pass. Keep the reference-machine benchmarks current as the corpus grows.
2. Decide supported RAW/HEIC formats and the next preview/zoom capabilities.
3. Confirm ratings/labels and catalog-versus-XMP ownership before Phase 3 persistence work.
4. Broaden accessibility, large-folder, minimum-macOS, and Intel verification; design distribution signing/sandbox behavior before release.

No live folder watching, recursion, multi-selection, 1:1 zoom, RAW/HEIC decoding, persistent catalogs, ratings, or metadata writes are implemented. Decoded caches are capped at 24 MiB (thumbnails) and 64 MiB (previews); visible image views and transient decoder/OS allocations are additional. Persistent per-window workers limit decode work to one thumbnail plus one preview at a time, including across folder switches; cancellation is cooperative around filesystem/ImageIO calls.

License and distribution requirements remain open. Proposed MVP exclusions remain destructive editing, cloud sync, collaboration, AI ranking, advanced search, and multi-user catalogs.

## Architecture handoff

- **PhotoCore** owns models, `WorkspaceState`, asynchronous read-only protocols, and shallow local file enumeration. Keep it independent of SwiftUI and AppKit.
- **PhotoImaging** owns ImageIO adapters, immutable decoded images, serial work lanes, and LRU caches. The preview protocol now has an associated Sendable result type; no external API consumers or data migrations exist.
- **PhotoUI** owns views and sample resources. Observable UI state is main-actor isolated.
- **PhotoApp** owns process startup and SwiftUI scenes.
- File reads are implemented; metadata writes and persistence are not. Folder generations and view cancellation reject superseded results. See decision 0002 for cache and UI boundaries.

## Change log

### 2026-10-19 — Real-camera validation and tuning

- Added repeatable release benchmarks, aggregate-only evidence, local regression targets, and original-byte hash verification.
- Removed redundant concurrent decoding, bounded temporary decoder retention, reused workers across folder sessions, bypassed cached-preview debounce, and indexed selection off the main actor.
- Passed all 18 tests, including eight extension/case variants, and verified native real/mixed/large-folder interactions. Fixed selected-thumbnail visibility when grid geometry changes. Remote checks and merge status are tracked above.


### 2026-10-19 — Read-only folder browsing

- Added shallow JPEG/PNG folder browsing, cancellation-safe folder sessions, natural sorting, EXIF-oriented downsampling, and separate bounded image caches.
- Replaced the sample filmstrip with a Photo Mechanic-informed contact sheet, density slider, resizable preview, native menu actions, keyboard navigation, and recoverable errors.
- Added a local development app bundle helper; local checks passed all 13 tests and the native interactions listed above were verified. Real-camera performance budgets remain open.
- Published implementation commit `6904965` in [draft PR #1](https://github.com/kuroiokami/photo/pull/1); its [remote CI run](https://github.com/kuroiokami/photo/actions/runs/39261955925) passed. This chunk is not merged into `main`.


### 2026-10-19 — Initial foundation

- Established repository conventions, development milestones, and the native macOS architecture decision.
- Added SwiftUI sample workspace, synthetic resources, service boundaries, local checks, and five tests.
- Added GitHub Actions and this maintained project tracker with AI handoff instructions.
- Local checks and the initial remote GitHub Actions run passed. Published the foundation on `main` as `e297d22`; interactive UI verification remains pending.
