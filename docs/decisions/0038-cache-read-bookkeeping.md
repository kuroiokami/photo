# 0038: Keep thumbnail reads independent of cache maintenance

- Date: 2026-10-27
- Status: Implemented; validation/delivery in the tracker

## Context

Disk payload reads and PNG decode already run outside the cache publication lock. Their final access-date update still takes that lock, which the writer holds while enumerating the directory, atomically publishing records and evicting files. A disk hit can therefore wait behind unrelated filesystem maintenance.

## Decision

Readers finish under only the short admission lock: verify their clear generation and record a coalesced date hint. Keep at most 512 distinct hints. At saturation discard one existing hint to admit the newly visited key, so long read-only sessions do not indefinitely favor their first folder. This is approximate recency, not an unlimited exact disk LRU.

Writers retain the publication lock for index/filesystem mutations and drain bounded hints before selecting eviction victims. Clear advances its generation and removes hints while serialized with publication. A stale read cannot publish a hint/result after its generation changes. No filesystem work, PNG work or source validation is moved into admission. Existing source-stamp/replacement checks, atomic records, 512 MiB disk target, 90% eviction hysteresis, bounded pending images/bytes, record format and original-byte guarantees remain.

This removes read-side dependence on publication; writers/clear still serialize and may wait for filesystem work. A full hint buffer may lose recency information and cause an otherwise reusable thumbnail to be evicted. Cache contents remain optional derived data. No user decisions, XMP durability or RAW decoder behavior changes.

## Validation

A deterministic gate holds the writer inside its publication lock. The new reader completes before the gate is released; the same regression against the old implementation times out as expected. Tests also cover coalesced/bounded hints, recency-based eviction, clear and concurrent read/store/clear. Four targeted Thread Sanitizer tests pass. Existing source replacement, corruption, permissions, cache generation and cancellation tests remain.

The [matched release experiment](../PERFORMANCE.md#cache-read-bookkeeping--2026-10-27) uses identical synthetic harness/core sources with only the cache implementation restored for the baseline. In baseline/candidate/candidate/baseline order, maximum queued disk-hit readiness falls from 124.6–129.8 ms to 2.4–2.5 ms while lazy indexing runs. All 72 reads hit disk without source decoding, and original hashes match. Scheduling overlap varies; first-viewport and p95 outcomes must not be collapsed into a universal speedup. No UI/FPS, physical-media or real-shoot claim.
