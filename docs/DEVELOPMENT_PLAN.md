# Development plan

## Planning baseline

The initial repository foundation is in place; the full product brief has not been established. The working hypothesis is a local-first photo browser and culling tool. Treat the workflows below as a proposed starting point, not approved product requirements. The user selected native macOS with SwiftUI and Swift Package Manager. Phase 1 targets macOS 14+ in Swift 6 language mode. Database and metadata persistence choices remain open.

## Phase 0 — Confirm the product and technical constraints

- Define the primary user and the single workflow the first release should improve.
- Confirm whether the first release targets macOS, another desktop platform, or the web.
- Prioritize formats: JPEG, RAW previews, HEIC, and sidecars require distinct support decisions.
- Decide whether ratings and labels live in an application catalog, XMP sidecars, or both.
- Define offline behavior, library size, privacy, and accessibility expectations.
- Establish a representative benchmark corpus and measurable targets for folder opening, preview latency, scrolling, and memory use.
- Choose a license and document any third-party codec obligations.

**Exit criteria:** a short agreed product brief, explicit MVP exclusions, measurable performance targets, and an architecture decision covering the platform and stack.

## Phase 1 — Create a runnable foundation

Implementation: native SwiftUI sample workspace, PhotoCore/PhotoUI/PhotoApp modules, bundled synthetic PNG fixtures, Swift Testing, built-in formatting, and a shared local/CI check script. See [decision 0001](decisions/0001-native-macos-foundation.md). [Initial remote CI passed](https://github.com/kuroiokami/photo/actions/runs/39257940587) for foundation commit `e297d22`; initial UI verification was pending at that revision; native Phase 2 verification is recorded in the project tracker.

- Scaffold the chosen stack with one documented development command.
- Add formatting, linting, and type checking where supported.
- Add CI using the selected runtime and lockfile; run the same checks locally and in CI.
- Create a minimal application shell and a small synthetic or licensed fixture set.
- Define boundaries for file access, preview generation, metadata, and UI state.

**Exit criteria:** a fresh checkout can install, launch, and pass documented checks; CI passes; a smoke test covers the application shell.

## Phase 2 — Deliver the first vertical slice

Implemented browsing slice: native folder picker and Command-O, shallow read-only JPEG/PNG enumeration, natural filename order, lazy contact sheet with a density slider, resizable preview, keyboard navigation, asynchronous ImageIO lanes, bounded caches, cancellation, and recoverable errors. See [decision 0002](decisions/0002-read-only-folder-browser.md).

[Final CI passed](https://github.com/kuroiokami/photo/actions/runs/39268234733) for the tuned implementation; [PR #1](https://github.com/kuroiokami/photo/pull/1) was merged into `main` as `24b7cff`. Native folder, navigation, failure, reload, and grid-reflow checks are recorded in the project tracker.

The reference-machine browsing slice passed its recorded real-camera and mixed-folder targets; see [PERFORMANCE.md](PERFORMANCE.md) for paired results, original-byte verification, memory measurements, and reproducibility. Broader hardware/camera/network/removable-media validation remains future work.

- Enumerate supported files without modifying their contents.
- Generate previews asynchronously with cancellation and bounded concurrency.
- Virtualize large thumbnail collections and bound the preview cache.
- Handle empty folders, unreadable files, corrupt images, and folders removed during browsing.
- Show useful loading, error, and retry states.

**Exit criteria:** the complete workflow works against the benchmark corpus, source files remain unchanged, and the agreed responsiveness and memory targets are met.

## Phase 3 — Add culling and persistence

- Confirm rating, flag, and label semantics before implementing controls.
- Add keyboard shortcuts, filtering, undo, and durable state.
- Implement the agreed catalog or sidecar policy with safe writes and conflict handling.
- Verify restart recovery, read-only folders, interrupted writes, and external metadata edits.

**Exit criteria:** selections survive restart, undo works, metadata round-trips correctly, and failed writes cannot corrupt originals or existing sidecars.

## Phase 4 — Harden and prepare a first release

- Test representative formats, orientations, color profiles, Unicode paths, and large folders.
- Review keyboard navigation, focus behavior, and screen-reader labels.
- Profile bottlenecks against the recorded performance targets.
- Add packaging, versioning, release notes, and signing if required by the target platform.
- Document supported formats, known limitations, recovery procedures, and installation.

**Exit criteria:** a clean-machine installation succeeds, critical workflows pass, benchmark results are recorded, and release limitations are documented.

## Proposed MVP exclusions

Confirm these during Phase 0: destructive editing, cloud sync, collaboration, AI ranking, advanced search, and multi-user catalogs.

## Testing approach

Use unit tests for metadata and state rules, integration tests for file operations and recovery, and a small end-to-end suite for the primary workflow. Measure performance with a reproducible corpus. Keep originals read-only in tests and verify content hashes around workflows that should not change files.

## First actionable backlog

- [ ] Agree on the product brief and first target platform.
- [ ] Define supported formats and metadata ownership.
- [x] Set reference-machine performance budgets and prepare real-camera/mixed benchmark fixtures.
- [x] Select the stack and record the rationale.
- [ ] Select a license.
- [x] Scaffold the application and CI (initial remote run passed).
- [x] Implement the read-only JPEG/PNG folder-to-preview vertical slice.
- [x] Verify reference-machine real-camera and mixed-folder performance for the browsing slice.
- [ ] Broaden performance coverage across hardware, cameras, and storage media.

Revisit this plan after each phase; defer additional features until the current exit criteria are met.

## Accepted fast-culling milestones — 2026-10-19

The user confirmed Sony ARW first and local decisions plus XMP, in this order. These approved milestones refine the earlier proposed scope.

1. **RAW/EXIF:** embedded-only Sony ARW contact sheet/preview, actual preview provenance/resolution, selected-priority EXIF indexing, numeric metadata sorting with missing values last and identity-preserving selection. Implemented in the feature branch.
2. **Decisions:** independent flags/stars, keyboard and visible controls, filters, rating ordering, one-step auto-advance, Undo/Redo, durable SQLite, preserving atomic XMP sync, visible errors/conflicts and replacement-file protection. Implemented; direct Lightroom interoperability is not yet verified.
3. **Detail:** explicit Fit/physical-pixel 100%, focal double-click, pan and navigator, separate full-detail worker, on-demand Apple RAW rendering, 256 MiB decoded-image limit and reset on selection. Implemented; broader camera/hardware/OS coverage remains open.

Acceptance evidence and actual checks belong in PROJECT_STATUS.md and docs/PERFORMANCE.md. Additional RAW formats, RAW+JPEG pairing and batch organization are implemented in the accepted workflow follow-up below. Future work includes wider camera coverage, focus/exposure tools, accessibility/platform validation, and release signing/distribution.


## Reliability acceptance follow-up — 2026-10-19

- [x] Add repeatable large-folder EXIF/decision/first-preview measurement with isolated storage.
- [x] Measure and remove unbounded per-photo ARW directory scans; retain collision/replacement protections and FULL local durability.
- [x] Verify every provided ARW, orientation handling, source hashes and full detail; current corpus covers nine ILCE-7CR files only.
- [x] Cover external-rating reorder, stale metadata sessions and corrupt-detail recovery with regressions.
- [ ] Bring first-open RAW preview/thumbnail latency within target, including decoder initialization while indexing runs.
- [ ] Add other Sony models, real diverse EXIF at large scale, native frame-time measurements and other storage media.
- [ ] Verify application-level Lightroom round trips in an isolated catalog; the prior import UI attempt remains unverified.

Record exact counts, timings, native checks and CI evidence in PROJECT_STATUS.md and PERFORMANCE.md. Existing release/signing, minimum-macOS/Intel and licensing limits remain open.

## Accepted ingest/metadata/camera follow-up — 2026-10-19

- [x] Case-insensitive Canon CR2/CR3/CRW and Olympus/OM System ORF recognition; embedded-only Fit and deliberate Apple RAW detail. Real CR2/CR3/ORF samples verified; real CRW remains acceptance work.
- [x] Recursive two-destination ingest with streaming checksums, durable incremental/original-name evidence, collision protection and background culling; manual Reload for arrivals.
- [x] Multi-selection and unique RAW+JPEG representation with independent per-file decision persistence and batch Undo.
- [x] Reviewed token-based bulk naming, companions, collision checks, original-name journals, Undo and interrupted-operation recovery.
- [x] Explicit layered IPTC presets, separate created/shown locations, keyword actions/hierarchies, pending local intent, preserving XMP and conflict handling.
- [x] Optional verified non-reject handoff including XMP/ACR and metadata embedding only in derived JPEG/PNG copies; manual Lightroom Add instructions.
- [x] Profile CR3 startup and bypass the measured slow ImageIO container path with a bounded embedded-JPEG reader; retain unknown-layout fallback.
- [ ] Verify Lightroom application round trips, real CRW/broader camera modes, and removable/network storage interruption scenarios.
- [ ] Add live arrivals, full keyword dictionary import/export/synonyms, automatic ingest metadata/naming presets, metadata Undo and clock correction if prioritized.

Implemented is distinct from complete release acceptance: keep first-open latency, actual interoperability and minimum-platform coverage explicit in the tracker. Preserve existing image bytes, use disposable copies for all mutation tests, and update evidence with every delivery.

## Accepted folder and batch usability follow-up — 2026-10-19

- [x] Merge existing fast-culling and ingestion/metadata work into main, retaining validation evidence.
- [x] Persist opened folder shortcuts and last selection; lazily expand and browse subfolders; explicit removal never deletes files.
- [x] Stable range/additive selection, Shift-arrow, visible batch flags, viewport rectangle selection and contextual metadata access.
- [x] Preview a single IPTC field from the first selected photo across a group, preserve all other fields and retain selection after applying.
- [x] Adopt appropriate Photo Mechanic shortcuts, native tooltips and optional Quick Start help; document deliberate shortcut differences.
- [x] Audit current Camera Bits documentation and record prioritized gaps in PHOTO_MECHANIC_REVIEW.md.
- [ ] Add first-use walkthrough, rectangle edge auto-scroll, mixed-value summaries and metadata Undo if prioritized.

Test and delivery outcomes are tracked in PROJECT_STATUS.md; the existing Lightroom, latency and release acceptance limits remain open.
