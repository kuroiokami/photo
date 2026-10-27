# 0037: Prepare nearby Fit previews after foreground readiness

- Status: Accepted with limited service/native validation
- Date: 2026-10-26

## Context

Sequential culling repeatedly needs adjacent Fit previews. Speculative work on the only Fit worker could delay a new selection because ImageIO cannot always be interrupted. Extra full-size caches or unbounded read-ahead would increase memory and card contention.

## Decision

Opt the workspace Fit pipeline into one extra preparation worker while keeping its existing foreground worker reserved. Thumbnail pools are unchanged. Other pipeline callers retain the existing defaults; the general initializer supports one through four ordinary workers plus one optional preparation worker. Optional work starts only when foreground demand is absent. A new foreground request can use its own slot while an obsolete opaque preparation finishes. Matching still-live requests coalesce; if the old view cancels before foreground admission, cancelled work can instead require a fresh decode. Never claim every cancelled opaque read is reusable.

The active single-image Fit view owns the preparation task. Begin only after its displayed preview is ready, wait 150 ms, then request at most the next/previous visible neighbors sequentially at 2560 pixels. Constant-size neighbor lookup preserves current filters, selected-only review, grouping and combined-folder ordering. Selection, source, readiness, neighbor-order or lifecycle changes cancel the old task. Pause in inactive scenes, detail/100%, comparison, workflow setup, crop/Trash setup, protected source review and file workflows. Make the shared workflow barrier observable so all windows pause on file-work transitions. An already running opaque read can only stop at cancellation probes.

Production preparation checks local/non-removable/non-ejectable volume flags on its blocking worker. Unknown/error/network/card/ejectable cases skip optional reads; foreground viewing retains its existing behavior. There is no physical-media acceptance or throughput-adaptive storage policy yet.

Share the existing 64 MiB Fit RAM cache rather than create another cache. Optional insertion protects the selected preview and the already retained first-priority neighbor. Evict other old entries as necessary; skip insertion if protected bytes plus the result exceed the budget. Decoding and UI/navigator references remain outside that cache accounting. Clear/session generations and retired-session UUID rejection still gate results. Background preparation has no disk cache, sidecar writes, full RAW demosaic or detail-image retention. Use the existing embedded-only decoder, orientation and recoverable-error behavior. Unavailable neighbors do not block the remaining candidate.

Fixed `NearbyFitPreparation` and `NearbyFitLoad` signposts expose optional work without paths or metadata. API callers own cancellation; a preparation controller generation prevents its continuation issuing another candidate after selection/session/clear changes. Selected work only scans/cancels speculative waiters when preparation is enabled, retaining the ordinary thumbnail hot path.

## Validation and limits

Eight preparation regressions cover bounds/readiness, foreground bypass of uninterruptible work, coalescing/cancellation, clear/retired sessions, tight-budget protection, storage eligibility, actual ImageIO/original preservation and broken-neighbor recovery. An observable barrier regression covers independent overlapping file jobs. Strict checks pass 216 registered tests, 214 executed and two optional RAW skips.

The [release control](../PERFORMANCE.md#foreground-first-nearby-fit-preparation--2026-10-26) uses fresh 64 MiB caches, off/on/on/off order, settled/zero-dwell forward/reverse/jump routes, original hashes, source counts and explicit failures. It improves ready-RAM hits on eight JPEGs/eight Sony ARWs and adds no source decodes in zero-dwell controls, with modest extra settled-route decoding. Native isolated-app checks and a fixed-event integration trace pass; original browsing context is preserved.

The benchmark omits view debounce/presented frames and uses tiny OS-cache-warmed corpora. Extra transient decoder memory, physical storage, broader camera families, pressure, multiple active windows and concurrent-ingest performance still need representative measurement. No dependency or broad throughput/parity claim is introduced.
