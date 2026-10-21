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

Record exact counts, timings, native checks and CI evidence in PROJECT_STATUS.md and PERFORMANCE.md. Existing release/signing and minimum-macOS/Intel limits remain open; MIT OR Apache-2.0 is now selected.

## Accepted ingest/metadata/camera follow-up — 2026-10-19

- [x] Case-insensitive Canon CR2/CR3/CRW and Olympus/OM System ORF recognition; embedded-only Fit and deliberate Apple RAW detail. Real CR2/CR3/ORF samples verified; real CRW remains acceptance work.
- [x] Recursive two-destination ingest with streaming checksums, durable incremental/original-name evidence, collision protection and background culling; automatic verified arrivals (follow-up below).
- [x] Multi-selection and unique RAW+JPEG representation with independent per-file decision persistence and batch Undo.
- [x] Reviewed token-based bulk naming, companions, collision checks, original-name journals, Undo and interrupted-operation recovery.
- [x] Explicit layered IPTC presets, separate created/shown locations, keyword actions/hierarchies, pending local intent, preserving XMP and conflict handling.
- [x] Optional verified non-reject handoff including XMP/ACR and metadata embedding only in derived JPEG/PNG copies; manual Lightroom Add instructions.
- [x] Profile CR3 startup and bypass the measured slow ImageIO container path with a bounded embedded-JPEG reader; retain unknown-layout fallback.
- [ ] Verify Lightroom application round trips, real CRW/broader camera modes, and removable/network storage interruption scenarios.
- [ ] Add continuous source watching, full keyword dictionary import/export/synonyms, automatic ingest metadata/naming presets and clock correction if prioritized.

Implemented is distinct from complete release acceptance: keep first-open latency, actual interoperability and minimum-platform coverage explicit in the tracker. Preserve existing image bytes, use disposable copies for all mutation tests, and update evidence with every delivery.

## Accepted folder and batch usability follow-up — 2026-10-19

- [x] Merge existing fast-culling and ingestion/metadata work into main, retaining validation evidence.
- [x] Persist opened folder shortcuts and last selection; lazily expand and browse subfolders; explicit removal never deletes files.
- [x] Stable range/additive selection, Shift-arrow, visible batch flags, viewport rectangle selection and contextual metadata access.
- [x] Preview a single IPTC field from the first selected photo across a group, preserve all other fields and retain selection after applying.
- [x] Adopt appropriate Photo Mechanic shortcuts, native tooltips and optional Quick Start help; document deliberate shortcut differences.
- [x] Audit current Camera Bits documentation and record prioritized gaps in PHOTO_MECHANIC_REVIEW.md.
- [ ] Add first-use walkthrough, rectangle edge auto-scroll, mixed-value summaries if prioritized.

Test and delivery outcomes are tracked in PROJECT_STATUS.md; the existing Lightroom, latency and release acceptance limits remain open.

## Accepted full-detail performance follow-up — 2026-10-19

- [x] Profile explicit full-detail requests and distinguish first draw from deferred/offscreen rendering.
- [x] Show bounded, genuine full-quality focus detail first; complete the full RAW asynchronously at unchanged settings/resolution.
- [x] Reuse the render context, own eager bitmaps, bound output strips, preserve pan and cancel subsequent work on Fit/navigation.
- [x] Retain a combined 256 MiB region/full-image budget and release on Fit or selection changes.
- [x] Add read-only before/after detail measurements and an optimized app bundle option.
- [ ] Extend native frame/cancellation timing and progressive pixel/memory coverage across camera families, storage and supported macOS versions.

Actual tests and measured tradeoffs belong in PROJECT_STATUS.md and PERFORMANCE.md. Progressive rendering does not claim region-only RAW decoding or instant whole-image completion.

## Navigator and interface acceptance — 2026-10-19

- [x] Click/drag the detail navigator with clamped bounds and keyboard/accessibility actions.
- [x] Preserve pan through progressive detail replacement; center smaller images at true physical-pixel scale.
- [x] Clarify mixed batch decisions, field previews, workflow labels and unavailable actions.
- [x] Verify native navigator and workflow layouts; record limits in docs/UX_REVIEW.md.
- [ ] Broaden compact-window, VoiceOver, keyboard-only and minimum-platform verification.

## Preview and filmstrip follow-up — 2026-10-20

