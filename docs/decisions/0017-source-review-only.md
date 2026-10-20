# 0017 — Protected source review, first implementation

- Date: 2026-10-20
- Status: Accepted for review-only; subset copying and handover remain planned

## Decision

Implement the first independently usable chunk of [the pre-copy design](../PRE_COPY_CULLING.md). Workflow → Ingest → Review Before Copying installs persistent source protection before draining the normal decision queue, then opens the source with familiar culling/composition controls. A persistent banner explains that reviews stay on this Mac and copying them is not available yet. Source-changing organization is disabled and the underlying services reject it too.

Per-file source decisions, explicit-review state, Photo-local composition and initial sidecar baseline/warning live in the additive SQLite `source_review_items` table, keyed by source session UUID and the existing protected file identity. They never become normal pending-XMP records. Initial sidecars are read only; malformed metadata produces a visible warning and does not stop local culling. Initial unreviewed entries are persisted during background decision indexing; 10k/40k indexing cost still needs measurement. Explicit clears count as reviewed, and decision Undo/Redo restores that bit. Image-only edits do not mark a photo as explicitly rated/flagged.

For a synchronous boundary across metadata and file actors, a small independent `source-protection.json` registry lives beside the database. Its records contain source UUID, canonical folder and directory binding (volume UUID where available, inode and creation time). Atomic registration synchronizes the file and containing directory before success. This is a deliberate refinement of the original all-SQLite proposal: a synchronous policy can cover filesystem mutations without actor reentrancy between a permission check and the write. The registry and SQLite must both be included in backups.

`SourceProtection.withWritable` holds a shared recursive lock across each mutation within the running Photo process. It guards normal decisions/XMP retries and conflict actions, metadata writes/history, local normal-edit saves, rename/recovery, copy directory/temporary/publication/manifest writes and derived-image export. Large copy reads/hashes run outside this lock; guarded chunks are at most 1 MiB so a whole RAW copy cannot monopolize source checks. Registry contents are cached against file identity/modification/size, not decoded for every indexed item. Corrupt data, disappearance of a previously loaded registry and unavailable source-directory identifiers fail closed.

Paths are canonicalized through existing ancestors. Known directory bindings retain protection when a source moves within its volume. Reusing a source location requires a new review; old source sessions/bindings remain protected and new file fingerprints do not inherit prior decisions. Multiply-linked regular files are conservatively blocked for normal mutations whenever source protection exists, including unrelated hard links. There is no unprotect command in this chunk. Other applications, manual local-data removal and another independently running Photo process are outside this process-level policy; this is not forensic media write blocking. Ambiguous remounts/relinking remain future acceptance work.

Workspaces publish photos before waiting for the persistence actor, and each protected decision entry carries its source context before controls become actionable. They restore protected context on open/reload/relaunch and through child folders. Starting a review notifies other windows to reload only if their current folder is protected; already queued normal writes still encounter the service boundary and cannot turn into review writes. The review entry waits for existing file operations, and rejects sources overlapping Photo’s local state. SQLite writes use the existing normal-quit queue/barrier. UI status separates saving, locally saved reviews and actual errors; it never offers XMP retry for review-only decisions.

## Deliberate boundary

Normal ingest and handoff reject protected sources (including a broader source containing a protected child). Their current all-file copy path cannot transfer the new review records. Do not expose a copy button that discards reviews. Destination organization remains available in ordinary working folders. The next chunk adds frozen reviewed scope and journaled identity/metadata handover to both verified copies before enabling this path. Source-local composition is not Adobe crop exchange or rendered output.

## Validation

Required checks and exact automated/native outcomes are maintained in PROJECT_STATUS.md and UX_REVIEW.md. Tests exercise separate store instances/windows, queued normal intent, pre-existing pending XMP, explicit clear/Undo/grouping, stars/flags/composition/restart, metadata history/retry, rename/recovery, copy destinations, aliases/hard links/moved/reused roots, replacement files, damaged registry and derived-image protection. Personal images must not be used for mutation tests.
