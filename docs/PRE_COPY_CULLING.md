# Review before copying: implementation plan

Status: **protected review and reviewed copying implemented**. Updated 2026-10-20. Workflow → Ingest → Choose keepers before copying → Start Culling protects the source and keeps decisions local. Return through the source banner’s **Copy Reviewed Photos…** button, choose destinations/scope and **Review Copy Setup →**, then **Copy & Verify Both Copies**. Both verified copies receive ratings, flags and Photo-local composition. **Resume Saved Copy** reuses the frozen list after interruption; **Review Copied Photos** explicitly opens working copies. [ADR 0017](decisions/0017-source-review-only.md) records protection; [ADR 0019](decisions/0019-reviewed-copy-handover.md) records copying and recovery. Exact automated/native acceptance is in the tracker.

Protection stays active after copying; this release has no unprotect command. Captions/renaming operate on copies. A new transfer of later source decisions requires a new reviewed list and fresh shoot folder; resume never overwrites later destination work. Both source and destinations must be connected to reverify/resume. Physical card interruptions and representative 10k/40k performance remain acceptance work.

The original detailed design below explains the intended safety boundaries. The implementation uses immutable local JSON plans plus synchronized append-only per-file provenance at both destinations and local verification acknowledgements, with SQLite destination receipts/intents (ADR 0019); the older all-SQLite journal wording is a design alternative. Source-wide counts are complete only after indexing; Current Selection deliberately leaves other source photos uncounted.

## Workflow and safety design

Workflow starts with **Copy everything** or **Review before copying**. Direct folder browsing stays available.

1. **Choose your card or source folder.** Show its name and subfolder tree immediately; load the selected folder’s embedded previews without waiting for a whole-card scan.
2. **Choose keepers.** Reuse Preview/contact sheet, stars, flags, comparison, zoom and Photo-local rotate/mirror/crop. Display a persistent **Reviewing source · Saved on this Mac · Source unchanged** banner. Keep P/X/U, 0–5, Undo and batch actions familiar.
3. **Review what will copy.** Offer the choices below with file/family counts and estimated bytes, then Photo folder, Backup folder and Shoot name. Preserve the source’s subfolder layout.
4. **Copy and verify.** Freeze the reviewed copy list and decision revision. Transfer review decisions to both copies as families complete. Allow early review of copied photos after verification.
5. **Name, caption and deliver or edit.** Use the existing reviewed rename, field-specific IPTC and delivery tools on the working copy. Lightroom is optional.

Before choosing a source, explain that review work is kept on this Mac and is not yet a backup of the photographs. Ordinary source files, sidecars and folder names must never be changed by this mode. Filesystem/device access can update system-maintained access information; this is an app-level no-write policy, not a forensic write blocker.

### Make copy scope explicit

| Choice | Meaning |
| --- | --- |
| All photos — default | Copy every supported photo discovered in the chosen source, including rejects and unreviewed photos; useful for preserving a complete shoot |
| Picks only | Copy files/families currently marked Pick, including flags read from existing metadata; show separately how many were reviewed in this session |
| Everything except rejects | Include unflagged and unreviewed photos; exclude explicit rejects |
| Current selection | Freeze the exact selected physical file identities, independent of later filters or navigation |

These are source-wide choices across its subfolders, not an accidental snapshot of the currently filtered screen. “Current selection” is the deliberate exception. Source-wide scopes wait for complete inventory and any decision indexing they require; do not treat unknown flags as unflagged. A frozen Current selection can proceed as soon as its own identities and required family/metadata dependencies are validated, without waiting for the rest of a 40k-photo source scan. This is the earliest deadline-oriented route. Expose **unreviewed photos left on source**, unsupported files and conflicts before starting. Do not label unflagged files as rejected or imply that unreviewed photos were inspected.

A photo is explicitly reviewed when a user makes a decision, including an explicit clear; loading its preview or moving past it does not count. Existing imported stars/flags can seed decisions but do not mark a photo reviewed in this session. Distinguish **Unreviewed** from **Reviewed, unflagged** in the copy summary. Undo restores review state together with its decision.

