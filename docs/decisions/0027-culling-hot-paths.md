# 0027 — Selection readiness, deferred cache writes and indexing costs

- Date: 2026-10-21
- Status: Implemented; validation and delivery evidence in the tracker
- Refines ADRs 0005, 0025 and 0026. Decision-save/XMP durability is unchanged.

## Context

Selected thumbnail controls repeatedly expanded the same selection to check readiness. Initial decision discovery normally seeded a decision record and path identity in two SQLite autocommit transactions per file. Natural filename comparisons were repeated for rating/EXIF ties. Thumbnail delivery waited for optional PNG serialization, initial disk-cache indexing and atomic writes.

## Decision

Cache selection readiness behind an observable revision. Selection/focus, displayed collection, grouping/family membership, live-ID mapping and loaded-decision readiness invalidate it. The first query after invalidation expands/checks the selection; subsequent tile queries are constant time. Keep revision observation on cache hits so SwiftUI cannot retain an obsolete enabled state. Diagnostic evaluation counts are not UI-frame counts.

Build native filename ranks once per inventory, off the main actor during folder opening. An already-ordered inventory takes a linear adjacent-order check; otherwise Foundation sorts it. Reuse integer ranks in subsequent filename/EXIF/rating ordering and single-rating repositioning. Refresh on inventory additions, sample replacement and explicit sort after a locale change. Preserve Foundation locale/Unicode/numeric behavior and identity ties; do not implement an approximate ASCII-only natural key. Initial directory enumeration still uses native collation. Membership updates and some rating sorts still run on the main actor.

Index initial decisions/image edits in transactions of at most 16 files, retaining selected-photo priority between batches. Each result is published only after commit. Sidecars are read, never written, inside these indexing transactions. Cancellation/commit failure rolls back; automatic SQLite rollback stops the loop before later files can autocommit. Per-file read errors remain recoverable. Source-review routing, conflict/replacement handling, pending recovery and FULL synchronous durability remain. Existing user-decision saves still commit durable intent before XMP publication and acknowledgement afterward; batching those saves is separate work.

Admit thumbnail persistence to one utility Dispatch queue, capped at 64 queued/active images and 32 MiB of decoded pending pixels per cache instance. Deduplicate pending keys and drop optional writes on saturation. Admission uses a separate short lock and does not wait for PNG encoding or disk I/O. Reuse a binary plist encoder behind an encoding lock. Validate source stamps before deferred encoding and again before atomic publication. Cache clear advances a generation; previously admitted writes cannot repopulate it. Outstanding derived writes need no quit barrier. Expose an asynchronous diagnostic drain for deterministic tests/benchmarks only.

Hash the original source stamp once and compare fresh stamp fields on subsequent validations; retain file-stat checks. PNG record reading/decoding runs outside the shared accounting lock, with a generation check before return. Reads remain synchronous on the thumbnail actor; this does not implement a separate asynchronous reader or worker pool. The record version, cache budgets, original bytes and separate Fit/detail workers remain.

## Validation and limits

Tests cover readiness reuse and Observation invalidation, mixed Unicode/numeric/identity filename ties across all sort modes, bounded commits and restart read-back, automatic rollback/retry, pending byte limits, preview delivery with a suspended writer, clear invalidation and replaced sources. Existing cancellation, source protection, group decisions, filters/Undo and image-byte preservation checks remain required.

The thumbnail benchmark reports preview-delivery time and subsequent cache-drain time separately. The expanded hot-path benchmark reports cold individual/batched SQLite indexing, five 40k-file tie sorts with separate rank-construction time, and 10k readiness queries for a 10k selection. These are synthetic service checks, not native scrolling FPS, physical-media acceptance, bulk flag-save throughput, CR3 startup or a fastest-viewer comparison. See [performance evidence](../PERFORMANCE.md) and [tracker](../../PROJECT_STATUS.md).
