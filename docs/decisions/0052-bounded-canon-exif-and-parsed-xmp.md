# 0052: Bounded Canon EXIF and immutable XMP read results

Date: 2026-10-30
Status: Implemented; scoped validation in tracker, broader acceptance open

## Problem and measured scope

Canon CR3 first metadata access initializes ImageIO's RAW container route even though standard shooting fields live in small CMT1/CMT2 TIFF blocks. Repeated metadata-panel visits also parse unchanged sidecar XML again. Treat first shooting information, repeated panel visits, filesystem reads and native frames as separate workloads.

## Canon standard-field route

Use an original bounded reader for `crx ` BMFF containers, the known Canon metadata UUID and one CMT1/CMT2 pair. Skip other box payloads with validated lengths; allow at most 4096 box headers, 64 KiB per metadata block, 512 root IFD entries, 4096 bytes per wanted field and the existing buffered reader's speculative-read budget. Interpret only required scalar/string/unsigned-rational fields in the root directories. Never follow maker notes, sensor data, arbitrary IFD graphs or RAW rendering. Read operations can prefetch small header windows; this is not a claim of zero physical payload bytes read.

Require Canon make/model, valid orientation, consistent TIFF/EXIF dimensions and Exif 2.30/2.31/2.32. Reject duplicate wanted fields, unsupported types/counts/versions, invalid offsets, unterminated/non-ASCII strings, zero denominators, invalid timezone forms and extended ISO sentinels. Missing/empty standard shooting fields also fall back, allowing ImageIO to recover vendor-specific values. Unknown representations return to the existing ImageIO route. Cancellation propagates instead of starting fallback work. Other formats retain ImageIO. No new runtime dependency.

Pass these standard values into the existing typed/date parser, retaining missing-value/numeric behavior, UTC interpretation when no offset exists, fractional seconds, file identity/size/nanosecond before/after validation and per-workspace LRU/session scheduling. Expose fixed native-read/byte counters only. Initial EXIF never extracts XMP or decodes image pixels.

References: [TIFF 6.0](https://www.itu.int/itudoc/itu-t/com16/tiff-fx/docs/tiff6.pdf), [CIPA Exif 2.31](https://www.cipa.jp/std/documents/e/DC-X008-Translation-2019-E.pdf), existing Canon container readers and the [pinned independent LibRaw pilot](../RAW_BACKEND_REVIEW.md). Format facts are implemented independently; no vendor decoder source is copied.

## Parsed XMP results

DecisionStore owns a bounded LRU of immutable decision/descriptive values, lazily and independently parsed per packet. Default limits: 128 packets / 4 MiB of accounted packet bytes, value UTF-8 and fixed record overhead. Digest keys are checked against exact packet bytes before reuse. Existing baseline digests are carried into reads when available. A cache-disabled constructor supports same-code controls; errors and oversized results are not cached. Nil descriptive packets return the same empty value without constructing an empty XML document. One decision parse walks the XML element list once rather than three times.

Every operation still discovers, validates and reads current sidecar bytes. Pending intent, per-image identity, protected-source rules, ambiguity/symlink/size checks and external conflicts remain in the store. Identical packets can safely share immutable external values across images/windows using the same actor; local decisions and ownership are never cached by packet. No mutable XMLDocument is retained/shared. Merges and writes always parse the current packet afresh, preserving unrelated/develop properties and coordinated atomic publication. Existing read duplication and SQLite durability remain; filesystem snapshot reuse is deferred.

## Evidence and limits

[Optimized controls](../benchmarks/2026-10-30-metadata-indexing.json) retain fresh-process ImageIO/native/native/ImageIO Canon controls twice, plus generated cache off/on/on/off metadata-panel visits with identical filesystem/SQLite work. The public Canon reference checks dimensions, camera/lens, shutter/aperture/focal/ISO and offset/subsecond time. The current SDK omits ISO and original offset on that fixture; retain its failed complete ISO/time reference explicitly rather than claiming exact SDK equivalence. Pinned developer-only LibRaw independently agrees on numeric shooting/camera values; time conversion is checked against standard block bytes and generated offset cases. No LibRaw code is shipped.

Tests cover mixed endianness, eight orientations, positive/negative offsets, subsecond time, malformed/version/type/limit boundaries, sparse sensor skipping, cancellation, stale cache validation and ImageIO fallback. XMP tests cover lazy/copy-safe results, digest collisions, budgets/eviction/disable, malformed packets, empty-keyword overlays, cancellation, same-length external edits with restored modification time, sidecar removal/symlinks and pending conflicts. Existing source protection, history, crash recovery and preservation regressions remain.

Timings describe one real Canon fixture and generated panel workloads on local storage with warmed OS caches. Fallback checks do not establish improvements for CR2/ORF/Sony. Accounted cache bytes are not total RSS; process samples are not native whole-app bounds. Broad cameras/modes, physical media/frames, pressure/concurrent ingest, sustained sessions, macOS 14/Intel and distribution acceptance remain open.
