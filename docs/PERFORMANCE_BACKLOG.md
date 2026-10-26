# Performance implementation checklist

Last updated: 2026-10-26. This tracks the reviewed optimization suggestions against implemented code. **Partial** means the full suggestion has not shipped. The [project tracker](../PROJECT_STATUS.md) records current validation/delivery; [performance evidence](PERFORMANCE.md) separates service timings from native interaction measurements.

| Suggestion | Status | Implementation or remaining work |
| --- | --- | --- |
| 1. Narrow selection readiness observation | Implemented; validation in tracker | Separate observable Boolean readiness and per-photo display records, with an Equatable tile boundary; see [ADR 0031](decisions/0031-thumbnail-observation.md). File-backed scale runs corrected ready-set traversal and redundant snapshot rebuilds in [ADR 0032](decisions/0032-workspace-scale-profile.md); the [ADR 0033](decisions/0033-combined-shoot-browsing.md) follow-up passes synthetic 2k/10k combined and 10k flat scripted input checks, with physical-frame/40k acceptance still open. |
| 2. Ordinary-ingest manifest scaling | Implemented; local acceptance passed | Append records at both destinations, replay and checkpoint by journal generation/offset; see [ADR 0029](decisions/0029-ordinary-ingest-journal.md). |
| 3. Reuse SQLite prepared statements | Implemented; local acceptance passed | Bounded actor-owned query leases and shared default record coders; reset/bind/error/rollback, nested use and connection lifetime regressions. See [ADR 0030](decisions/0030-sqlite-statement-reuse.md). |
| 4. Disk-hit filesystem/property work | Open; proposal needs adjustment | Retain source revalidation across reads and pre-decode dimension bounds. A stamp captured before reading does not detect replacement during the read. Measure changes without removing these protections. |
| 5. Disk-cache lock boundaries | Partial | Disk-read decode is outside the accounting lock; optional writes are bounded/background. The final read touch still shares a lock held by writer filesystem/index work. |
| 6. Buffered CR3 container reader | Open | Bound and stream box parsing without per-header seek/read and integer arrays; preserve corrupt-layout bounds/orientation/cancellation/fallback. |
| 7. Shared/cached EXIF and XMP parsing | Open | Reader opens separate sources. Any shared result cache needs source identity/stamp invalidation and must preserve selected-photo priority. |
| 8. Cache selection summary | Implemented; validation in tracker | Cache summary over represented selected records; update decisions directly and rebuild membership on focus/selection/group/inventory changes. Unknown gating, mixed values, filters and Undo regressions; construction costs reported separately. |
| 9. First-selected lookup | Open | Still scans visible order. Choosing focused selectedID first can change semantics; preserve the intended first-in-visible-order result. |
| 10. Image task/cache overhead | Partial | Typed Equatable task identity shipped. Immediate RAM lookup remains in display and loading paths to avoid a loading flash and retain session/cancellation checks. |
| 11. Detail pan/zoom observation | Open | DetailPresentation remains one state value. Separate high-frequency navigation from image/loading/control state with linked-comparison tests. |
| 12. Duplicate tile labels/identity | Partial; identity retained deliberately | EXIF labels format once. Explicit photo IDs remain ScrollViewReader targets for keyboard selection reveal. Removing them requires an equivalent verified target. |
| Workspace indexing view dependencies | Implemented; synthetic acceptance passed | Child-body regions isolate header/progress, preview and saving status. Rendering isolation and synthetic 2k/10k combined plus 10k flat native input checks pass; see ADR 0033. |
| Native measurement gap | Partial | One earlier matched 1k pair exists. The new 2k Time Profiler export had no rows and was rejected; successful 2k/10k input/RSS checks are not CPU/frame comparisons. Usable matched captures, 40k/real shoots and physical-trackpad acceptance remain open. |

## Smaller suggestions

- GridItem array construction: open; measure before adding layout state.
- SupportedImageTypes static JPEG/PNG set: open; no throughput claim established.
- Sidecar existence/attributes/read consolidation: open; preserve regular-file, size, ambiguity and source-change checks. Memory mapping is a proposal, not an automatic improvement.
- Selected-family priority attempts during indexing: partial concern. Calls repeat, but ready/pending guards run before database actor access; the claimed repeated database round-trips are not established.
- Reviewed-copy freeze identity/sidecar reuse: open; final checks currently protect changes between review and freeze. Any reuse must retain those checks.
- RAM/disk URL normalization: open; reconcile aliases without broadening file-identity or cache-staleness behavior.

## Implementation sequence

1. Ordinary-ingest journaling and recovery/scaling evidence merged in [PR 29](https://github.com/kuroiokami/photo/pull/29).
2. Actor-owned prepared statements and record JSON coders merged in [PR 30](https://github.com/kuroiokami/photo/pull/30).
3. Narrow readiness/summary observation and selected tile dependencies implemented with observable invalidation/unknown-decision/group/filter/Undo tests and native interaction checks; final evidence in the tracker/delivery PR.
4. File-backed scale profiling and selection corrections are implemented in ADR 0032. The failed native indexing/control/scroll checks drove ADR 0033: isolate UI regions and add distributed-shoot scope/profiling. Synthetic 2k/10k combined and 10k flat input checks now pass; matched frame/CPU and 40k acceptance plus large-group costs remain open.
5. Then profile disk-cache locking, CR3 parsing, metadata reuse and detail navigation independently; representative shoot/memory/physical-trackpad acceptance remains open.

User-decision save batching is separate from prepared-statement reuse and initial-index transactions. Natural filename ranks already reduce repeated sort collation; the first locale-aware sort still uses native collation. Physical-media interruption, memory pressure and representative 10k/40k mixed-camera shoots remain acceptance work, not completed by synthetic service scenarios.

The [rapid-scroll row experiment](decisions/0034-contact-sheet-row-experiment.md) was withdrawn: repeated release process-CPU results did not establish a reliable gain. Only diagnostic tooling and findings remain. Rapid full-grid scrolling is unresolved; evaluate a bounded native collection view with usable frame/hitch evidence before accepting a replacement.