Unique RAW+JPEG pairs can copy together through an explicit **Keep RAW+JPEG pairs together** option, initially on. Expand the plan to show exactly which companions this adds. If a restricted scope selects one companion and pair expansion adds a companion with an opposing flag, require a review choice. All photos already includes both and preserves their independent decisions; do not invent a conflict for that scope. Never infer grouping across folders or ambiguous same-stem RAW files. Required XMP/ACR metadata companions follow included images even when pair expansion is off.

Use the current two-verified-destination policy for the first implementation. A deadline mode that copies to one destination before backup would be a separate, explicit durability decision, not a hidden relaxation.

## Storage and source protection

### Separate review records from working-file decisions

The first chunk stores per-file review items in Application Support SQLite, with a small synchronized JSON registry for cross-service source protection (ADR 0017). Before copying ships, extend this with reviewed-scope/revision/location data and durable copy handovers. Do not put review decisions into the normal `decisions.pending` or descriptive metadata pending queues: those records mean a future sidecar write, whereas source review intentionally has none.

The first chunk stores full decisions, Photo-local composition, explicit-review state and initial sidecar digest/warning, keyed by session UUID and protected file identity. Copy-ready records additionally need source-relative locations, reviewed-field ownership and revisions. Store only overridden decision fields when merging into a copy. Existing source metadata is read, not rewritten. Do not silently inherit unsynchronized normal-workspace intent; identify it separately if present.

Show **Saving review…**, **Review saved on this Mac**, or a real local-save failure. Saving, Undo and normal-quit draining use the existing queue/barrier, but a review save has no XMP retry or conflict-resolution action targeting the source. Local review survives app restart; session Undo can remain session-scoped initially. Session data is not lost when the card is temporarily absent.

### Enforce the policy below the UI

The current normal save path is `WorkspaceState.persist` → `DecisionStore.save` → coordinated XMP replacement. `loadImageState` also reads normal decision records, and `retrySync` calls the same saving path. Merely hiding a Retry button or pretending that the card is read-only is insufficient.

Introduce an explicit workspace access context: working folder or protected source review with session ID. Capture it with each queued request, not from whichever folder is active when the task executes. Persist protected source locations independently of the open window. Opening/reloading a protected source in another window, restoring it after relaunch, or selecting a child folder must preserve review mode.

Centralize checks before any source-side mutation: decision/XMP save and retry/conflict actions, metadata batches and persistent metadata Undo/Redo, rename/recovery, copy/handoff destination creation and any future exporter. Resolve canonical paths and use file identities where available to cover path aliases/hard links. Check actor-side immediately before mutation; UI disabling alone is not protection. Install the source guard before draining queues: quarantine not-yet-started source writes, block new ones and wait for already executing operations through the decision/file-operation barriers. Do not report the mode protected until that handover finishes. Entering review must not flush queued XMP writes onto the card. Pending old records remain local and cannot be retried against the protected source.

Disable descriptive IPTC editing, renaming and other source-changing workflow actions in the first review chunk, with **Available after copying** help. Composition is permitted because it saves only in the session; it must not fall through to normal source state. Closing/finishing a review does not silently remove source protection. Re-enabling ordinary writes needs an explicit separate user action, outside the first review flow.

No source manifests, hidden review files, card deletion, erasure or eject automation. Persist review data only under Application Support; destinations must remain outside protected source locations.

## Identity, reconnection and speed

Use a session UUID and available persistent volume/directory/file identifiers, with relative locations and replacement fingerprints. A card’s label or a matching filename is not enough to resume. Reconnect to the same source only after validating those bindings. If identifiers changed or are unavailable, offer an explicit relink/review process rather than guessing. Reformatted/reused media and replacement files must not inherit decisions automatically.

These fingerprints are replacement safeguards, not cryptographic proof that bytes never changed. Keep SHA-256 verification during copying and recheck fingerprints before/after reads. If a prior content hash exists, compare it too. Ambiguous reconnections must stop decision transfer. Do not hash 40k RAWs, demosaic, recursively decode previews or build all thumbnails before the first selected preview. Reconnecting/copy planning can validate file bindings in the background, selected photo first, and must label incomplete indexing.

Subfolder navigation stays shallow. A cancellable metadata-only source scan builds the source-wide copy summary; it never takes an image worker. Keep separate image workers/cache budgets and demand-only detail decoding. Completing a scan updates counts without repeatedly shuffling the visible grid. Copying may consume card bandwidth; measure preview responsiveness under concurrent copy, not just idle browsing.

## Frozen copy plan and handover

