# 0035 — Native reusable contact-sheet experiment

- Date: 2026-10-26
- Status: Experimental branch; native acceptance and performance comparison pending.
- Extends ADRs 0028, 0031, 0033 and 0034.

## Context

Rapid scrolling still lags. The row-only trial did not establish a benefit. The [source review](../OPEN_SOURCE_PERFORMANCE_REVIEW.md) recommends testing actual cell reuse and stable native geometry while preserving interactive culling controls. Upstream code is not copied and no dependency is added.

## Candidate

Use `NSCollectionView` with a flow layout for the full Contact Sheet. Each reusable item hosts the existing Equatable SwiftUI thumbnail. Keep the horizontal filmstrip in SwiftUI. Preserve the existing thumbnail/Fit/detail services, cancellation and session checks, cache limits, persistence and original-byte safeguards.

The coordinator caches an ID-to-index map. Inventory/order/filter/session changes reload the collection; selection changes map identities to native index paths. Per-photo observable records still update the bound controls directly. Width/density, actual EXIF label choices, cache generation, paired/folder labels and crop-clipboard availability reconfigure visible items. Offscreen cells release their hosted contents, cancelling image tasks; photo identity resets hosted view state on rebinding. Full-grid scrolling publishes no SwiftUI tile-frame preferences.

Use uniform card heights, reserving a composition-status line so applying an edit does not move rows. Native width uses the actual viewport, including legacy scrollbars. Arrow/range/Home/End navigation and offscreen reveal retain model selection semantics. Background marquee tracking uses native layout attributes clipped to the viewport, with Command/Shift preserving the selection base; tracking can cancel on focus loss. Existing direct controls, context actions and menu commands remain.

## Costs and acceptance

Hosted SwiftUI controls may retain layout/focus costs. Flow-layout preparation can still scale with inventory on reload/reflow. Native views/layout records/textures are outside image-cache budgets. Uniform card heights differ from unedited intrinsic SwiftUI cards: match window and density, record visible/newly exposed cell counts and geometry, and do not attribute reduced work solely to renderer efficiency.

Do not merge this default-grid switch as a speed fix until native functional checks and a usable matched release comparison succeed. Require stars/flags, group selection/marquee, Undo, edits, filters, keyboard reveal, resizing, labels and accessibility to survive reuse. Compare warmed 115-JPEG and settled 10k controls using identical completed inputs and usable stall/layout evidence. CPU/sample totals and accessibility wall time are not presented FPS. Real RAW shoots, physical-trackpad response, distributed shoots, 40k stress and memory pressure remain separate acceptance.

## Evidence so far

Strict checks pass with 201 registered Swift tests, 199 executed and two optional local RAW skips. Three new native-adapter tests exercise the real view factory, offscreen window/reveal, bounded binding at 1k, no inventory reload for selection/readiness, legacy scroller resizing, viewport-clipped marquee targets, same-count label replacement, filtering, same-photo session reset and native group/range mapping. These tests are not on-screen frame measurements.

An initial release candidate passed native checks on 115 disposable JPEGs: End/Home reveal, Shift-arrow range selection, direct group stars, keyboard Pick, independent two-step Undo, Crop opening/cancellation and Space/Z entry into genuine 2,400 × 1,600 JPEG detail then return to Fit/Contact Sheet. Native drag selection regressed; the background-tracking correction passes automated checks but still needs on-screen verification. Rotation/mirror and remaining native regressions have not been accepted in this round.

The Mac locked and automatic unlock failed before the corrected candidate could be inspected. Native comparison, corrected marquee acceptance and browsing-context restoration remain pending. The prior release is preserved outside Git. No speedup or Photo Mechanic parity is established.

The exact final candidate packages successfully and passes strict signature verification: release-product/app UUID `528BFE49-8702-38B6-A284-9630A7888953`. The preserved baseline UUID is `D370475D-D534-3B2D-8BEF-22F6C49D5B30`; its runtime matches the accepted grid. The baseline bundle is restored to the normal development-app location while the candidate stays outside Git. No Photo process is running. All 10,115 disposable original hashes/inodes match; only three expected 115-folder XMPs remain from explicit decisions/Undo, with no 10k XMP. Restoring the initial on-screen context still requires unlock.