- [x] Default to a large preview above a lazy horizontal filmstrip; retain the full contact sheet as an explicit view.
- [x] Keep selection, multi-selection, filters, decisions and shortcuts shared between views; separate the shooting-information pane from the image.
- [x] Maintain independent in-session grid/filmstrip sizes and reveal the focused thumbnail after navigation or reordering.
- [x] Review current Photo Mechanic screen illustrations and rank proposed additions in PHOTO_MECHANIC_REVIEW.md.
- [x] Implement pinned comparison, selected-only review and configurable metadata labels in the approved follow-up below.

## Approved comparison and workflow follow-up — 2026-10-20

- [x] Pin reference/active comparison with linked or independent Fit/100% and normalized pan; reset to Fit on photo/view/session changes.
- [x] Keep RAW detail deliberate; bound each pane to 256 MiB retained detail (512 MiB comparison total), with no speculative rendering or detail cache.
- [x] Freeze selected physical identities for selected-only review; retain filtering, individual decisions and grouping semantics.
- [x] Offer up to two remembered EXIF thumbnail rows using existing indexing.
- [x] Publish complete, dual-verified image families during ingest; merge arrivals without resetting the current browsing session.
- [x] Commit reviewed metadata batches and owned-field Undo/Redo history atomically to SQLite; retain 20 batches across restart and preserve unrelated metadata.
- [x] Add regressions for linked routing, review/filter behavior, ingest publication/session races, metadata conflicts, failures, cancellation and restart.
- [ ] Broaden native comparison/platform/accessibility and real ingest interruption testing; actual outcomes remain in PROJECT_STATUS.md.

This scope implements normal-ingest arrivals, not continuous source watching or ingest naming/metadata automation. Lightroom application interoperability remains unverified.

## Contact-sheet decisions, gestures, editing and guides — 2026-10-20

- [x] Audit the installed Photo Mechanic’s basic image/metadata/file/inspection commands and document implemented versus remaining coverage.
- [x] Separate interactive thumbnail stars/flags from selection; retain batch scope, grouping, filtering and Undo, without direct-click auto-advance.
- [x] Add pinch magnification to preview/detail/comparison and thumbnail density; retain pan, explicit Fit/exact 100% and source-pixel geometry.
- [x] Implement the user-prioritized rotate/mirror/crop chunk, crop copying, protected local persistence and ordered session Undo without changing original bytes.
- [x] Make the first editing interoperability boundary explicit: Photo-local composition, with Adobe crop/orientation exchange and applied export still planned.
- [x] Replace repeated README material with linked, complete installation and usage guides, retaining the technical workflow and evidence documents.
- [x] Complete strict regression checks and optimized packaging; exact native outcomes and delivery are recorded in PROJECT_STATUS.md.
- [x] Recheck the final corrected crop/detail view and persisted composition after relaunch on an unlocked Mac.
- [ ] Complete physical pinch and broader accessibility/platform acceptance.
- [ ] Follow with verified crop/orientation exchange/export, locked-ratio/straightening, color classes, external editors and other audited gaps according to priority.

## Photo Home and deadline-first workflow — 2026-10-20

The user clarified two primary workflows: wire/news photographers delivering promptly without requiring Lightroom, and wedding/photoshoot photographers culling 10–40k frames before a separate editor. Favor immediate embedded previews, reversible keyboard decisions and short routes to output. Folder-wide collection performance at this scale needs measured acceptance; do not imply it has been established.

- [x] Replace technical folder wording with Photo folder, Backup folder, Shoot name and a folder chooser prompt.
- [x] Add remembered Photo Home as the first browsable sidebar folder; retain other saved folders and load subfolders on demand. Changing Home never moves photos.
- [x] Present copy setup in numbered steps and make Deliver / Edit independent of Lightroom in the interface and guides.
- [ ] Add guided source review before copying: local-only decisions, no source-sidecar writes, restart/reconnect protection and an explicit reviewed copy scope. Reuse verified copying and image-family publication; do not weaken source identity checks or backup verification.
- [x] Carry reviewed decisions and metadata to new copy identities safely; verify source/sidecar hashes unchanged and correct family/selection scope after filtering.
- [ ] Add a publication output route: reviewed keeper scope, caption/rights checks, derived JPEG rendering with orientation/crop/color validation, named output presets and an external editor option. Upload/FTP remains separate scope.
- [ ] Provide a resumable guided flow connecting source → optional review → copy destinations → organization → publication/editor, without blocking direct folder browsing or keyboard culling.
- [ ] Benchmark representative 10k/40k collections: first preview, metadata/decision indexing, scrolling, filtering, sorting, memory and large batch save/cancel/recovery. Full detail remains deliberate.

