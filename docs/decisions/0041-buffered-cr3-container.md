# 0041: Buffer bounded Canon CR3 header reads

- Date: 2026-10-27
- Status: Implemented; camera/media acceptance remains limited

## Decision

The existing PRVW reader seeks and reads separately for each small container field and builds temporary arrays to decode integers. Keep its format logic, embedded JPEG path and bounded box indexes; introduce one request-local FileHandle reader with a **4 KiB** window. A total **1 MiB** speculative-byte budget bounds read amplification on sparse layouts; once exhausted, exact reads continue. Large payload reads bypass the window. Existing limits remain: 10,000 boxes, 64 KiB CMT1 metadata and a 64 MiB embedded JPEG. Box sizes skip sensor payloads rather than loading a whole RAW.

Check cancellation on cached reads and before/after blocking I/O. Keep the reader/callback inside synchronous decode using a scoped nonescaping adapter; no pipeline API or concurrency changes. Decode big/little-endian integers directly without temporary arrays. Preserve all extent/overflow checks, orientation transforms, source-stamp/session validation and unknown-layout embedded-only fallback. Never add implicit RAW rendering.

A 32 KiB pilot reduced calls but read noticeably more data without a measurable warm-preview latency gain; use the smaller window to limit that tradeoff. This is a bounded-I/O implementation, not a new camera decoder or an asserted UI speedup.

## Validation and measurement

Tests cover adjacent/boundary reads, negative/overflow/truncated ranges, cancellation on cache hits, large-payload bypass, a capped sparse read-ahead workload, extended/zero-size/oversized boxes, box-count limits, skipping a 128 MiB sparse sensor payload and exact preview/orientation equivalence. Existing explicit pipeline-cancellation and all eight ImageIO orientation controls remain.

`sh scripts/benchmark-canon-container.sh /disposable/public-eos-r.CR3 /tmp/canon-container.json` verifies the documented CC0 fixture hash before and after a release test. It alternates thirty buffered/unbuffered pairs after three warmups per mode, using the same current parser/JPEG decode. The control isolates buffering; it does not restore the old integer-array implementation. Report actual read counts/bytes, medians and nearest-rank p95, with source hashes unchanged.

See [measured results](../PERFORMANCE.md#bounded-canon-cr3-container-reads--2026-10-27). OS caches and background load are uncontrolled. No first-paint, full RAW rendering, physical-media, broad-camera, memory-peak or scrolling claim. ImageIO EXIF/XMP parsing still opens separate sources and remains a separate invalidation/priority-sensitive optimization.
