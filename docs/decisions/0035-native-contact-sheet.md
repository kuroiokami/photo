# 0035 — Native reusable contact-sheet experiment

- Date: 2026-10-26
- Status: Accepted for the full grid after controlled release acceptance; broader library/physical-input acceptance remains open.
- Extends ADRs 0028, 0031, 0033 and 0034.

## Context

Rapid scrolling still lags. The row-only trial did not establish a benefit. The [source review](../OPEN_SOURCE_PERFORMANCE_REVIEW.md) recommends testing actual cell reuse and stable native geometry while preserving interactive culling controls. Upstream code is not copied and no dependency is added.

## Candidate

Use `NSCollectionView` with a flow layout for the full Contact Sheet. Each reusable item hosts the existing Equatable SwiftUI thumbnail. Keep the horizontal filmstrip in SwiftUI. Preserve the existing thumbnail/Fit/detail services, cancellation and session checks, cache limits, persistence and original-byte safeguards.

The coordinator caches an ID-to-index map. Inventory/order/filter/session changes reload the collection; selection changes map identities to native index paths. Per-photo observable records still update the bound controls directly. Width/density, actual EXIF label choices, cache generation, paired/folder labels and crop-clipboard availability reconfigure visible items. Offscreen cells release their hosted contents, cancelling image tasks; photo identity resets hosted view state on rebinding. Full-grid scrolling publishes no SwiftUI tile-frame preferences.

Use uniform card heights, reserving a composition-status line so applying an edit does not move rows. Native width uses the actual viewport, including legacy scrollbars. Arrow/range/Home/End navigation and offscreen reveal retain model selection semantics. Background marquee tracking uses native layout attributes clipped to the viewport, with Command/Shift preserving the selection base; tracking can cancel on focus loss. Existing direct controls, context actions and menu commands remain.

## Costs and acceptance

Hosted SwiftUI controls may retain layout/focus costs. Flow-layout preparation can still scale with inventory on reload/reflow. Native views/layout records/textures are outside image-cache budgets. Uniform card heights differ from unedited intrinsic SwiftUI cards: match window and density, record visible/newly exposed cell counts and geometry, and do not attribute reduced work solely to renderer efficiency.

Accept the native full-grid replacement on the controlled keyboard/group/edit checks and repeated warm 115/10k CPU plus usable stall/layout evidence below. Do not infer equal work from equal density: differing card heights expose different photo counts. CPU/sample totals and accessibility wall time are not presented FPS. Real RAW shoots, physical-trackpad response, distributed shoots, 40k stress, broad VoiceOver and memory pressure remain separate acceptance.

## Evidence and outcome

Strict checks pass with 201 registered Swift tests, 199 executed and two optional local RAW skips. Three native-adapter tests exercise the real view factory, offscreen window/reveal, bounded binding at 1k, no inventory reload for selection/readiness, legacy scroller resizing, clipped marquee targets, same-count label replacement, filtering, same-photo session reset and group/range mapping. They are not frame measurements.

After unlock, native tests found and corrected background drag selection and lost culling-key focus. The retained implementation restores the outer SwiftUI focus state after native tracking. Release checks pass first/last-row marquee, post-drag stars/P/X and independent Undo, rotation/mirror/Undo, filters/Clear Filters, density/EXIF reflow, group IPTC access, offscreen keyboard navigation and genuine JPEG Fit/100% return. Synthetic 10k Select All reports ready targets. Original-byte guards remain intact.

[Controlled evidence](../PERFORMANCE.md#native-reusable-contact-sheet--2026-10-26): process-CPU repeats improve from 2.57/2.55 to 1.57/1.55 seconds at 115 JPEGs and 5.56/5.38 to 2.34/2.21 at 10k. Matching 20-second stall captures reduce longest potential stalls from about 327/344 ms to 132/130 ms. Counts are not uniformly lower; geometry, sequential phases and automation overhead prevent an isolated renderer-efficiency percentage. No competitor, presented-frame or physical-trackpad claim.

Both baseline and native AX snapshots sometimes omit button labels after background scrolling. Replacing the host root with an observable content wrapper did not resolve that shared observation; withdraw that additional trial and retain the measured host implementation. Selected labels/actions remain available. Broad VoiceOver acceptance remains open rather than claim a resolved accessibility issue.

The final rebuilt release UUID is `942E2146-BC8B-3537-BF74-4B2D68F8AB21`; the preserved baseline is `D370475D-D534-3B2D-8BEF-22F6C49D5B30`. Packaging and strict signature verification pass. All 10,115 disposable original hashes/inodes match; six expected 115-folder XMPs reflect explicit decisions/Undo and none exist at 10k. Raw traces/pixels stay outside Git. After unlock, both temporary sidebar shortcuts were removed and Sample Collection / Dawn / full grid / density 160 / empty sidebar were verified. The current window size and original files are preserved; native cleanup is complete.
