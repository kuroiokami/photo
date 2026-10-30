# 0051: Explicit camera-preview inspection in an isolated worker

Date: 2026-10-30
Status: Implemented; targeted real-camera/native acceptance recorded in tracker

## Context

The LibRaw pilot found larger embedded camera JPEGs than current Fit previews in the tested Sony/Canon files. Camera JPEGs can help focus decisions without demosaicing RAW, but may be smaller than the sensor and reflect camera processing. Repeated in-process JPEG decoding also showed high RSS despite releasing returned images. A decoded-image limit alone cannot bound SDK/transient process allocations.

## Decision

Add **Camera Preview / ⌥Z** as an explicit per-photo inspection source. Label verified color-JPEG payloads **Camera JPEG**, other embedded-only results **Embedded preview**, actual dimensions and magnification **of preview pixels**. Keep **Z / 100%** on original/rendered RAW; Z from Camera Preview deliberately switches to RAW. Reset to Fit on photo changes and retain existing crop/pan/pinch/navigator/link behavior.

Use original Swift format indexing: bounded classic TIFF/SubIFDs and strict single-sample Canon CR3 CRAW/JPEG tracks inside verified mdat ranges. Inspect JPEG frame headers before payload/pixel decode; reject sensor/lossless frames, non-eight-bit/non-three-component frames, invalid offsets and excessive graph/box/encoded sizes. Guard original and oriented dimensions against the existing 256 MiB decoded limit. Use container orientation once, reject conflicting JPEG orientation, preserve RGB profiles and revalidate file identity/size/nanosecond timestamps. Unknown layouts can use embedded-only ImageIO with generation-from-RAW disabled and a 4096-pixel limit; malformed structures fail recoverably.

Format references are the [TIFF 6.0 specification](https://www.itu.int/itudoc/itu-t/com16/tiff-fx/docs/tiff6.pdf), the existing Canon reader and observations validated against the [pinned LibRaw pilot](../RAW_BACKEND_REVIEW.md). This is not a copy of a third-party decoder and adds no external runtime package.

Bundle **PhotoPreviewWorker**, a native SwiftPM executable, for one-photo decoding. A tiny owned C ABI shim creates private POSIX shared memory because Swift cannot call variadic shm_open directly. Unlink its name immediately, inherit its descriptor as stdin, validate bounded metadata/profile/stride/bytes and retain the mapping only through the returned image's provider. Shared RAM carries pixels; no temporary image file is written. Cancel queued jobs before launch, terminate an active worker when superseded/cancelled, and bound execution with a 30-second timeout. Validate source identity again after the worker exits. No silent in-process or RAW-rendering fallback is allowed.

The normal app-build script builds/copies/signs the worker before signing the enclosing bundle; benchmark/check scripts build the helper too. Keep the helper inside copied apps. No Package.resolved is needed because all targets are owned source/system frameworks.

## Evidence and limits

Generated regressions cover largest JPEG choice, TIFF endianness/cycles, CR3 media bounds, raw-sensor JPEG rejection, pre-decode size checks, all eight orientation pixel mappings, Display P3, source separation/linked commands, worker IPC, shared/owned buffer release, malformed headers and both queued/running cancellation. Existing original/RAW rendering and image-preservation checks remain.

[Real read-only controls](../benchmarks/2026-10-30-camera-preview.json) and the tracker record the actual corpus/results. Independent extracted-JPEG references check pixels, not RAW color/sharpness equivalence. Parent and per-worker RSS are separate and include shared pages; summing them double-counts shared RAM. The metadata-only service loop does not touch every mapped pixel, so its parent RSS is not the displayed app footprint. The 256 MiB limit bounds the returned bitmap, not all decoder/transient allocations. Broad storage/camera/platform, physical-frame, pressure and overnight acceptance remain open.