Ordinary source browsing still uses normal XMP synchronization. Explicit Review Before Copying now supports protected local review and frozen reviewed copying with verified decision handover. Physical card/reconnect and representative scale acceptance remain separate; do not imply they are measured. See [ADR 0015](decisions/0015-photo-home-and-workflow-routes.md).


## Pre-copy review and installable distribution design — 2026-10-20

Detailed plans: [protected source review](PRE_COPY_CULLING.md), [ADR 0016](decisions/0016-protected-source-review.md) and [distribution](DISTRIBUTION.md). Protected review, reviewed scope planning and verified handover are implemented; packaging/distribution remains a release design.

- [x] Audit current decision writes, ingest scope/manifests and app packaging; define the review boundary, frozen scopes, destination identity transfer and recovery requirements.
- [x] Implement review-only store/context and source mutation guards, including queued retries/history, second windows, child folders and relaunch. Automated writable-source preservation coverage passes; exact native acceptance is in the tracker.
- [x] Implement explicit source-wide copy choices, reviewed/unreviewed counts, pair expansion/conflicts and immutable file/family plans.
- [x] Implement journaled two-destination decision/edit handover and destination-only XMP, preserving provenance and later destination edits across interruption/retry.
- [ ] Complete guided review/copy/resume native acceptance and representative 10k/40k concurrent-copy measurements before claiming that scale.
- [ ] Add clean, versioned release-bundle/DMG tooling without changing the development command. Confirm release identity, icon, inclusion of both license texts and NOTICE and hardware support before publishing.
- [ ] With owner-provided Developer ID/notarization setup, produce and validate a stapled app/DMG on a clean recipient Mac, including upgrade/local-data persistence and offline launch.
- [ ] Publish only an explicitly authorized, accepted beta artifact with checksum, installation instructions and tested platform/camera limits. Intel/universal builds, automatic updating and App Store distribution remain separate acceptance work.


## Protected source review implementation — 2026-10-20

- [x] Add separate SQLite review items and a durable source registry; route stars/flags/composition/Undo locally without normal pending XMP.
- [x] Guard normal metadata/decision/history, rename/recovery, file destinations and derived-image mutations beneath the UI; preserve identity/replacement/alias protections.
- [x] Install protection before draining queued saves; restore context on child navigation/relaunch and refresh affected windows.
- [x] Expose Review Before Copying and an explicit review-only banner/status. Block copy/handoff until reviewed scope and transfer are implemented.
- [ ] Complete native/platform/removable-card/performance acceptance; exact observed checks are in PROJECT_STATUS.md.
- [x] Implement reviewed copy choices and durable handover; retain source bytes, XMP preservation, destination identity binding and two-copy verification.


## Workflow guidance — 2026-10-20

- [x] Add a non-blocking Ingest introduction and five-step walkthrough with concrete deadline/large-shoot examples, navigation and plain language.
- [x] Remember explicit permanent dismissal; retain Help/workflow access and allow re-enabling. Keep operational protection/error banners independent.
- [x] Explain current protected-review copying and local-image-edit limits before relying on them; recommend verified-copy/early-culling for current output.
- [x] Connect reviewed-copy/resume implementation to guidance and explain selection versus source-wide scopes, frozen revisions and metadata readiness. Full removable-card/scale acceptance remains separately tracked.

See [ADR 0018](decisions/0018-workflow-walkthrough.md); validation is maintained in the tracker.


## Complete reviewed copying — 2026-10-20

- [x] Expose all/picks/non-rejected/physical-selection scopes, explicit unreviewed counts and companion additions/conflicts before copying.
- [x] Freeze source identities, per-field decision ownership/revision, composition, sidecar baselines and destination layout without decoding pixels.
- [x] Verify two destinations, persist append-only original provenance and transactionally seed both destination identities before publication.
- [x] Resume saved plans idempotently across bytes/local-intent/XMP boundaries; preserve later destination decisions, composition and descriptive/develop metadata.
- [x] Keep the source visible and protected; explicitly navigate to verified working copies. Update walkthrough and guides together.
- [ ] Finish physical removable-card, broad VoiceOver/compact-display and representative 10k/40k concurrent-copy acceptance; exact automated/native evidence belongs in the tracker.

