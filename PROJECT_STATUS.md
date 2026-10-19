# Project tracker

Last updated: 2026-10-19

This is the current handoff for humans and AI contributors. Update it in the same change as any implementation, setup, validation, or roadmap change. Read [AGENTS.md](AGENTS.md) before working. The [development plan](docs/DEVELOPMENT_PLAN.md) contains milestone acceptance criteria; architecture decisions live in `docs/decisions/`.

## Current state

Photo is a native macOS photo workflow application using SwiftUI, Swift 6 language mode, and Swift Package Manager. Phase 1 is implemented and locally checked. It is a development executable with bundled samples, not an installable release. Real-folder browsing is the next proposed milestone.

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

There is no DMG, signed app bundle, installer, or release download yet.

## How to use the current app

- The app opens a sample collection containing three synthetic gradient images.
- Click a thumbnail to select it and show its large preview.
- Use the toolbar Previous/Next controls or the left/right arrow keys to navigate. Navigation stops at the first and last image.
- Quit with Command-Q; command-line developers can also stop the process with Control-C in the launching terminal.
- The current app does not open personal folders, retain selections between launches, or modify photos or metadata.

## Features and delivery status

| Capability | Status | Notes |
| --- | --- | --- |
| Native SwiftUI macOS shell | Implemented | macOS 14+, SwiftPM executable |
| Bundled sample collection | Implemented | Three generated PNGs with recorded provenance |
| Thumbnail selection and large preview | Implemented | Bundled samples only |
| Previous/next and arrow-key navigation | Implemented | Bounded selection behavior |
| File, preview, and metadata boundaries | Interfaces only | Async Sendable read-only protocols; no real-file adapters |
| Formatting, build, and automated tests | Locally verified | Shared check script; five tests |
| GitHub Actions | Verified | [Initial run passed](https://github.com/kuroiokami/photo/actions/runs/39257940587) for `e297d22` |
| Real-folder browsing and asynchronous previews | Planned: Phase 2 | Includes error states, bounded work, and cancellation |
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

Latest local evidence, 2026-10-19: formatting, compilation, and all five Swift Testing tests passed with Apple Swift 6.4 on arm64. Tests cover initial selection and clamped navigation, invalid and cleared selection, empty collections, bundled image decoding, and sample/empty workspace rendering.

`swift run Photo` built and started successfully. Interactive thumbnail and keyboard verification remains pending because the UI automation tool could not target the bare executable. Rendering smoke tests do not establish end-to-end keyboard behavior, performance, or real-format support. The minimum macOS version and Intel architecture have not been separately exercised.

The check script discovers the selected toolchain's installed Testing macro plugin when present; this handles a Command Line Tools plugin-discovery issue. The local toolchain also emitted linker search-path warnings for absent developer framework directories; builds and tests completed successfully.

Initial remote evidence, 2026-10-19: [Swift checks run 39257940587](https://github.com/kuroiokami/photo/actions/runs/39257940587) passed on `main` for commit `e297d22`. Formatting, build, and tests completed successfully on the macOS runner. This records that specific code revision; later commits must be checked against their own runs.

## Next work and open decisions

1. Complete interactive verification of the sample app; keep subsequent CI results current.
2. Confirm Phase 2's initial supported formats and representative folder/benchmark corpus.
3. Agree on numerical responsiveness and memory targets before performance work.
4. Implement read-only folder selection, enumeration, and asynchronous thumbnail/preview adapters, then connect them to the existing workspace.
5. Test empty, unreadable, corrupt, and removed folders/files, cancellation, and preservation of source bytes.

Metadata persistence (catalog versus XMP), ratings/labels, license, and distribution requirements remain open. Do not silently treat proposed roadmap features as approved product decisions. Proposed MVP exclusions include destructive editing, cloud sync, collaboration, AI ranking, advanced search, and multi-user catalogs.

## Architecture handoff

- **PhotoCore** owns models, `WorkspaceState`, and file/preview/metadata protocols. Keep it independent of SwiftUI and AppKit.
- **PhotoUI** owns views and sample resources. Observable UI state is main-actor isolated.
- **PhotoApp** owns process startup and SwiftUI scenes.
- Production file-service adapters do not exist yet. No current operation reads user-selected files or writes metadata.

## Change log

### 2026-10-19 — Initial foundation

- Established repository conventions, development milestones, and the native macOS architecture decision.
- Added SwiftUI sample workspace, synthetic resources, service boundaries, local checks, and five tests.
- Added GitHub Actions and this maintained project tracker with AI handoff instructions.
- Local checks and the initial remote GitHub Actions run passed. Published the foundation on `main` as `e297d22`; interactive UI verification remains pending.
