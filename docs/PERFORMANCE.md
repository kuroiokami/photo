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

## Ingest/camera workflow follow-up — 2026-10-19

[Aggregate results](benchmarks/2026-10-19-ingest-cameras.json) record sequential release runs on the same reference Mac. Public CC0 files cover Canon EOS R CR3, Canon EOS Rebel SL1 CR2, Olympus E-M1MarkII ORF and OM System OM-1 ORF; [provenance and SHA-256](fixtures/public-raw-provenance.json) are public, but the images stay outside Git. These four camera/mode examples do not establish universal RAW compatibility. Real CRW remains unverified.

Initial ImageIO-only support returned a **5,127.52 ms** maximum/p95 thumbnail over four files. A focused diagnostic isolated approximately **5,088 ms** in the EOS R CR3 property read; requesting its thumbnail without properties still took approximately **5,114 ms**. Both RAW generation switches were disabled. Repeated preview access was much faster, so reporting only warm previews would conceal the startup problem.

The new bounded CR3 container path reads the existing PRVW JPEG and CMT1 orientation/dimensions, then decodes only the JPEG. Unknown layouts retain ImageIO's embedded-only fallback. The follow-up run's maximum/p95 thumbnail over the four files fell to **182.02 ms**; preview p95 was **77.90 ms**, cached-preview p95 **0.017 ms**, with zero failures and all input hashes unchanged. Sampled CLI peak RSS was **195.56 MiB**; fit/thumbnail cache costs were **60.84/2.49 MiB**, within their existing budgets. The direct PRVW image can be smaller than ImageIO's alternate embedded source; the UI reports its actual decoded size and retains genuine rendered RAW detail separately.

The 182 ms first-thumbnail outcome still exceeds the 150 ms reference target. Apple's initial decoder setup for other formats and CR3 EXIF/background indexing remain profiling work. These runs are single-process observations with uncontrolled OS caches, not controlled performance distributions or native frame/input measurements. Full-detail render timings are not represented by the Fit preview figures.

