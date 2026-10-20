# 0019 — Frozen reviewed copying and destination handover

- Date: 2026-10-20
- Status: Implemented; acceptance evidence is maintained in the project tracker

## Decision

Complete the protected source review route with explicit All Photos, Picks Only, Everything Except Rejects and Current Selection scopes. Source-wide scopes inventory supported images and companions recursively and freeze decisions on the persistence actor without interleaved saves. Current Selection checks only its selected folders/physical identities and necessary family dependencies, without waiting for a whole-card scan. It does not inherit the current filter as an implicit copy scope. The summary distinguishes explicitly reviewed/unreviewed images, omitted unreviewed images (source-wide scopes), added RAW/JPEG companions, metadata files and source bytes per destination.

Keep unique same-folder RAW+JPEG pairs together by default; allow opting out. Conflicting added flags require explicit acknowledgement. All Photos already includes both, preserving independent decisions without invented conflicts. Ambiguous shared RAW sidecars and case-folded filename collisions stop planning. Existing source-sidecar changes require an explicit Use Updated Source Metadata choice; owned local decisions remain, and other fields come from the current source packet. Malformed packets are not rewritten.

Add optional ownership/revision fields to existing source-review JSON rows. Older explicitly reviewed rows conservatively own both decision fields. New actions track rating and flag ownership independently, including explicit clears, and Undo restores ownership. A copy snapshot contains identity, exact decisions, owned fields, composition, explicit-review state, revision and sidecar digest. Source fingerprint/identity and metadata baselines are checked before/after copying. Later source decisions never alter an in-flight plan; changed included revisions are reported afterward.

## Durable stages

Save an immutable plan in Application Support/Photo/Operations before copying. Append and synchronize per-file original SHA-256/verification events rather than rewriting an ever-growing JSON document for each image. Both destination provenance logs are durable before the corresponding local verification acknowledgement and before publishing a family. Preserve original source checksums; derived destination XMP is not represented as source-identical. At successful completion materialize the ordinary `.photo-ingest.json` records once. An incomplete final event is unacknowledged, trimmed on the next append, and reverified; earlier malformed events fail closed.

Once an image family and required companions are verified at both destinations, one SQLite transaction binds both destinations' actual file identities to decisions, Photo-local composition, pending synchronization and idempotent transfer receipts. Existing unrelated local state causes a conflict rather than replacement. The receipts and normal pending decision rows precede destination-only XMP replacement. Merge only owned rating/flag fields; retain unrelated descriptive/develop metadata. Synchronization errors remain visibly pending; local review state can still be published. A digest match acknowledges a crash between XMP replacement and SQLite acknowledgement.

Resume Saved Copy reuses the exact source identities, choices and destinations. Revalidate original bytes and receipt-bound destination identities. Once receipts exist, later destination metadata (including deliberate removal), ratings and composition are not replaced by the older source packet/snapshot. Newer destination intent is preserved. Conflicts require the existing explicit destination-side resolution rather than an automatic overwrite. A new transfer of later source choices needs a newly reviewed list and fresh shoot folder; this first implementation does not reconcile a second snapshot over existing destination decisions.

The source stays open during copying; Review Copied Photos explicitly navigates to the first verified working folder, including during background copying. Verified arrivals remain limited to complete families with durable local review state. Source protection remains after completion. Later working-copy changes do not mirror to backup. Crop/rotation transfers inside Photo's local database, not Adobe develop settings or rendered pixels.

## Boundaries

The source and both destinations must remain connected for resume/reverification. No guessed relink, source erasure/eject, one-destination relaxation, continuous card watching, agency upload or RAW publication renderer. No unprotect command. Store both decisions.sqlite/source-protection.json and Operations when backing up local review/recovery state. A force-killed copy can leave hidden partial files; only verified final paths are used on resume. Representative 10k/40k concurrency, physical removable-media interruption, broad VoiceOver and cross-platform/macOS acceptance remain unmeasured until evidence says otherwise.

Normal decision rows now distinguish explicit user intent from a read-only cache seed. After a crash, opening a folder can seed cached decisions/descriptions before resume; those unchanged, explicitly read-only rows may receive the frozen review. Any real decision save, image-edit row, pending descriptive intent, mismatching baseline or legacy/unknown intent remains a conflict. The eligibility check is repeated inside the destination transaction to protect against another store/window committing intent during preparation.