[ADR 0019](decisions/0019-reviewed-copy-handover.md) records implementation choices and limits. A new transfer of later source decisions needs a fresh list/shoot folder; replay over existing destination work is deliberately refused.

## Public repository standards — 2026-10-20

- [x] Adopt owner-selected MIT OR Apache-2.0 with NOTICE, contributor/support/security/conduct policies and issue/PR templates.
- [x] Add changelog, CODEOWNERS, pinned least-privilege CI, Actions dependency updates and automated repository hygiene/secret checks.
- [x] Audit reachable history and repository metadata before public visibility; retain only intentional fixtures and preserve unrelated local edits.
- [x] Verify public visibility and GitHub protections/security settings; record actual settings in PROJECT_STATUS.md.
- [x] Validate the combined implementation/standards tree in public CI; deliver through PR #14 with final-head required checks. Exact check/merge evidence is recorded in the PR and tracker.

Signed/notarized app distribution and broader platform/native acceptance remain separate milestones.

## Public documentation — 2026-10-20

- [x] Present Photo with a concise introduction, practical feature overview, build instructions and first culling session.
- [x] Add a public roadmap and welcoming contribution/support guidance; retain detailed evidence and agent instructions in their dedicated documents.
- [x] Keep release, camera compatibility and composition-edit limits visible without turning the README into an engineering handoff.

Documentation validation and delivery evidence are tracked in PROJECT_STATUS.md and the delivery PR.

## Dual licensing — 2026-10-20

- [x] Offer MIT or Apache-2.0 at the recipient’s option, following the owner’s explicit choice.
- [x] Keep complete license texts, consistent contribution/distribution guidance and license-integrity checks; preserve third-party terms and existing Git history.

See ADR 0021 and the tracker/delivery PR for validation and remote CI evidence.

## Clear ingest setup — 2026-10-20

- [x] Replace the scrolling main ingest form with bounded source, destination, confirmation and progress pages.
- [x] Make Start Culling and the source-banner return explicit; default reviewed copying to Picks Only and retain other explicit scopes.
- [x] Keep detailed file lists, saved-copy recovery and full status in separate views; retain source protection and frozen plans.
- [x] Verify native layout and both cull-first and copy-first flows on disposable images, including original hashes, saved resume and final packaged fixes.
- [x] Pass local Swift checks; record repository checks and exact final-head required CI/merge evidence in the delivery PR. Broader compact-display/VoiceOver/platform and physical-card acceptance remain open.

See ADR 0022 and the tracker for observed evidence.

## Measured performance review — 2026-10-20

- [x] Audit supplied optimization suggestions and retain natural ordering, durability, source protection and independent copy verification.
- [x] Measure and remove linear cache recency scans; reuse actor-owned EXIF/JSON parsers and existing decision identity lookups.
- [x] Add isolated release microbenchmarks and cache/timestamp regressions; distinguish warm synthetic service gains from RAW/native/large-shoot acceptance.
- [ ] Profile batch persistence/XMP, selection summaries/observation, main-actor rating reorders and cold camera metadata before further architectural changes.

See [the audit](PERFORMANCE_REVIEW.md), [evidence](PERFORMANCE.md) and tracker for measurements and exact validation limits.

## Keyboard culling, in-window workflow and reject cleanup — 2026-10-20

- [x] Clarify selected-only review with explicit scope, two-photo minimum and Show All Photos.
- [x] Stabilize ordinary review/decision status layout and add Fit/100%, rotation and unconditional photo-navigation shortcuts.
- [x] Present workflow setup in the main window with explicit return-to-photos callbacks and retained browser identity.
- [x] Add confirmed macOS Trash removal of selected working files and exclusive companions; preserve source protection, file identity checks and shared sidecars.
- [x] Add isolated failure/replacement/arrival/protection/selection/late-result regressions; document Finder recovery and non-atomic batches.
- [ ] Broaden native compact-window/accessibility/platform, removable/network-volume and large-batch performance acceptance.

See ADR 0023, the usage guide and tracker for actual checks and delivery.

## Visible image editing — 2026-10-20

- [x] Keep labelled rotation/mirror/crop controls visible in Contact Sheet and Preview, with shortcut hints and correct selection scope.
- [x] Retain existing Image menu commands and Photo-only edit boundaries; verify the shared controls natively and run required checks.

Actual validation/delivery evidence is recorded in the tracker and delivery PR.
