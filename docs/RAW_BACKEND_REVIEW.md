# RAW backend lessons and measured pilot

Reviewed and measured: 2026-10-30. This follows the [earlier source review](OPEN_SOURCE_PERFORMANCE_REVIEW.md). The app remains SwiftUI/SPM with ImageIO previews and deliberate Apple RAW detail; LibRaw is a standalone experiment.

## What Photo adopted

- **LibRaw:** separate metadata, embedded preview extraction, sensor unpack and full rendering. `open_file` parses metadata; `unpack_thumb` selects the default largest preview, with explicit indexed preview APIs available. JPEG extraction does not itself decode pixels. See the [official API](https://www.libraw.org/docs/API-CXX.html).
- **RawTherapee:** temporary Inspector/peek behavior, with embedded/RAW source distinctions. Photo independently implements hold-W Quick Preview and an explicit Z transition to true detail; see [Inspector source](https://github.com/RawTherapee/RawTherapee/blob/dev/rtgui/inspector.cc).
- **darktable:** stable mip sizes and best-effort cached images while a requested size loads, plus temporary preview behavior. Photo independently implements Retina thumbnail classes and bounded same-session stand-ins. See [mipmap cache](https://github.com/darktable-org/darktable/blob/master/src/common/mipmap_cache.c) and [full preview controls](https://docs.darktable.org/usermanual/development/en/lighttable/lighttable-modes/full-preview/).

Existing embedded-first browsing, bounded memory/worker lanes, visible priority and nearby Fit preparation were already implemented. No GPL implementation was copied. RawTherapee/darktable are GPL projects; LibRaw offers LGPL-2.1/CDDL-1.0 alternatives with component-specific notices in its [COPYRIGHT](https://github.com/LibRaw/LibRaw/blob/cf02d66eb5c19d4e46df7aee0582e47a4918509a/COPYRIGHT). Any shipped library/backend needs its own distribution decision; this pilot adds no runtime dependency.

## Standalone LibRaw pilot

[Raw anonymous observations](benchmarks/2026-10-30-libraw-pilot.json) retain all five cases, build provenance, errors, dimensions, requested cancellation and process peak RSS. [Probe/reproduction](../Tools/LibRawProbe/README.md) uses official LibRaw **0.22.3**, pinned commit **cf02d66eb5c19d4e46df7aee0582e47a4918509a**; source archive SHA-256 **f2d01366f36640e8a5079b2ea8e3ec64d4c4a844e005257fca2f65c95b87670d**. Built with official Makefile.devel, -O3/zlib, without OpenMP, external JPEG, LCMS, DNG SDK or RawSpeed. This is not a tuned FastRawViewer backend.

Two authorized Sony ARWs and three provenance-verified CC0 Canon CR3/CR2 and Olympus ORF fixtures stay outside Git. Every original hash matches after both backends. Fresh processes alternate backend order; hashing warms OS caches. These are single observations, not p95, cold-media or native frame measurements.

| Case | LibRaw metadata / JPEG extraction (ms) | Largest camera JPEG | Apple first Fit / full RAW completion (ms) | Extracted JPEG full completion (ms) |
| --- | ---: | --- | ---: | ---: |
| 1 · ARW | 1.1 / 1.3 | 9504×6336 | 177 / 1095 | 281 |
| 2 · ARW | 0.9 / 1.3 | 9504×6336 | 187 / 1137 | 276 |
| 3 · CR3 | 0.9 / 0.4 | 6720×4480 | 49 / 569 | 131 |
| 4 · CR2 | 0.8 / 0.4 | 5184×3456 | 220 / 285 | 78 |
| 5 · ORF | 1.1 / 0.2 | 3200×2400 | 239 / 476 | 34 |

LibRaw metadata/thumbnail/unpack/full processing succeeded in all five cases; requesting its progress callback before unpack cancelled all five. This does not prove a maximum mid-decode cancellation delay. ISO/shutter/aperture/focal field presence was checked, not EXIF value/timezone accuracy. Photo's own cancellation/session tests remain separate.

The tested Sony camera JPEG is 9504×6336 while current ImageIO embedded Fit is 1616×1080: a larger camera-JPEG focus-check option is worth investigating. Olympus's embedded JPEG is only 3200×2400 against a 5184×3888 Apple detail image; it cannot be called sensor-resolution 100%. LibRaw and Apple rendered dimensions differ at active/border areas, so outputs are not interchangeable without crop/orientation validation.

Do not compare compressed extraction directly with Photo's decoded Fit time. The optional scratch JPEG is decoded separately through ImageIO, with its write reported separately and derived bytes deleted. Its full completion is measured after a Fit request in that process. Camera JPEG includes camera processing; it is not rendered RAW. Apple uses existing progressive CIRAWFilter settings; LibRaw full uses camera WB, 8-bit sRGB and otherwise defaults. No visual/color/sharpness equivalence is established.

LibRaw full unpack+processing was slower than Apple full completion in every pilot case in this build. Its process peak RSS spans roughly 239–786 MiB; Apple RAW roughly 305–642 MiB, and extracted-JPEG processes roughly 128–738 MiB. These include framework/transient allocations and are not whole-app cache budgets. The large JPEG path is not automatically a memory improvement.

## Decision and next acceptance

Ship adaptive thumbnail/Quick Preview/crop improvements, retain production PNG and the existing RAW backend. Continue only a narrow metadata/larger-embedded-JPEG candidate if broader camera/mode, EXIF/timezone, rotation/active-area/color, decoded-memory, cancellation and distribution checks justify it. Keep camera-JPEG inspection explicitly labelled and preserve genuine RAW 100%. Do not replace Apple processing or add broad speculative full-detail decoding based on this pilot.

The separate [thumbnail codec controls](PERFORMANCE.md#adaptive-thumbnail-sizes-and-disk-codec-experiment--2026-10-30) retain PNG/JPEG/JPEG/PNG observations and pixel errors. Photographic/color/physical-frame acceptance remains open.
