# 0032 — File-backed scale profiling and selection readiness traversal

- Date: 2026-10-26
- Status: Implemented; measured evidence and delivery in the tracker/PR
- Refines ADR 0031. Decision persistence, source protection and image decoding are unchanged.

## Context

The prior summary benchmark used in-memory sample items. It did not measure navigation through a loaded real-file inventory, full indexing or resident memory. The first 10k/40k file-backed runs showed selection-to-Fit service latency growing with folder size, even after decisions were loaded.

The readiness snapshot used `Set(selectedIDs).subtracting(allReadyIDs)`. Swift's Set implementation can walk the supplied large ready set before finding the selected members. For a one-photo selection this visits unrelated files during focus/selection refresh. This was introduced with the previous readiness refactor; the small semantic tests and repeated-summary microbenchmark did not establish its large-folder navigation cost.

## Decision

Construct unknown membership by iterating represented selected IDs and looking each up in the ready set. Preserve the same resulting unknown set, Boolean readiness, mixed summary, grouping and publication behavior. Reuse the selection snapshot when explicit selected IDs stay unchanged through order/focus changes. Selection-ID changes, implicit focus without explicit IDs, grouping, families and inventory still invalidate it; pending focused results continue to promote. Large group initial snapshot construction and collection reordering remain separate costs.

Add `PhotoBench --scale` for actual read-only image inventory, concurrent metadata/decision indexing, first selected readiness/Fit, forward/reverse/spread navigation, cached Fit, selection/filter/sort costs and sampled process RSS. Use an isolated temporary database, original-byte hashes, fixed anonymous fields and no shared disk thumbnail cache. Report per-selection time separately from total Fit latency. Source hashing warms filesystem caches; fresh process/database does not mean physically cold media. Preflight URLs coexist with workspace inventory and contribute to service RSS; retain a pre-workspace checkpoint. No compositor, view debounce or thumbnail-grid work is included in the service timer.

Add `--generate-scale` using the existing project-created JPEG/PNG gradients and filesystem clones with distinct inodes, never hard links. Refuse existing destinations, invalid counts and unsupported cloning. This bounds physical storage but repeats only three pixel templates, with no real EXIF/RAW diversity. Do not present it as representative camera/shoot acceptance. Generated images/databases/traces remain outside Git.

Capture native release scrolling diagnostics separately, with fixed inputs/window/density, settled indexing and explicit RSS checkpoints/sampling. Keep raw traces outside Git and publish the existing analyzer's fixed aggregates. Potential hangs, sampled main-thread weight, body evaluation and presented frames are different measurements; do not equate them. Physical trackpad and real mixed-camera large-shoot acceptance remain open.

## Validation

The small CLI smoke run verifies valid decoding, distinct identities, original hashes, complete scale-report results, no source sidecars, existing-folder refusal and invalid-count refusal. Regressions check mixed/unknown selected decisions against 40k unrelated ready records and unchanged membership across sorting/focus plus filtering to an empty selection; existing Observation/group/filter/Undo/session tests remain required. Before/after release reports and native diagnostic scope belong in the tracker and performance notes, including remaining slow operations and memory-measurement limits.
