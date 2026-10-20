# 0012 — Publish verified ingest families without reloading

- Date: 2026-10-20
- Status: Accepted

Normal ingest publishes an explicit approved-image list after both destinations, source identity and durable manifests verify. Same-directory unique RAW+JPEG families and matching companions complete together. Companions still copy first. Keep existing file-operation path/collision protections unchanged; a separate canonical path helper stabilizes not-yet-created ingest roots through existing symlink ancestors.

Workflow coalesces arrival events and merges only the currently browsed destination folder. First publication opens once; browsing elsewhere is respected. Opening active destination folders is restricted to approved images. Completion/cancellation flushes publication. Workspace merges preserve session/cache, focus, decisions and Undo; collection revisions reject stale sort results. New metadata/decisions load asynchronously and active decision filters wait for known values.

This is destination publication during a snapshot ingest, not a continuous source watcher or an automatic backup of later edits. Ordinary external filesystem changes still require Reload.
