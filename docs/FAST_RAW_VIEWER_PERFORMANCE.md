# FastRawViewer performance patterns applied to Photo

Reviewed 2026-10-21 against the vendor's published documentation. These sources explain design choices; they do not establish a universal fastest-viewer ranking or give access to its implementation.

## What transfers to Photo

| Documented pattern | Photo implementation / decision |
| --- | --- |
| RAM thumbnail cache sized by decoded pixel cost | Replaced the 24 MiB thumbnail budget with about 1.6% of physical RAM, bounded to 64–256 MiB per window. Cache hits retain constant-time recency updates. |
| Persistent thumbnail cache with a size limit and compression options | Added a 512 MiB disk target shared across windows, storing lossless thumbnail pixels. Repeat visits can avoid original JPEG/RAW preview extraction. |
| Avoid doing too much work as soon as a folder opens | Keep lazy, visible-demand thumbnail requests. Selected Fit previews and full detail keep their separate workers. |
| Directional/bounded prefetch and limits for slow media | Further work: measure a cancellable viewport-aware queue and volume-specific limits before adding speculative reads. No new prefetch or parallel RAW work is enabled here. |
| Separate small thumbnails from expensive decoded files | Persist at most 480-pixel thumbnails. Keep the existing 2,560-pixel Fit limit and demand-only full-detail/RAW limits. |

Sources: [FastRawViewer 2 performance design](https://www.fastrawviewer.com/blog/FastRawViewer-2-0-Improved-Performance), [thumbnail/cache settings](https://www.fastrawviewer.com/node/221), [disk-cache design and tuning](https://www.fastrawviewer.com/blog/FastRawViewer-1-5-Release).

## What changed for photographers

Once a thumbnail is in RAM, returning to it can display it directly without waiting behind another image decode or first resetting it to a loading indicator. If it has left RAM, Photo checks its local disk thumbnail before decoding the source again. Disk thumbnails survive ordinary quit/relaunch and folder changes.

Use **View → Clear Thumbnail Cache** to discard generated thumbnails and rebuild them as needed. This clears the current window's thumbnail memory cache and the shared disk cache; photos, decisions and sidecars stay intact. Other open windows can retain their own already-loaded memory images. There is no import/catalog requirement.

The larger RAM allocation deliberately trades some memory for repeat-browsing speed. It is a cache budget, not a process-RSS ceiling: visible images, Fit/detail images, framework and decoder allocations use memory separately. The disk cache also adds one-time encoding/writing work on a cold visit. Photo stores all eligible thumbnails rather than using FastRawViewer's documented generation-time threshold; the benchmark records that tradeoff explicitly.

## Correctness and recovery

RAM cache access uses a short lock around dictionary/LRU/session state; it performs no file I/O and does not wait for the decode actor. Disk work stays on the thumbnail worker. A filename-free disk key includes standardized source location, device/inode, size, modification/change timestamps, thumbnail size and schema version. Source stamps are rechecked before accepting a disk result or saving a generated one.

Disk entries contain PNG pixels, source-kind and original dimensions, with atomic replacement, bounded decode dimensions/payload sizes and eviction to 90% of budget when full. Corrupt entries, unavailable cache directories and failed writes fall back to source decoding. Only owned cache files are removed by clearing/eviction. The cache is derived data under the user's macOS Caches folder; originals and XMP are not changed.

RAM entries trust the current browsing session as before. Reload clears that memory session and rechecks file stamps; **Clear Thumbnail Cache** also removes disk entries when regeneration is needed. This is metadata-based cache invalidation, not a cryptographic proof of unchanged source content or offline-library support. Cache budgets are maintained within this process; multi-process cache writers and unusual filesystem metadata behavior are not verified.

## Evidence and remaining work

See [measurements and methodology](PERFORMANCE.md#thumbnail-cache-tiers--2026-10-21), [aggregate runs](benchmarks/2026-10-21-thumbnail-cache.json), the [tracker](../PROJECT_STATUS.md) and ADR 0025. The harness compares cache policies using 115 synthetic 24MP JPEGs; it is not a FastRawViewer comparison, RAW benchmark or UI frame-time test.

Directional idle prefetch, media-aware parallel decoding, memory-pressure adjustment, disk-cache UI sizing controls, real mixed-camera benchmarks and representative 10–40k shoots remain follow-ups. Preserve current selected-image priority while measuring each change.
