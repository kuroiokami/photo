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

[Remote CI passed](https://github.com/kuroiokami/photo/actions/runs/39261955925) for implementation commit `6904965`; [draft PR #1](https://github.com/kuroiokami/photo/pull/1) is open for review. Native folder, navigation, failure, and reload checks are recorded in the project tracker.

Performance acceptance remains open: agree on a real-camera benchmark corpus and numerical targets before declaring the entire phase complete.

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
- [ ] Set numeric performance budgets and prepare benchmark fixtures.
- [x] Select the stack and record the rationale.
- [ ] Select a license.
- [x] Scaffold the application and CI (initial remote run passed).
- [x] Implement the read-only JPEG/PNG folder-to-preview vertical slice.
- [ ] Establish and verify real-camera performance budgets before closing Phase 2.

Revisit this plan after each phase; defer additional features until the current exit criteria are met.
