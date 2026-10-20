# 0013 — Durable owned-field metadata batch history

- Date: 2026-10-20
- Status: Accepted

Preflight every reviewed target identity and owned value before committing all local metadata intent and one Undo record in a shared SQLite transaction. Journal only owned before/after values, file references and synchronization identity; do not duplicate unrelated XMP/embedded packets. Retain the latest 20 batches; a new batch clears Redo. Explicit Workflow buttons show fields and physical counts, independent of text/culling Undo.

Undo/Redo preflight the whole batch against expected owned values and identities. Preserve current unowned fields, independent decisions and unrelated XMP. Later owned external edits or missing/replaced files stop replay. History persists across restart; renames can make stored paths unavailable until names are restored.

Local transactionality does not imply multi-file filesystem atomicity. After local commit, coordinated preserving sidecar writes run independently; cancellation/errors leave durable pending intent for retry. Cancellation before commit records no batch. Existing malformed/ambiguous/conflict protections continue to govern sidecars.
