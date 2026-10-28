# 0043 — Bounded durable decision saves

Date: 2026-10-27

Status: Accepted; acceptance evidence in the tracker and [performance report](../PERFORMANCE.md#bounded-decision-saves--2026-10-27).

## Problem

A group rating/flag action previously queued one task per physical photo. Each ordinary save durably committed its pending decision, published XMP, rebased descriptive metadata if present, then separately committed the acknowledgement. Protected pre-copy review also committed each decision independently. Prepared statement reuse and read/index transactions did not batch these user writes.

## Decision

Queue one immutable persistence snapshot per decision action or Undo/Redo group. Process at most **32 physical files** per store call, then publish guarded UI statuses and yield. Maintain the existing shared queue ordering and normal-termination/workflow flush. Closing a workspace must not cancel its queued writes; weak workspace references guard only UI publication. Session and per-file versions reject stale statuses after navigation or a newer action.

For an ordinary chunk:

1. Validate per-file identity and source-write policy. Read current sidecars and merge only owned decision fields. Preserve conflicts, malformed/ambiguous/symbolic sidecars and original image bytes. Individual preflight failures do not discard valid neighbors.
2. Commit all valid pending decisions in one **SQLite `BEGIN IMMEDIATE` / `COMMIT`**, retaining `synchronous=FULL`. No sidecar is published before this durable intent. A database failure rolls back the chunk and prevents publication.
3. Publish each eligible sidecar through the existing coordinated, atomic replacement. Recheck physical identity and the exact preflight sidecar digest inside coordination. A late external edit remains a conflict, including during explicit resolution. Partial publication is possible; failed files stay pending independently.
4. Acknowledge successful publications and their descriptive-metadata baseline rebases in one local transaction. A failed acknowledgement rolls back all those local changes; already published sidecars remain recoverable.

The source registry's recursive boundary remains held through a bounded chunk so in-process protection activation cannot occur between per-file admission and mutation. The boundary grants no write permission; normal writes still require `withWritable`, and protected-review writes still validate the matching review/session/file binding. No SQLite transaction spans suspension or sidecar I/O. Protected review uses one local transaction per chunk, preserving composition, review state, revision and independent field ownership without writing source sidecars.

Repeated physical identities use ordered singleton saves so alias requests cannot collapse or reorder decision history. This exceptional path retains its original cost. Store APIs reject oversized chunks; workspace callers divide larger actions and yield between chunks. Cancellation before committing intent rolls back; after intent commits, the admitted ordinary chunk finishes publication/acknowledgement even if its caller is cancelled. Subsequent chunks are independently cancellable, while the production save queue remains uncancelled and drains on normal Quit.

## Interrupted acknowledgement

A new optional `StoredDecision.publication` receipt records the exact before/after XMP digests in the pending-intent transaction. On reopen, acknowledge an already published decision only when its fields **and exact expected digest** match. Rebase matching descriptive metadata and acknowledge together. This avoids a false metadata conflict after an interrupted acknowledgement and prevents matching stars from hiding an intervening unrelated external edit. A subsequent decision or immediate retry first completes recovery of a matching prior receipt, before replacing pending intent; these exceptional recovery commits are separate from the normal batched save counts. Older pending records without receipts retain legacy compatibility; no database schema migration is required.

Recovery may run inside an existing image-state indexing transaction. Use a savepoint there, and stop if a SQLite trigger/error automatically rolls back the outer transaction. Never let remaining statements silently run as autocommits after rollback.

Retain at most **1 MiB of prepared XMP output per chunk**. Larger outputs are hashed during preflight, discarded and recomputed per file inside coordination, with the expected digest checked again. Existing 16 MiB sidecar admission remains; transient XML/parser/source buffers and allocator overhead are separate from this retention bound. This is not a process-memory guarantee.

## Acceptance and limits

Fault-injection regressions cover intent and acknowledgement rollback, partial publication/restart, nested recovery rollback, metadata rebasing, external edits before/after publication, malformed/conflicting sidecars, identity replacement, cancellation, aliases, output bounds, protected review/edits/ownership, grouped Undo/Redo and persistence after workspace release. Existing read-only, symlink, ambiguity, grouping/filter/advance and termination/protection checks remain.

`sh scripts/benchmark.sh --decision-saves` compares singleton and 32-file production saves over three matched 1,000-file generated ordinary/protected workflows. Fixture/index creation and verification are excluded; original bytes, sidecars and restarted decisions are checked. Reverse mode order in the second iteration. Commit counts are deterministic; timing is local service evidence, not historical code comparison, native frame rates, physical-card latency, whole-process memory or power-loss acceptance. Representative shoots/media, concurrent ingest, UI publication budgets and detail-state isolation remain separate work.