Extend `MediaOperations.ingest` to accept an explicit immutable plan rather than always calling its private recursive `ingestFiles` scan. Record session ID, source bindings, decision revision, chosen physical files/families, dependencies, source-relative destinations and options. Validate all paths, collisions, identities and available destinations before beginning. The current overlapping-folder and symlink protections still apply.

A family proceeds through these durable stages:

1. **Planned:** exact members, decisions/edits and baseline metadata fixed for this copy.
2. **Bytes verified:** original image and companion copies verified at both destinations against source hashes; source fingerprints still match; both copy manifests durable.
3. **Review applied locally:** bind to the new destination identities and transactionally record decisions, Photo-local edits and per-destination pending synchronization in SQLite. Never key transfer solely by filename or checksum; identical images can have different decisions.
4. **Metadata synchronized or visibly pending:** merge only reviewed flag/star overrides into destination XMP, retaining unrelated metadata/develop settings. Record each destination’s result and derived sidecar digest. Original image bytes remain source-identical; a changed destination sidecar is no longer described as byte-identical to the source sidecar.
5. **Published:** emit verified arrivals only after byte verification and durable local review state. A sidecar failure can still permit culling with an explicit pending status; **Ready to deliver** requires required metadata synchronization. Show which backup metadata writes remain pending.

The existing ingest manifests identify original source checksums. Preserve that provenance and add a separate handover/derived-metadata record; do not replace a source checksum with the edited XMP checksum. Integrate with the existing re-ingest rule that preserves later destination metadata. On resume, do not replay an older review snapshot over newer destination decisions or captions; revision/identity/baseline conflicts need explicit resolution. A crash after XMP replacement but before acknowledgement can be recovered by comparing the intended fields/digest.

The manifest and SQLite database cannot form one filesystem-wide transaction. Use the handover journal to reconcile each idempotent stage after restart. Cancellation retains verified files and pending records, never deletes card files, and distinguishes **bytes copied**, **review saved**, and **metadata ready**. A partial failure in one destination cannot be summarized as fully backed-up metadata.

Source review may continue while a frozen copy plan runs, but later revisions are not silently added to that copy. Show **Changed since this copy started** and offer a reviewed subsequent transfer after the current plan completes. Once the user enters a destination collection, its new decisions belong there. Do not automatically switch away from an actively reviewed source; provide **Review copied photos** and preserve the current source position.

Photo-local crops/rotation/mirroring transfer to both copies in Photo’s database. They still do not become Adobe develop settings or rendered JPEG output. The backup is an initial snapshot of review state, not continuous mirroring of later working-copy edits.

## Delivery chunks and acceptance

| Chunk | Work | Required proof |
| --- | --- | --- |
| 1. Protected source review — implemented; validation in tracker | Durable review store/context, guarded mutations, familiar culling controls, source banner, child navigation and restart | Writable disposable source still has identical directory listing and image/sidecar hashes after stars/flags/Undo/retry/metadata/rename attempts, relaunch and second-window tests |
| 2. Reviewed subset copy — implemented | Source indexing, explicit scopes/family expansion, frozen plan and reviewed counts | No filtered-scope surprises; unreviewed accounted for; grouped/conflicting/ambiguous pairs, missing files, destination overlap/collisions and source replacement covered |
| 3. Verified handover — implemented | Destination identity mapping, local edit/decision transfer, preserving XMP and recovery journal | Both copies retain independent stars/flags/crops, unrelated XMP/ACR survives, source unchanged; failures/crashes at every stage recover without overwriting newer destination edits |
| 4. Guided native flow and scale | Resume/reconnect, source/destination navigation, publication/editor next steps and performance | Native keyboard/VoiceOver workflow; real disposable card unplug/reconnect; 10k/40k inventory, scrolling, first-preview/p95, save queue and concurrent-copy measurements |

Protected review, explicit subset planning and verified handover are implemented. Physical-card/native/scale acceptance remains separately tracked. Do not weaken decision transfer or claim unmeasured performance. Use synthetic or redistributable fixtures for automated tests; run destructive/interruption experiments only on disposable media/copies. Existing original-byte, cancellation, stale-result and full-detail budget checks remain required.

This plan does not implement FTP/upload, a one-copy deadline mode, RAW-to-JPEG publication rendering, Lightroom crop exchange or continuous source watching.
