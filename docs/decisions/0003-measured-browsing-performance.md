# 0003: Measured browsing performance and stable workers

- Status: accepted
- Date: 2026-10-19
- Refines: 0002 (worker/cache lifetime and preview protocol)

## Context and evidence

The user requested real-folder validation, responsiveness/memory measurement, bottleneck fixes, and review/merge of PR #1. Paired release measurements on 17 approximately 50 MP JPEGs found redundant concurrent decoding and repeated linear selection scans. A 2,000-file mixed JPEG/PNG corpus supplied larger enumeration/scrolling coverage. See [performance results](../PERFORMANCE.md) and the aggregate JSON there.

## Decision

Keep a single ImagePipeline actor per thumbnail/preview lane for the lifetime of the window. Cache lookup and synchronous ImageIO decoding happen within that actor without suspension between them, so queued identical requests reuse the first result. Thumbnail and preview lanes can still run concurrently, and UI execution remains on the main actor. A per-decode autorelease pool bounds temporary decoder retention.

Add an optional folder session ID to the preview-loading protocol. Session changes clear image caches without replacing workers; cancelled session-reset tasks do nothing. SwiftUI's session-keyed task cancels superseded cache-reset work. Each image task carries the session ID, and a non-decoding cache lookup lets cached previews bypass the 35 ms cold-preview debounce. Existing cancellation checks reject queued or completed stale work; running filesystem/ImageIO calls remain cooperatively cancellable only around the call.

Store the selected index and an ID-to-index table in WorkspaceState. Selected photo, selected ID, and index reads are constant-time. Build folder models and lookup tables in a cancellable background task, publish them together on the main actor, and clear selection before replacing the collection. This trades a small amount of indexed folder-startup work/memory for cheap repeated selection.

Keep selected thumbnails visible after pane/density changes by coalescing intermediate grid layouts for 50 ms and then revealing the current selection; keyboard selection still scrolls immediately. This resolves a native regression observed at the end of a 2,000-file contact sheet.

Add a dependency-free PhotoBench executable and release benchmark script. Source hashes are compared in memory; output contains aggregate statistics only. Generation is restricted to a new directory. Reports include hardware/build context and measurement limits; correctness tests run in CI, but machine-specific timing targets do not.

## Validation and limits

The current repository check passes 18 tests, including duplicate-request decode count, cancellation-safe session resets, stale cache invalidation and retry, large-collection selection, eight JPEG/PNG spelling/case variants with Unicode filenames, and the existing folder/image/source-preservation tests. Native checks and the merge/CI evidence are maintained in PROJECT_STATUS.md.

Median paired results: eight concurrent requests 1628.8 → 203.1 ms; 50,000-item selection p95 7.1260 → 0.0009 ms; sampled peak benchmark-process RSS 531.2 → 418.6 MiB. Individual cold ImageIO decoding is not materially faster. Cache budgets are not total application memory caps; measured RSS includes validation allocations. This is one reference Mac/corpus, not a claim about every device, camera, or frame rate. No persistence migration or external client compatibility is required.
