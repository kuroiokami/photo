# 0029 — Append-only ordinary-ingest records

- Date: 2026-10-21
- Status: Implemented; local acceptance passed, exact-head delivery evidence belongs in the PR
- Extends ADRs 0006 and 0019; source protection, verified copying and family arrival policy remain.

## Context

Ordinary ingest encoded, atomically replaced and synchronized two complete growing JSON manifests after every source file. Aggregate manifest payload grew quadratically with file count. Reviewed copying already uses append-only provenance, but its frozen-plan/decision-transfer protocol is distinct and remains unchanged.

## Decision

Keep `.photo-ingest.json` as a compatible consolidated snapshot. During ordinary ingest append one complete JSON-line `IngestRecord` to `.photo-ingest.events` in each destination after both copies and the source fingerprint pass existing verification. Use one open actor-confined writer and reused encoder per destination. Synchronize each append and its parent directory before publishing progress or family arrivals. No relaxed durability, skipped checksum, background acknowledgement, source mutation or new dependency.

Read legacy snapshots, then replay complete journal records. Every journal starts with a version and fresh UUID. The snapshot stores its covered journal UUID/byte offset. Consolidate once before and once after a run per destination. Write and synchronize the snapshot first, then remove the covered journal and synchronize its directory. If interrupted between these steps, replay skips the covered prefix, including obsolete pre-rename destination mappings. A new journal UUID starts a fresh replay even when the snapshot retains an older cursor. Manifest readers in rename and reviewed copying share this replay/checkpoint path.

An unterminated final line (including an unfinished header before any acknowledged record) is unacknowledged and can be discarded during recovery; retry still verifies actual copies. Complete malformed rows, unsupported versions, invalid cursors, symlinks, changed journal identity/length and write/synchronization failures stop the operation. A completed append in only the first destination never publishes arrival; retry re-verifies both actual targets. Completed image bytes and existing metadata-preservation/collision behavior remain authoritative.

## Validation and limits

Seven regressions cover legacy renamed-manifest compatibility, invalid cursors, append-prefix preservation with unchanged snapshots across 24 progress callbacks, both-copy/source equality, cancellation/restart, torn header/record recovery, snapshot-before-unlink interruption, new journal generations, complete corruption/version refusal, replaced second-destination journal failure and symlink protection. Existing rename/re-ingest, metadata preservation, family arrival and reviewed-copy recovery tests remain required.

`sh scripts/benchmark.sh --ingest-journal` uses 100/1,000 synthetic 4 KiB marker files and two disposable local destinations. It observes snapshot publications/payload bytes and journal growth, checks arrivals and all source/copy bytes, then re-ingests to check incremental verification. These are filesystem payloads, not physical device I/O, RAW throughput or UI frame measurements. Matched baseline uses the unchanged ingest implementation with the same benchmark-only harness. No physical removable-media fault or 10k/40k acceptance claim.

Use the updated app to resume an interrupted ingest; older builds do not replay the new event file. Completed consolidated snapshots retain the existing record format with an optional checkpoint field. The shared MediaOperations actor serializes operations; cross-process or independently instantiated concurrent writers to the same destinations are not a supported workflow.

Two alternating release pairs are recorded in [performance evidence](../PERFORMANCE.md#ordinary-ingest-journal--2026-10-21): 1,000-file encoded bookkeeping payload 743.79 MB → 2.77 MB, initial copy 18.87–18.93 → 10.36–10.69 seconds. All source/copy bytes and arrivals matched. Timing and payload limits above apply.

Local strict checks pass (174 registered Swift tests, 172 executed, two optional RAW skips), plus three Python analyzer tests and full repository checks for 187 files. Release packaging/signature verification and normal quit/relaunch pass. UI code is unchanged; disposable core/service tests exercise copying and recovery. Physical-media acceptance remains open.