With unique-family/companion indexes enabled, 2,000 valid synthetic JPEG/PNG files returned first preview during concurrent indexing in **43.84 ms**, decision loading in **2.03 s** initially/**0.44 s** on repeat, metadata indexing **362.80 ms**, ISO/rating sorts **31.00/42.26 ms**, and sampled maximum main-actor gap **42.17 ms** including scheduler delays. All 2,000 source hashes matched; metadata/decision errors were zero. An early quadratic family companion scan was removed before these results. This nominal 10 ms timer gap is not UI frame time.

Reproduce externally, keeping sample images out of the repository:

```sh
PHOTO_RAW_TEST_FOLDER=/absolute/disposable/raw-folder sh scripts/check.sh
sh scripts/benchmark.sh --folder /absolute/disposable/raw-folder > camera-report.json
sh scripts/benchmark.sh --generate /new/disposable/mixed-folder 2000
sh scripts/benchmark.sh --workspace /new/disposable/mixed-folder > workspace-report.json
```

## Folder and batch usability follow-up — 2026-10-19

Folder disclosure enumerates only immediate directories on a separate actor; photo loading continues through the existing session-isolated lanes. Restoring a folder opens its images before restoring expanded descendants. This change does not alter decoding, cache budgets, RAW render policy or the preceding benchmark results. No new latency/frame-rate claim is made. Rectangle hit testing uses currently laid-out grid frames and the viewport; edge auto-scroll is deferred. A 50-photo field-patch regression verifies preservation and selection, not throughput. Large folder-tree/rectangle frame-time measurements remain future acceptance work.

## Progressive RAW detail — 2026-10-19

A read-only release benchmark compared the legacy algorithm from `b4cf5e7` with the progressive implementation on four 60 MP Sony ILCE-7CR ARWs (9504 × 6336), three passes each on the reference 18-core/128 GiB Apple Silicon Mac. [Aggregate report](benchmarks/2026-10-19-detail.json) contains no private photo identifiers. This is one sequential paired process run; OS/driver caches were not flushed. Twelve samples make p95 equal to the maximum; these service timings are not native frame-time measurements.

| Measurement | Legacy | Progressive |
| --- | ---: | ---: |
| First inspection median | 266.94 ms | 122.21 ms |
| First inspection p95 / maximum | 468.19 ms | 351.08 ms |
| Initial process request | 468.19 ms | 351.08 ms |
| Complete eager full image median | Not measured comparably | 940.40 ms |
| Complete eager full image p95 | Not measured comparably | 1151.79 ms |
| Process peak RSS | 662.06 MiB | 850.84 MiB |
| Failures / changed originals | 0 / 0 | 0 / 0 |

First inspection was about 54% quicker in this run. The baseline includes a centered 1600 × 1200 first draw of the old deferred CGImage, which need not materialize every offscreen pixel. The progressive run includes the same first draw, then completes the full image eagerly off the UI thread. Do not interpret the old CGImage-return time as completed decoding or compare offscreen completion as equal work.

The new worker renders a normal-quality focus patch first, reuses its context, then completes the full image in 1024-row strips with cancellation checks and cache release between strips. Small patches fit within one bounded render. No draft mode, reduced resolution or RAW processing changes ship. The temporary patch plus full decoded image stays within 256 MiB; context/decoder/GPU work is additional. RSS is higher than the viewport-only baseline because the full image is prepared eagerly. An earlier whole-surface progressive experiment peaked at about 1070 MiB; bounded strips reduced that to about 851 MiB while increasing total completion time. This is an explicit responsiveness/memory tradeoff, not a total-memory cap or a claim of region-only RAW decoding.

Reproduce sequentially with `sh scripts/benchmark.sh --detail /path/to/folder --baseline` and the same command without `--baseline`. Use `sh scripts/build-app.sh --release` for native evaluation. The benchmark hashes every source before/after, uses no decision store and writes no image/sidecar files. Real-camera preservation/progressive checks use disposable copies. Minimum-platform, other-camera, native frame-time and interruption measurements remain open.

## Comparison and verified arrivals — 2026-10-20

Comparison uses two independent demand-only detail actors, each retaining at most 256 MiB combined region/full decoded images: 512 MiB total retained detail. Normal single-image mode remains 256 MiB. This increase permits two 60 MP photos, and is explicit in the Link Zoom/Pan help. Decoder/GPU/transient allocations remain additional. Fit/navigation/closing releases detail ownership. There is no speculative rendering or full-detail cache.

EXIF label rows reuse existing indexed values. Verified ingest arrivals coalesce for 200 ms, append only new identities and index only new metadata; they retain preview session/cache identity. Collection revisions reject stale asynchronous sort snapshots. Tests exercise sorting during arrival and retained selection/decision history. Synthetic native linked/unlinked pan checks pass. Two real Sony 60 MP ARWs also completed 9504×6336 Rendered RAW detail and linked pan; source/sidecar hashes matched. No new latency, frame-rate, peak RSS or broad performance claim is made. Historical single-pane benchmarks above are unchanged and do not measure comparison.

## Non-destructive composition and magnification — 2026-10-20

Rotation, mirrors and crop use a shared affine CGImage drawing path in Fit/thumbnails, detail/progressive regions and navigator. Explicit fitted-rectangle clipping prevents uncropped pixels leaking into letterboxes. Drawing does not allocate another edited full-resolution bitmap. Views skip redundant redraw requests when source/edit are unchanged and redraw on size changes. Magnification reuses the existing decoded detail; cropped inspection inverse-maps focus into original coordinates. Cropping does not avoid full RAW processing or permit an oversized source through the detail budget.

Existing thumbnail/preview cache limits, 256 MiB per-pane decoded-detail allowance and 512 MiB comparison allowance remain; transient driver/decoder/UI memory is additional. There is no speculative rendering or detail cache. Extra SQLite image-edit lookups do not decode pixels. Automated source-pixel, progressive-region, physical-size and zoom-anchor checks pass. No new service latency, native frame-time or RSS benchmark is claimed; historical results above remain scoped to their recorded implementations. Physical trackpad and final native clipped-view acceptance remain pending an unlocked screen.


## Protected source review implementation — 2026-10-20

This chunk adds no new latency or 10k/40k performance claim. Normal RAW decoding/cache lanes are unchanged. Folder photos publish before awaiting persistence context so a busy metadata actor does not hold up the selected preview; protected decision entries carry their role before becoming actionable. Protection registry JSON is cached by identity/modification/size, and copy write locks cover at most 1 MiB rather than entire RAW reads/hashes. Initial unreviewed review rows still use SQLite during background decision indexing; representative large-source indexing, memory and concurrent-copy measurements remain required. Native acceptance used only three synthetic PNGs; it establishes functionality/source preservation, not camera/card throughput.


## Reviewed-copy completion — 2026-10-20

Strict regression suite passes (135 registered, two optional RAW skips), including copying scoped source reviews, destination handover, cancellation/restart, metadata failures and later edits. Inventory/planning uses file metadata/XMP without image decoding; Current Selection limits dependency discovery to selected folders. Copying retains chunk-bounded source protection locks and original SHA-256 verification. Immutable plan counts are cached per execution rather than flattening the list per arrival; append-only provenance avoids rewriting an expanding ingest manifest for every photo, and final ordinary manifests materialize once.

Optimized packaging/signature checks pass. Native synthetic source directory/image/sidecar hashes are unchanged, but the UI bridge disconnected before completing copy acceptance. No new preview/copy throughput, latency, RSS or 10k/40k scale numbers were collected; automated suite durations are not photographer performance benchmarks. Existing preview/detail targets and unmeasured simultaneous card-I/O acceptance remain in force.
