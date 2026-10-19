# Browsing validation and performance

Measured: 2026-10-19. Baseline: `3130efa`. Optimized code: the performance follow-up in [PR #1](https://github.com/kuroiokami/photo/pull/1), merged into `main` as `24b7cff` after [the final PR checks passed](https://github.com/kuroiokami/photo/actions/runs/39268234733). [Raw aggregate results](benchmarks/2026-10-19.json) contain no source names, paths, hashes, EXIF, or image content.

## Corpus and method

- Real camera: 17 JPEGs, each 8640 pixels on its longest edge (approximately 50 MP), totaling 181,363,581 bytes. Both landscape and orientation-transformed portrait previews were observed in the native app.
- Mixed synthetic folder: 2,000 JPEG/PNG files with landscape/portrait dimensions and Unicode names; longest edges range from 1536 to 2400 pixels. Decode sampling covers the first 64 files, while enumeration and before/after hashing cover every file.
- Selection stress: 500 select/read operations near the end of a virtual 50,000-item collection. This measures state lookup cost, not rendered UI frame time.
- Apple Silicon, 18 logical CPUs, 128 GiB RAM, macOS 27.0.1, Apple Swift 6.4. Release builds. Three alternating, sequential before/after real-camera runs; one paired mixed-folder run. Builds and UI actions were not run concurrently with measurements.
- Cold means an empty application image cache; OS filesystem caches were not flushed. The benchmark hashes source bytes in bounded read buffers before and after browsing. All hash comparisons matched and all sampled files decoded successfully.

## Results

Real-camera table values are medians across the three process runs; p95 values within each run cover 17 decoded images or the recorded repeat count. Small timing differences are not treated as regressions or gains.

| Measurement | Before | After |
| --- | ---: | ---: |
| Uncached thumbnail p95 (ms) | 108.2 | 106.2 |
| Uncached preview p95 (ms) | 233.3 | 240.7 |
| Cached preview p95 (ms) | 0.0198 | 0.0199 |
| 8 concurrent same-image requests (ms) | 1628.8 | 203.1 |
| 50,000-item selection p95 (ms) | 7.1260 | 0.0009 |
| Sampled peak process RSS (MiB) | 531.2 | 418.6 |

Repeated requests now decode once, rather than serially decoding the same image eight times. Constant-time selection removes repeated array scans. A per-image autorelease pool releases temporary decoder objects. Individual cold JPEG decoding remains ImageIO-bound; these changes improve duplicate requests, cached interaction, and temporary memory retention rather than claiming faster JPEG decompression.

The 2,000-file folder's enumeration p95 was 84.9 ms before and 88.3 ms after. End-to-end folder-load p95 was 107.1 ms before and 125.3 ms after. Building the selection lookup table adds startup work, now off the main actor. Sampled peak CLI RSS was 429.8 MiB before and 396.7 MiB after.

## Reference-machine targets

These are local regression targets for this corpus and hardware, not portable CI deadlines or guarantees for every computer:

| Metric | Target | Optimized outcome |
| --- | --- | --- |
| 2,000-file folder load p95 | Below 250 ms | Passed |
| 50 MP thumbnail p95 | Below 150 ms | Passed |
| 50 MP preview p95 | Below 300 ms | Passed |
| Cached preview pipeline p95 | Below 1 ms | Passed |
| 50,000-item selection lookup p95 | Below 1 ms | Passed |
| Concurrent identical requests | One decode for eight requests | Passed by regression test |
| Real-camera benchmark peak RSS | Below 512 MiB | Passed |
| Cache budgets | At most 24 MiB thumbnails / 64 MiB previews | Passed |
| Original bytes | Unchanged | Passed |

RSS is sampled at 10 ms in the CLI process and includes validation/state allocations; it is not the UI app's footprint or an exact peak. The native debug app was separately observed at 635.6–648.7 MiB before tuning during real-camera navigation; the tuned native app was separately sampled at 216.9–312.3 MiB while navigating mixed real JPEG/PNG and 2,000-file folders (ending at 296.1 MiB). These are different process lifetimes/workflows, so no direct percentage reduction is inferred from the native samples. Final UI validation is recorded in the project tracker. OS rendering surfaces, visible images, and decoder allocations are additional to cache costs. No frame-rate claim is made.

## Native UI regression check

On the final rebuilt app, the contact sheet opened 23 mixed images (copies of the 17 real JPEGs plus six generated PNGs), displayed Unicode names and JPEG extension variants, showed correctly oriented portrait previews, and retained the final selection on Reload. The 2,000-file folder supported scrolling and Home/End navigation. A discovered preview-toggle reflow bug was fixed: photo 2,000 remains visible after hiding and reopening the preview. These are functional checks, not frame-time measurements.

## Reproduce locally

```sh
sh scripts/benchmark.sh --folder "/path/to/photo/folder" > /tmp/photo-benchmark.json
```

To create a separate, entirely synthetic corpus (the destination must not exist):

```sh
sh scripts/benchmark.sh --generate /tmp/photo-synthetic-corpus 2000
sh scripts/benchmark.sh --folder /tmp/photo-synthetic-corpus > /tmp/photo-synthetic-report.json
```

The benchmark opens originals read-only, samples up to 64 decodes, and verifies hashes for every enumerated JPEG/PNG. It never alters files in the supplied folder. Hash values are kept in memory and are not emitted. Machine-readable output is aggregate only. Keep personal images and ad hoc traces out of Git.

CI runs correctness checks and regression tests; it does not enforce hardware timing thresholds. Recheck performance when the decoder, cache, selection, or folder-loading paths change. Broader camera formats, network/removable media, minimum-macOS/Intel behavior, and very large real libraries remain future validation work.

## Fast culling validation — 2026-10-19

Final integrated release pipeline runs on the same reference Mac (18 logical CPUs, 128 GiB, macOS 27.0.1). [Aggregate JSON](benchmarks/2026-10-19-fast-culling.json) contains no paths, filenames, source hashes, EXIF or image content.

| Corpus | Preview p95 | Cached preview p95 | Sampled CLI peak RSS | Image failures | Source hashes |
| --- | ---: | ---: | ---: | ---: | --- |
| 3 Sony ARW, 9504-pixel sensor long edge | 19.31 ms | 0.016 ms | 87.16 MiB | 0 | All unchanged |
| 17 real JPEG, 8640-pixel long edge | 142.14 ms | 0.017 ms | 447.38 MiB | 0 | All unchanged |

ARW fit results use the camera's 1616-pixel embedded previews, not full-resolution demosaicing. They meet the new local ARW targets of 150 ms preview p95 and 1 ms cached p95. JPEG results meet existing local preview/thumbnail/cache/RSS targets. These are single final runs with uncontrolled filesystem caching, not paired proof of a new speedup or broad camera coverage.

The optional local integration test separately verified 9504 × 6336 Apple RAW detail rendering within the 256 MiB decoded-image limit, cancellation boundaries, and source preservation. Its elapsed test time includes hashing and is not a rendering benchmark. Decoder, GPU, view and OS allocations are additional; no total-application 256 MiB cap is claimed. The CLI does not measure EXIF-indexing, decision-save latency, native input latency or scrolling frame times.

Native checks used disposable ARW copies and generated PNGs: embedded preview badges, EXIF inspector, flags/stars, Shift-and-advance, Undo, Reload persistence, Picks filtering, an empty filtered set and recovery, ISO selection retention, explicit full RAW detail, native scrolling, and rating while zoomed. The build helper now seals the local app with an ad-hoc signature after wrapping its executable; an invalid pre-wrap signature caused native panel failures during validation.


## Large-folder reliability follow-up — 2026-10-19

[Aggregate measurements](benchmarks/2026-10-19-large-folder.json) compare `b0fcc3d` services with this PR's hardening follow-up, using the same new `--workspace` harness and reference Mac. Each synthetic corpus has one before/after process run; these are observed results, not portable performance guarantees.

| Corpus / measurement | Before | After |
| --- | ---: | ---: |
| 2,000 synthetic JPEG/PNG: initial decisions | 2,541 ms | 1,898 ms |
| Same: repeat decisions | 1,729 ms | 429 ms |
| Same: first preview during indexing | 43.8 ms | 44.1 ms |
| Same: complete metadata indexing | 355 ms | 361 ms |
| 2,000 synthetic ARW-name/XMP pairs: initial decisions | 35,897 ms | 2,273 ms |
| Same: repeat decisions | 35,528 ms | 662 ms |

The ARW-name corpus is **not camera imagery**: each `.ARW` contains invalid synthetic bytes beside valid rating XMP. All 2,000 preview/metadata failures are expected, while decision errors are zero. This isolates the former per-photo whole-directory collision scan. It now checks only the eight ARW extension spellings, deduplicating actual filesystem names, without retaining a stale collision cache. The store also reuses one actor-owned SQLite handle and avoids unchanged path-map writes, while retaining FULL synchronization and durable per-decision writes.

JPEG/PNG synthetic templates have valid dimensions but no shooting EXIF; their ISO sorting exercises missing values and natural filename ties, rather than a diverse exposure corpus. After-change ISO/rating sorts took 28.5/39.3 ms. A nominal 10 ms main-actor timer observed maximum gaps of 32.9 ms for mixed images and 13.4 ms for ARW-name fixtures. This includes scheduling and sorting publication; it is not UI frame-time evidence. Source image hashes matched in every report. The benchmark writes only its temporary database, which is removed afterward.

Nine verified disposable real ARW copies (655,712,256 bytes, 9504-pixel sensor long edge) were also tested. All are **Sony ILCE-7CR**, with eight orientation-1 files and one orientation-8 portrait. Embedded previews and genuine rendered detail passed for every file, with matching source hashes. Pipeline preview p95 was 21.72 ms, cached p95 0.014 ms, sampled peak CLI RSS 131.98 MiB and image failures zero. The first thumbnail took 166.85 ms; that exceeds the old 150 ms thumbnail target for this run. In the separate workspace process, first preview during concurrent indexing took **179.61 ms**, exceeding 150 ms; metadata indexing took 167.72 ms, initial/repeat decisions 9.17/2.63 ms and the selected decision 3.90 ms. The pipeline's preview phase follows its thumbnail phase, so its lower preview p95 must not be substituted for startup latency. Decoder initialization/first-open latency remains an explicit optimization target; multiple-camera coverage remains open.

Reproduce workspace measurements using `sh scripts/benchmark.sh --workspace /path/to/folder`. Use disposable folders for any metadata-write tests. The real-camera optional suite now checks every ARW in its supplied shallow folder, rather than only the first file. Camera files, filenames, private EXIF, source paths and hash values are excluded from the committed evidence.
