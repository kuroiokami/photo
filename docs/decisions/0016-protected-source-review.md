# 0016 — Protected source review and verified decision handover

- Date: 2026-10-20
- Status: Proposed implementation design; source protection and workflow goals requested by the user

## Decision and rationale

Implement pre-copy culling as a durable, separately namespaced source-review session. Do not reuse normal pending-XMP decisions to simulate read-only behavior. Existing `WorkspaceState.persist`, `DecisionStore.save`, Retry/conflict actions, descriptive history and rename/recovery paths require an actor-side source-write policy, captured with each request and retained across windows/restart.

Keep familiar browsing/decision/Photo-local composition controls; gate source-changing organization until a working copy exists. Scan source inventory separately from preview workers, keep normal RAW browsing embedded-only, freeze an explicit reviewed copy plan and preserve the existing two-destination verification rule. Store relative locations and protected identities/fingerprints; do not resume a reformatted/replaced source by matching its name.

Handover binds the frozen review revision to new destination file identities after byte verification, with journaled stages spanning manifests, SQLite and destination XMP. Preserve original source-copy hashes and unrelated metadata; record derived sidecar digests separately. Publish destination arrivals only after durable local review transfer, distinguish pending metadata from delivery-ready state, and do not replay old source decisions over later destination edits.

## Alternatives and limits

Treating sidecar-write failures as a mode creates misleading errors and can write on retry. UI-only restrictions can be bypassed by queued work or a second window. Copying by the current visible filter can omit unreviewed photos unexpectedly. Filename/checksum-only identity transfer can attach decisions to the wrong copy. A single cross-filesystem/SQLite transaction is unavailable; explicit idempotent journal recovery is required.

See [the implementation plan](../PRE_COPY_CULLING.md) for user-facing choices, exact boundaries, reconnect behavior, delivery chunks and required tests. This record does not claim the feature is implemented. The release recommendation is tracked separately in [Distribution](../DISTRIBUTION.md).
