# 0025 — Bounded RAM and persistent thumbnail caching

- Date: 2026-10-21
- Status: Implemented; delivery evidence in the tracker/PR
- Supersedes the thumbnail cache budget in ADR 0002; Fit/detail limits remain unchanged.

## Context

The 115-photo repeat-browsing case exceeds the original 24 MiB thumbnail budget. Eviction then causes repeated original-file decoding. FastRawViewer documents decoded-cost RAM caches, persistent thumbnails, controlled prefetch and slow-media limits. We adopt cache reuse first; speculative scheduling needs separate measurements.

## Decision

Use about 1.6% of physical RAM, bounded to 64–256 MiB per window, for thumbnails. Move constant-time LRU bookkeeping into a lock-protected memory holder shared with the decode actor. A synchronous RAM-only lookup lets a view draw a hit without an actor wait or clearing an image first. Keep image/session/request-size identities and cancellation checks.

Add a shared best-effort local disk cache with a 512 MiB target. Persist lossless PNG pixels and original source-kind/dimensions, at most 480 pixels per edge, in versioned atomic binary-plist records. Hash source location, device/inode, size, mtime/ctime nanoseconds and requested size into filenames; validate source stamps before using/storing a result. Restrict cached image format, payload size and decoded dimensions. Do not persist Fit or rendered RAW detail, source EXIF, decisions or Photo edits. Draw current edits over cached pixels as usual.

Index owned files lazily; maintain accounting in memory and evict to 90% of budget after crossing the limit to avoid sorting/scanning for every new thumbnail. Cache failures never prevent source viewing. Clear only owned derived files through **View → Clear Thumbnail Cache**. Session RAM invalidation still requires Reload after external changes; disk uses metadata stamps, not source content hashing. Concurrent processes and unusual network timestamp behavior need further acceptance.

## Tradeoffs and validation

More RAM reduces eviction churn. Disk population costs extra encoding/write time on first use, but enables later original-decode avoidance. Budgets exclude visible images and decoder/framework/RSS costs. All eligible thumbnails are stored, rather than applying a generation-time threshold. Six new tests cover pixel/source-description persistence, replacement/corruption/missing sources, disk limits/clear/failure fallback, RAM LRU/session limits and concurrent immediate reads during eviction. Existing cancellation and worker/cache tests remain applicable.

Use the release synthetic benchmark and native repeat scrolling/relaunch checks recorded in the tracker. No fastest-viewer, RAW-rendering, frame-rate or large-library performance claim follows from these service measurements. No speculative prefetch, new RAW processing or decoder parallelism is introduced.
