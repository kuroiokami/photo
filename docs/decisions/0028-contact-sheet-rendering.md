# 0028 — Contact-sheet rendering and native scrolling diagnostics

- Date: 2026-10-21
- Status: Implemented; final native acceptance pending
- Refines ADRs 0024 and 0025. Cache/decode/durability policy is unchanged.

## Context

A reported scrolling gap versus Photo Mechanic needs UI evidence, not additional decoder microbenchmarks. A finalized Animation Hitches capture of the release app browsing 1,000 disposable JPEG/PNG gradients recorded 45 potential main-thread stalls over 33 ms, up to about 305 ms. Sampled work included SwiftUI rendering/focus/lazy-grid/preference processing; a separate settled exploratory capture varied substantially. Scripted input adds accessibility/focus overhead. These are diagnostic observations, not competitor, dropped-frame or FPS measurements.

## Decision

Render unedited Fit/thumbnail CGImages through SwiftUI's resizable image with high interpolation and aspect-fit layout. Preserve the existing custom AppKit drawing path for Photo-local rotations, mirroring and crops, and preserve the separate detail renderer. Keep immediate RAM display, cancellation, pipeline/session identity, retry and cache-clear invalidation. Replace interpolated task-ID strings with an Equatable value containing the same identity fields. Format configured thumbnail labels once for visible and spoken values.

Report tile frames in a named content coordinate space instead of viewport coordinates. One content-origin preference tracks horizontal/vertical scrolling. A non-observable geometry holder projects frames into the viewport during marquee hit testing, clipping each projected frame before intersection. Stable tile positions no longer need new viewport-position values on every scroll step. Preserve per-photo identity/scrollTo targets, keyboard focus, lazy layout, accessible stars/flags and hover actions.

Add a local standard-library Python analyzer for finalized Animation Hitches traces. Export potential-hang and CPU tables into a temporary directory, resolve references, filter the selected process/main thread and publish only fixed-category aggregates. Merge overlapping stall intervals; inclusive CPU categories overlap. Do not publish raw exports, paths, process IDs, environment, symbol text or images. Do not treat process-less frame-lifetime/surface tables as Photo FPS. Parser regressions run in repository CI.

## Validation and limits

Strict Swift checks cover 168 registered tests, 166 executed and two optional RAW skips; two new geometry tests cover unchanged content frames across both scroll directions, replacement/clearing and viewport clipping. Three Python tests cover references, missing tables, overlap, process filtering and report privacy. Release packaging passes strict ad-hoc signature verification.

The rebuilt app opened the synthetic collection in Preview and Contact Sheet and completed returning scroll passes. The Mac locked before final native marquee, edit/hover/keyboard checks, matched shorter baseline replay and context restoration. Those checks remain pending. No measured smoothness improvement or parity with Photo Mechanic is claimed. Complete matched captures and physical trackpad/real-camera/color-profile/large-shoot acceptance before assigning UI performance targets; see [tracker](../../PROJECT_STATUS.md) and [performance evidence](../PERFORMANCE.md).
