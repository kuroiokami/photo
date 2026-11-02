# 0053: Isolated session endurance checks

- Date: 2026-11-02
- Status: Implemented developer harness; bounded acceptance recorded in the tracker

## Decision

Exercise the production workspace, image pipelines, decision save queue and verified-ingest services repeatedly in `PhotoBench --endurance ROUNDS IDLE_SECONDS`. Generate 64 separate 1600×1000 JPEG files across two subfolders, and give every decision store, source-protection registry and operations journal an explicit private temporary location. A different app bundle identifier alone does **not** isolate Photo's shared Application Support database. Native checks in this pass use bundled samples and avoid file decisions and metadata writes.

Start with 32 verified copies, then publish another 32 arrivals while applying decisions. Deliberately dwell 20 ms in arrival callbacks to exercise concurrent culling; do not report that as ingest throughput. Alternate parent-with-descendants and single-subfolder scopes, index EXIF/decisions, request thumbnails and Fit images, draw full JPEG detail, and apply/Undo/Redo group decisions before idling. Check cache budgets, drained image/save queues and source/working/backup image hashes. Keep all file tasks joined and queued saves flushed before removing the private tree, including failure paths.

Compare independent expected decisions against a new store, then a fresh child process opening the same disposable SQLite database. This checks saved decisions surviving process recreation; sidecar recovery is still available and this does not isolate SQLite-only durability or test interrupted Quit/power loss. The existing failure/recovery tests remain necessary.

Record anonymous per-round RSS, open-descriptor counts and accounted image-cache bytes. RSS includes allocators/frameworks/models and these checkpoints are not peak bounds. Report observations rather than imposing an arbitrary leak threshold. The child verification command is an internal read-only helper; failure produces a nonzero exit and no acceptance JSON. No image data, filenames, paths, hashes or metadata values belong in the report.

## Validation and limits

Run a short smoke check and sustained rounds, record actual duration and all checkpoints, and inspect native lifecycle events alongside loaded previews after window recovery. Native automation may itself request a reopen while observing a closed window; correlate `reopenRequested`, zero-window state and `windowCreated` instead of treating repeated accessibility trees as proof that Close failed. Provider wall time does not measure Photo latency or time the app was running.

Ownership regressions verify that hundreds of completed save closures release their captured payloads and that a running background sampler does not retain its owner. No production termination, sleep, cache, save or rendering policy changes are introduced by this harness. Generated JPEG service work and bounded native sample checks leave real RAW pressure/worker endurance, sleep/wake, overnight runs, physical media and frame acceptance open. See [performance evidence](../PERFORMANCE.md) and [the tracker](../../PROJECT_STATUS.md).
