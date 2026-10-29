# 0046 — Prepared photo identities and inventory-sized indexing tables

Date: 2026-10-29

Status: Implemented; measured scope and delivery evidence in the tracker.

## Evidence

The 10k Unicode-path control retains about 0.4 s Select All work and 62–64 ms decision-publication spikes after ADR 0045's small batches. Separate sampling of an owned disposable debug-signed PhotoBench copy shows foreign-string Unicode hashing throughout selection/lookups and dictionary/set resize-and-rehash stacks inside publications. Samples include waits and are not CPU milliseconds or presented frames. Raw traces remain outside Git.

## Changes

Prepare each file-backed PhotoItem ID with `makeContiguousUTF8()` once during model construction. Preserve the exact standardized path's UTF-8 sequence, canonical equality/hash behavior and original URL/filename. No normalization, case conversion, path shortening, persisted identity migration or image change. Enumeration already constructs models off the main actor; URL-based filesystem identity, cache/source validation and persistence remain unchanged.

Reserve metadata capacity when indexing begins, using the current inventory size. Reserve the six decision/edit/status/readiness/identity/review-field tables before decision indexing, using that index's snapshot count. This moves expected allocation to the measured startup stage instead of geometric rehashes of accumulated keys inside a small publication. Retain normal value semantics and snapshot isolation. It is earlier model allocation, not a change to decoded-image cache budgets or a peak-memory bound. Verified arrivals retain their existing validation/publication path; later growth and shared snapshot copies remain possible.

For ungrouped operations, selected IDs are already unique: look them up directly instead of expanding them through arrays and a second Set. Grouped operations still expand/deduplicate physical companions. Publish selection changes by walking removed/added membership directly, updating only changed per-photo flags without constructing a symmetric-difference Set. Summary, unknown gating, focus, ordering, filters, auto-advance, Undo/Redo and persistence semantics remain.

## Validation and limits

Tests preserve exact decomposed/composed/emoji/non-Latin path bytes and legacy dictionary/Set compatibility; exercise 1,025-photo selection, unknown readiness, unchanged-tile observation, snapshots, group decisions/history, inversion/deselection; and verify actual file-backed RAW+JPEG grouping versus ungrouped membership. Existing interruption/source protection/save tests remain.

Quiet ABBA controls cover Unicode-heavy and ordinary ASCII 10k generated-file corpora, retaining complete anonymous reports, first-preview/readiness, suspension, RSS, hashes and failures. Native isolated checks cover 10k selection/inversion/deselection during/after indexing, disabled unknown decisions and ready controls, plus Unicode JPEG stars/flags, independent Undo/Redo, filter removal/restoration, Reload and cleanup. See PERFORMANCE.md. Large Unicode selections and collection-wide ordering still exceed a frame; no hard 2 ms, FPS, memory, physical-media, 40k/pressure or broad-camera claim.
