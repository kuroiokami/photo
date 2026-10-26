# 0033 — Combined shoot browsing and isolated workspace regions

- Date: 2026-10-26
- Status: Implemented; validation and delivery evidence in the tracker/PR
- Extends ADRs 0002, 0004, 0031 and 0032. No image decoding, cache budget or persistence durability change.

## Context

Large shoots normally span card, date and event folders. A 40k single directory is useful as a stress case, but it should not define the normal workflow. The prior native scale checks also found excessive view-graph/layout work while indexing; per-photo records alone did not prevent header, preview and status reads from registering on the parent workspace body.

## Decision

Expose **Include Subfolders** beneath the active folder name. Start with direct files, preserve scope while clicking folders within the window and reset it on relaunch to avoid an automatic whole-home scan. Scope changes use existing session cancellation/reload semantics. Enumerate recursively on the file-access actor, excluding hidden entries, packages and symbolic links, propagating traversal errors and checking cancellation. Keep the legacy shallow API and an explicit unsupported fallback for providers without recursive capability.

Sort by the existing native filename comparison with deterministic path ties. Retain full-path item IDs and file identities, and compute relative labels once per containing folder. Matching basenames from different folders remain independent; existing family grouping stays within a single folder. Filters, selection, decisions, metadata, workflow scopes and copy planning consume this collection without flattening physical folders.

During ingest, gate the active destination subtree by verified-image membership even when the chosen combined folder is an ancestor. Preserve unrelated existing photos outside that subtree. Publish verified arrivals from descendants without resetting the preview session, and recheck session/context after asynchronous protection checks. Completed verified arrivals still publish from the final flush of a cancelled ingest caller; session changes, rather than that caller’s cancellation, reject stale publication. Source-protection registry/file checks must not wait on filesystem mutation locks on the main actor. A combined collection must have one source-review context; protected roots may include their own descendants, but mixed protected/working or separate protected collections fail closed. A mid-index context change invalidates the collection. Avoid republishing an identical review context on every batch.

A recursive Trash plan composes existing per-folder plans. Keep ownership snapshots separate, place every image before every sidecar, validate all affected inventories/files before the first move and recheck every affected inventory before companion moves. Preserve source guards, expected fingerprints, partial-failure reporting and recoverable Trash behavior. Confirmation uses source-relative names so duplicate filenames can be reviewed accurately.

Evaluate header/progress, selected preview and saving status inside small `WorkspaceRegion` views. Their closures read observed values in the child body; the parent no longer subscribes to those frequent counters/dictionaries. The contact sheet retains its own observable dependencies and per-photo records. Do not use broad Equatable suppression or cache view values that could hide legitimate changes.

Extend the read-only scale harness with `--scale-tree`; schema 2 identifies recursive scope. Keep process/database freshness, original hashes and RSS caveats. Test distributed shoots as well as single-folder stress cases. Native input completion, sampled CPU weight and presented frames remain distinct measurements.

## Validation

Regressions cover traversal exclusions/cancellation, duplicate names and pairing, cross-folder decisions/filtering/Undo, verified destination/ancestor visibility, new arrival labels, protected contexts and mid-index activation, composite Trash ownership/staleness/source guards, and header-vs-grid Observation rendering. Native scope, scrolling, decisions and confirmation checks plus measured limits belong in the tracker and performance notes. Synthetic repeated gradients are not real-camera, physical-card or physical-trackpad acceptance.
