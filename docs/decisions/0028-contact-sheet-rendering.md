# 0028 — Contact-sheet rendering and native scrolling diagnostics

- Date: 2026-10-21
- Status: Implemented; native functional checks passed
- Refines ADRs 0024 and 0025. Cache/decode/durability policy is unchanged.

## Context

A reported scrolling gap versus Photo Mechanic needs UI evidence, not additional decoder microbenchmarks. A finalized Animation Hitches capture of the release app browsing 1,000 disposable JPEG/PNG gradients recorded 45 potential main-thread stalls over 33 ms, up to about 305 ms. Sampled work included SwiftUI rendering/focus/lazy-grid/preference processing; a separate settled exploratory capture varied substantially. Scripted input adds accessibility/focus overhead. These are diagnostic observations, not competitor, dropped-frame or FPS measurements.

## Decision

Render unedited Fit/thumbnail CGImages through SwiftUI's resizable image with high interpolation and aspect-fit layout. Preserve the existing custom AppKit drawing path for Photo-local rotations, mirroring and crops, and preserve the separate detail renderer. Keep immediate RAM display, cancellation, pipeline/session identity, retry and cache-clear invalidation. Replace interpolated task-ID strings with an Equatable value containing the same identity fields. Format configured thumbnail labels once for visible and spoken values.

Keep tile frames in viewport coordinates in a non-observable geometry holder. Clip each frame to the viewport before marquee intersection so a drag outside the pane cannot select a hidden part of a partially visible tile. A candidate content-coordinate/one-origin optimization failed native acceptance after scrolling and was withdrawn. Preserve per-photo identity/scrollTo targets, keyboard focus, lazy layout, accessible stars/flags and hover actions.

Add a local standard-library Python analyzer for finalized Animation Hitches traces. Export potential-hang and CPU tables into a temporary directory, resolve references, filter the selected process/main thread and publish only fixed-category aggregates. Merge overlapping stall intervals; inclusive CPU categories overlap. Do not publish raw exports, paths, process IDs, environment, symbol text or images. Do not treat process-less frame-lifetime/surface tables as Photo FPS. Parser regressions run in repository CI.

## Validation and limits

Strict Swift checks cover 167 registered tests, 165 executed and two optional RAW skips; the new geometry regression covers visible-only clipping alongside existing frame replacement/clearing tests. Three Python tests cover references, missing tables, overlap, process filtering and report privacy. Release packaging passes strict ad-hoc signature verification.

Native checks passed viewport-based marquee after vertical scrolling and horizontal filmstrip movement, group stars/flags and Undo, quick actions, rotate/mirror/crop rendering and Undo, density reflow, keyboard navigation/reveal and normal quit/relaunch. Original browsing context was restored and the disposable shortcut removed; all 1,000 source-image hashes matched. Physical trackpad/real-camera/color-profile/RSS/large-shoot acceptance remains open. Native diagnostic comparisons and their limits are recorded in [performance evidence](../PERFORMANCE.md); no Photo Mechanic parity or FPS claim is established.
