# 0042: Reuse validated EXIF and embedded XMP reads per workspace

- Date: 2026-10-27
- Status: Implemented; broader camera/media acceptance remains open

## Evidence and decision

EXIF and embedded XMP opened separate ImageIO sources. Workflow refreshes also constructed new readers, discarding any opportunity to reuse unchanged image information. Keep one actor-owned reader in the workspace's retained WorkflowModel and use it for browsing, workflow refreshes, rename information and verified arrivals. No global cross-window cache or new dependency.

Cache typed EXIF and serialized embedded XMP independently and lazily. Ordinary EXIF indexing never extracts XMP. The default LRU holds at most **128 entries / 4 MiB of accounted results**; oversized entries bypass it. Accounting includes field strings, packet bytes and fixed per-entry overhead; path keys, allocator/dictionary overhead and ImageIO allocations are separate. This is not a whole-process memory limit. Cache unavailable descriptive values without inventing metadata; ImageIO can synthesize structural XMP for an otherwise untagged PNG.

A single actor-isolated ImageIO source can serve adjacent requests for different fields. Release it when both fields are cached, on invalidation/clear, or after idle expiry. One weak background sleeper serves a stream of requests, rather than creating one task per indexed photo. The reuse deadline is two seconds; periodic cleanup normally releases within roughly two to four seconds after use, with system scheduling/App Nap able to defer cleanup. Expired sources are never reused. Pixel caching remains disabled and no image/RAW rendering call is added. Opaque ImageIO memory is not counted in the result budget.

## Freshness, cancellation and scheduling

Each eligible regular file has a standardized-path key plus device, inode, byte length, nanosecond modification time and nanosecond change time. Validate before reuse and after reading, including cache hits. Changed/deleted/replaced files invalidate cached fields and matching source objects; changes during a read throw a recoverable file-changed error. Unstampable/symbolic aliases keep an uncached read path. These checks depend on filesystem identity/timestamp fidelity, not content hashing.

Keep ImageIO objects actor-isolated. Check cancellation before work and before publication. Explicit Reload clears reader state; an epoch prevents an old expiry task from clearing a new lease. Workspace session/selection guards, selected-photo-first indexing and per-file yielding remain. Opaque work already running cannot be preempted. Workflow operations submit one file at a time; there is no eager whole-folder XMP pass or new speculative queue.

Only original-image results are cached. Sidecar discovery, XML parsing/merging, pending intent, source protection and conflict/write validation stay in the existing persistence path. A cached embedded packet must not mask a new, changed or removed sidecar. No image bytes or database schema are changed.

## Validation and limits

Regressions cover both query orders, repeated calls, bounded LRU/oversized bypass, exact-size/mtime-preserved replacements and in-place edits, changes during reads/cache validation, failed reads, uncached symbolic aliases, cancellation, source idle expiry/weak lifetime, clearing and real workflow refreshes after external sidecar edits. Existing date/offset, sorting, selected-priority, metadata Undo/conflict and original-preservation checks remain.

`sh scripts/benchmark.sh --metadata-reads` uses generated JPEG/PNG only and compares current-reader reuse off/on/on/off. Cold EXIF, paired queries and repeated panel visits are separate. Validate returned values and every original hash. See [results and native acceptance](../PERFORMANCE.md#validated-metadata-read-reuse--2026-10-27).

The controls are small metadata-service workloads with uncontrolled OS caches/background load. They are not a historical executable comparison, full UI/frame measurement, cold RAW initialization improvement, physical-media throughput, peak RSS or representative large-shoot result. First ImageIO RAW metadata initialization, downstream sidecar XML parsing, cross-window sharing and broad camera/media acceptance remain separate work.
