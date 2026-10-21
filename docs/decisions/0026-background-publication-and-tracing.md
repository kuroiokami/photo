# 0026 — Background publication and local interaction tracing

- Date: 2026-10-21
- Status: Implemented; validation and delivery evidence in the tracker/PR

## Context

Per-photo mutation of shared observable dictionaries can repeatedly invalidate contact-sheet dependencies. The 1,000-image baseline issued 1,000 metadata and 1,000 decision publication groups. Decoder-only measurements cannot establish input responsiveness. The [research plan](../WORKFLOW_PERFORMANCE_RESEARCH.md) prioritizes interaction evidence and less redundant publication before prefetch or framework/codec replacements.

## Decision

Buffer background metadata and loaded decisions in main-actor, observation-ignored dictionaries. Publish at read-completion checkpoints after roughly 50 ms or 64 reads/entries, plus completion. This is a checkpoint policy, not a timer or guaranteed deadline during an uninterruptible read. Merge each observable dictionary once per group. Selected-photo reads stay immediate. Changing focus promotes already-buffered metadata and the selected group's buffered decisions, including RAW+JPEG companions without waiting for unrelated I/O. Unknown decisions remain unavailable until loaded.

Validate session and live photo identity before buffering/publication. Clear buffers on folder/sample changes, exclude removed files, flush completed metadata on same-session cancellation, and allow an interrupted read to retry. Publish final metadata before the final EXIF-sort snapshot. Preserve existing filter/loading behavior; background completion cannot overwrite an already-ready photo's newer decisions/edits. Save ordering, SQLite durability, XMP reconciliation, source protection and normal-quit barriers are unchanged.

Add local OSSignposter intervals/events through PhotoCore, without UI dependencies or filenames, paths, captions, EXIF or hashes. Generated request IDs correlate UI publication with worker/decode/cache stages across actors. Publication events are not compositor presentation. Disabled tracing skips interval-state allocation. There is no upload or application trace archive. Raw Instruments recordings can contain system/process data and stay outside Git.

Observation-ignored counters measure publication groups, not actual view evaluations or frames. The read-only workspace harness adds optional first/middle/last navigation during real verified ingest of up to 24 disposable copies to two temporary destinations. Original images/sidecars are never written.

## Validation and boundaries

Regressions cover selected buffered metadata while another read is blocked, session changes, removal, cancellation/retry, final EXIF ordering and decisions/filter/Undo/persistence during loading. Existing protected-review, RAW+JPEG, conflicts, copy recovery and original-byte tests remain required. Native/release evidence is recorded in the tracker and [performance notes](../PERFORMANCE.md).

No prefetch, worker pools, cache codec/writer changes, ingest journal changes or decoder replacement are added. Lower publication counts alone do not establish scrolling FPS or large-shoot acceptance. Finalized SwiftUI/hitch traces, pressure/RSS profiling and physical-media/mixed-RAW scenarios remain separate requirements.
