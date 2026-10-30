# 0049 — Prepared rating keys and less repeated bulk-action work

Date: 2026-10-30

Status: Implemented; strict local regressions and matched generated controls pass; scoped native functional/hash/XMP acceptance passes; locked-screen restart/cleanup unverified.

## Decision

For Rating order with a complete filename-rank map, decorate each photo once with its rating (default zero) and existing native filename rank. Sort integer keys, then recover photos. This avoids repeated Unicode-ID hashing and unrelated metadata lookups in each comparison, preserving arbitrary integer API values, native digit/Unicode/filename-ID ties and missing ratings. Empty/incomplete rank maps retain the general comparator; no replacement natural-sort algorithm or normalization is introduced. Temporary per-row records add allocation; no RSS/peak-memory reduction is claimed.

Flag-only actions do not reorder Rating views when stars remain unchanged. Undo/Redo compare the restored value against the current live stars before deciding whether to reorder, so an intervening external synchronization is not ignored. Decision/source-field/history semantics, filter rebuilding and focus rules remain synchronous. Capture operation targets once, rather than expanding the same selected files twice. Reconcile selected IDs only when an ID has actually left the visible index.

Select All already owns the exact visible rows: supply them for its one synchronous ungrouped summary refresh instead of looking every selected ID up again. Clear the temporary target reference with defer; grouped selections still expand physical companions. No asynchronous user-action transaction, new save barrier or cache/persistence change is introduced.

## Evidence and limits

Strict checks register 277 Swift tests, execute 275 and skip two optional RAW cases. New regressions compare prepared/general Rating order with Unicode/duplicate filenames, missing/arbitrary ratings and incomplete ranks, and verify multi-photo flag history under rating/min-star filters with empty/return neighbor selection. Existing grouping, source ownership, external conflicts, snapshots, auto-advance, cancellation and durability regressions pass.

Identical optimized public-API harness source is separately linked against accepted/candidate core objects. Quiet baseline/candidate/candidate/baseline runs use 10k/40k generated ASCII and Unicode sample IDs, varied starting stars and a full selection. No image/sidecar/database-record writes. Check values/focus/history outside timed actions. Retain all reports in [the benchmark artifact](../benchmarks/2026-10-30-bulk-actions.json), with separate select/flag/rating/Undo/Redo costs. The same operations are available as PhotoBench --bulk-actions.

These are synchronous model timings, not displayed frames, file-save completion, physical camera/media or pressure/long-session acceptance. Large Unicode batches still cost time; filename-rank construction and first-selected lookup remain separate work. Native and delivery evidence belong in the tracker/PR.

Isolated signed release `987347F9-2D04-3D38-BAEC-70543B300E46` verifies 65 selected Unicode JPEGs in Rating order: independent stars/flags, flag and rating Undo/Redo, Picks/min-four-star removal by rejection, Undo restoration, Redo removal and Clear Filters. All 65 original hashes match; all sidecars contain Rating 4 plus independent reject fields pick -1/good false. A native automation timeout was recovered through fresh state and separate actions. The Mac locked before normal Quit/restart and shortcut cleanup; an asynchronous unlock request is pending. Do not claim restart/cleanup complete.
