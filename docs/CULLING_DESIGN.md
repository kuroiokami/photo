# Fast culling design

Accepted 2026-10-19: Sony ARW → independent culling decisions → explicit full-detail inspection. The main workflow is open folder, browse quickly, pick/reject, narrow with filters, rank keepers with stars, and inspect doubtful focus at 100%. No import or full-library preview generation is required.

## Research

- [Lightroom flag/rating documentation](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/flag-label-rate-photos.html) supports familiar P/X decisions, 1–5 stars and Shift-and-advance. Photo adds U/0 for clearing and an explicit remembered auto-advance checkbox rather than a hidden modifier mode.
- [Photo Mechanic format documentation](https://camerabits.freshdesk.com/support/solutions/articles/48000361354-supported-file-formats) explains embedded JPEG use for fast RAW browsing. Photo uses that approach for ARW without silently rendering the sensor data.
- [FastRawViewer features](https://www.fastrawviewer.com/) emphasize actual RAW exposure/focus evaluation. Photo distinguishes embedded-preview provenance from explicit Apple RAW rendering; RAW histograms and focus peaking remain future work.
- [Photographer workflow discussion](https://www.reddit.com/r/photography/comments/1813bau/catalog_culling_and_import_software_for_2023/) describes the value of keyboard controls, preview speed, RAW inspection and organizational tools. These accounts informed interaction priorities, not numerical comparative claims.

The design recommendation is a synthesis of those sources: separate binary triage from star ranking, make controls discoverable, preserve keyboard flow, and spend RAW-rendering time only on demand.

## Behavior and storage

P picks, X rejects, U clears flags; 0–5 assigns stars. Shift advances once; Auto-advance is visible and initially off. Reject never deletes. A decision disappearing through a filter selects its next pre-action survivor or the previous survivor if necessary. Advancing at the final surviving photo stays there. Rating reordering preserves identity; normal unfiltered decisions avoid a collection rebuild.

SQLite is shared across windows and stores decisions plus pending sidecar writes before XMP is attempted. Normal quit drains the serial save queue. On restart, a sidecar already containing the pending decisions completes a lost SQLite acknowledgement without being rewritten. File-system volume/inode identity (path fallback) plus creation/modification/size fingerprints guard replacement files. UI requests retain the loaded identity; save errors are visible. A path/identity association detects replacements with leftover XMP and requires an explicit choice before adopting predecessor decisions. The paths table is created additively for existing databases. There is no cross-library relocation scanner or content deduplication.

ARW uses basename.xmp; JPEG/PNG use full-filename sidecars. [XMP Rating](https://developer.adobe.com/xmp/docs/xmp-namespaces/xmp/) stores 0–5 independently of [Lightroom pick/good fields](https://exiftool.org/forum/index.php?topic=15815.0). A legacy rating of −1 imports as rejected/unrated. Unflagging removes good and writes pick=0.

Namespace-aware merges preserve unrelated XMP semantically, including develop settings, but may change XML formatting. Ambiguous documents, entities/DTDs, sidecar symlinks and oversized packets are not rewritten. Sidecar digests detect changes since the last synchronization; coordinated atomic writes avoid partially published XML. Other apps that ignore file coordination can still race filesystem changes; do not edit the same sidecar concurrently. Reload imports external decisions when local edits are not pending. Conflicts and failed writes stay local until explicitly resolved/retried.

Lightroom application-level round-trip exchange is **not verified**. JPEG/PNG sidecars are not a universal interchange format. No original image or embedded metadata writes occur. RAW+JPEG are separate items; labels and batch decisions are deferred.

## Preview and EXIF

ARW browsing requests embedded ImageIO thumbnails only. EXIF indexing reads properties without pixel decoding, prioritizes the selected item between background reads, and publishes complete sort order after indexing. Numeric sort values stay numeric; missing values sort last with natural filename ties. Capture timestamps honor offsets/subseconds; timestamps without offsets use a consistent UTC wall-clock interpretation, which cannot infer unknown camera timezone differences.

Thumbnail/fit cache budgets remain 24/64 MiB. Selected 100% detail uses a separate serial worker and no cache. JPEG/PNG full decoding applies orientation; supported ARW detail uses CIRAWFilter and an sRGB 8-bit render. One image pixel maps to one physical display pixel. Limit decoded detail to 256 MiB, with preflight dimensions and a post-decode stride check; operating-system/decoder allocations are additional. A full RAW render may process the entire sensor image. No region-decoding performance claim is made.
