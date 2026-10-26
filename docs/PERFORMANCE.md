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

## Performance suggestion review — 2026-10-20

See the [complete suggestion audit and reproducible hot-path measurements](PERFORMANCE_REVIEW.md). Release microbenchmarks confirm and remove linear cache-hit scaling, and measure actor-owned EXIF parser/coder reuse plus duplicate identity-stat removal. The aggregate before/after report is linked there. These synthetic warm-read results do not change historical RAW startup/detail targets or establish 10k/40k native acceptance. Batch persistence, observation/selection costs, rating reorders and decoder concurrency remain targeted profiling work.

## Culling interaction stability — 2026-10-20

Review context, batch summary and ordinary save status now reserve height, avoiding preview resizing when a normal saving message appears/disappears or review mode begins. Workflow setup retains the underlying browser identity in the main window; Trash removes only confirmed moved images without resetting the preview session, and late indexing results for removed items are rejected. Existing cache/decode/detail bounds and deliberate RAW policy remain. These are interaction changes verified in tests/native checks recorded in the tracker, not new frame-time, RAW latency, RSS or large-shoot benchmarks. Trash ownership indexes build once per folder; bulk Trash throughput and physical/network-volume availability remain unmeasured.

## Contact-sheet scrolling follow-up — 2026-10-21

A user reported slow scrolling through 115 JPEGs. Native inspection confirmed the 115-item Contact Sheet. A short pre-change CPU sample overlapped scrolling and included SwiftUI lazy-grid sizing/layout and `PhotoTileFrames` preference reduction; no ImageIO thumbnail-decoding stack appeared in that sample. A second sampling attempt did not reliably overlap the gesture, so it is not a valid paired measurement. Raw profiles remain in temporary local storage and are not published.

The implementation removes two avoidable UI costs: viewport position changes no longer write to workspace `@State`, and invisible quick actions no longer create/layout all six controls. A stable, main-actor non-observable frame holder supplies marquee hit testing without invalidating the grid. Current-frame replacement and offscreen clipping are tested. Decoder workers, cache limits, thumbnail resolution and original-image behavior are unchanged.

Strict checks pass: 150 registered tests, 148 executed and two optional RAW skips; optimized packaging and signature verification pass. After unlock, native checks traversed the same 115-JPEG collection, scrolled back across several pages, and confirmed visible thumbnails eventually finished loading. Returning to evicted entries can still show transient loading indicators; this is not an all-115-images warm-cache measurement. Marquee selection after scrolling, exact two-sample marquee, selected-tile rotation/Undo, Mirror menu opening, Crop/cancel, Preview/filmstrip and Space return passed. The original folder, selection, flag and Contact Sheet were restored without personal-photo edits. Physical trackpad/hover-only and broad platform/accessibility coverage remain open. No numeric scroll/frame-time improvement or large-library acceptance is claimed. See ADR 0024 and the tracker/delivery PR for final evidence.

## Thumbnail cache tiers — 2026-10-21

[FastRawViewer research and decisions](FAST_RAW_VIEWER_PERFORMANCE.md) informed bounded RAM/disk thumbnail reuse and immediate RAM-hit display. [Two aggregate release runs](benchmarks/2026-10-21-thumbnail-cache.json) use 115 distinct paths containing copies of one synthetic 24 MP gradient JPEG, decoded to 480-pixel thumbnails. Reference Mac: 18 logical CPUs, 128 GiB RAM, macOS 27.0.1. Application caches start empty; OS caches are uncontrolled. Passes are sequential within one process. The previous policy uses current code with the former 24 MiB budget, not a historic binary.

| Cache policy / pass | Source decodes on return | Total service time across 115 images |
| --- | ---: | ---: |
| Former 24 MiB RAM policy, second pass | 115 | 1,343–1,381 ms |
| Adaptive RAM (256 MiB budget here), second pass | 0 | 0.44–0.46 ms |
| RAM + disk, second pass | 0 | 0.42–0.56 ms |
| New worker forced to use disk, first pass | 0 (115 disk hits) | 31–37 ms |

Adaptive RAM retained 67.38 MiB of decoded thumbnails versus 23.44 MiB under the old budget. These are cache bytes, not process RSS. Initial RAM-and-disk population took 1,748–1,771 ms versus 1,347–1,367 ms with RAM only: about 380–424 ms (28–31%) of extra first-use encoding/writing work. Photo currently saves all eligible thumbnails as lossless PNG rather than applying a generation-time threshold. All original JPEG hashes matched afterward. Reproduce with `swift run -c release PhotoBench --thumbnail-cache`.

Native checks passed scrolling several pages through an existing 115-JPEG folder and returning with visible thumbnails populated, normal quit/relaunch, final-build Contact Sheet and restored original focus. View → Clear Thumbnail Cache is present; disposable automated tests exercise clearing, not the personal-photo cache. Six new regressions cover pixel/dimension/source-kind round trips, source replacement/removal, size keys, corruption, write failure, budgets, owned-file clearing, session isolation and concurrent RAM lookups. Strict checks pass with 156 registered tests, 154 executed and two optional RAW skips; release packaging/signature verification pass.

These timings measure the thumbnail service, not scrolling FPS, full-app restart latency, RAW rendering or FastRawViewer performance. No comparative fastest-viewer, peak RSS, physical-trackpad or 10k/40k-shoot claim. Directional idle prefetch, media-aware parallelism and memory-pressure response remain follow-ups. Cache invalidation uses file identity/timestamps rather than source hashes; cross-process writers and unusual filesystem timestamp behavior remain unverified.

## Background publication and interaction tracing — 2026-10-21

The [tracing guide](PERFORMANCE_TRACING.md) documents local Instruments markers and the extended release harness. [Aggregate runs](benchmarks/2026-10-21-background-publication.json) compare an unbatched workspace with basic tracing/counters against grouped publication with additional stage tracing. Two alternating baseline/updated pairs use 1,000 generated JPEG/PNG gradients, three dimensions/orientations and varied extensions on the same 18-CPU/128 GiB/macOS 27.0.1 reference Mac. Fresh temporary SQLite per run; OS caches uncontrolled. Final runs use temporary idle-sleep prevention after a pilot's 351-second heartbeat gap made it noncomparable; that pilot was excluded explicitly.

Metadata publication groups fell from 1,000 to 18; initial decision publication groups fell from 1,000 to 33–34 in the recorded updated runs. Counts represent model publication operations, not view evaluations, per-dictionary notifications or frames. Focused results bypass batching; a focus change can promote buffered information without waiting for another file read. Background checkpoints occur after 64 reads/entries or roughly 50 ms, not on a deadline that interrupts active decoding.

Full metadata indexing did not improve: it took about 191 ms before and about 227 ms afterward. Additional tracing and grouped publication are both included; this is not an isolated estimate of their individual cost. Decision-load and first-preview service measurements remain in the aggregates; small two-run differences are not treated as an established speedup. Maximum nominal-10ms heartbeat gaps are OS/scheduler-sensitive and are not frame-time results. All original-image hash comparisons matched; there were no metadata/decision failures.

An updated concurrent scenario navigated first/middle/last while real verified ingest copied 24 disposable inputs to two temporary destinations. All 24 verified arrivals completed; selected-decision waits include 1 ms polling and are not keyboard-to-screen latency. This is same-machine synthetic service contention, not physical-card throughput or a large-shoot acceptance test.

A finalized Time Profiler CLI trace exported 2,246 fixed-name marker rows, with balanced exercised intervals and a shared Fit-load/source-decode correlation ID. Raw traces remain outside Git. Native checks passed group stars/flags while EXIF indexing was still in progress, Pick filtering/Clear Filters, Undo, return scrolling, selection retention and quit/relaunch. Original browsing context was restored without personal-photo edits. The native SwiftUI recording reported malformed transferred data; it supplies no valid before/after hitch comparison. No new FPS/RSS/RAW/40k claim. Strict checks pass with 160 registered tests (50 UI/imaging + 110 core), 158 executed and two optional RAW skips; four new regressions cover selected promotion, stale/removal results, cancellation/retry and decisions/filter/Undo/persistence during loading. Remaining scheduling/cache-writing/ingest-journal experiments stay separate.

## Culling hot paths — 2026-10-21

Implemented [ADR 0027](decisions/0027-culling-hot-paths.md). [Raw synthetic reports](benchmarks/2026-10-21-culling-hot-paths.json) include one pre-change release thumbnail run and two updated runs on the same 18-core/128 GiB Mac, macOS 27.0.1 (26A434). Caches/files are disposable; OS caches and run order are uncontrolled. No competitor, native scrolling/frame-time or actual large-shoot ingestion claim follows.

| Scenario | Before / individual / native | Updated | Scope |
| --- | --- | --- | --- |
| Initial delivery, 115 synthetic 24 MP JPEG thumbnails with disk caching | 1,765 ms | 1,369–1,390 ms | About 21–22% lower delivery time; background queue drain adds 3.20–3.22 ms after delivery. One baseline, two updated runs; not an alternating trial. |
| New-worker disk reuse, same 115 entries | 32.5 ms | 25.4–26.9 ms | All 115 disk hits, zero source decodes; not an application restart. |
| Cold decision/image-state indexing, 1,000 JPEG paths | 2,043–2,054 ms individually | 1,347–1,359 ms in batches | About 33–34% lower; two fresh databases per updated process, FULL durability, individual first then batched. No XMP writes/bulk decision saves. |
| Five repeated rating sorts, 40,000 synthetic filenames, all ratings tied | 1,186–1,223 ms native comparisons | 483–488 ms ranked comparisons | About 59–60% lower repeated-sort time; add 220–221 ms once to build ranks. Identical resulting identity order. |
| 10,000 readiness queries for 10,000 selected samples | Structural regression: expanded selection on each selected tile check | 2.94–2.95 ms; one selection evaluation | Includes the first expansion; no timed pre-change/native UI comparison. |

RAM-only return passes still decode zero originals and take 0.44–0.49 ms for 115 service requests. Retained thumbnail bytes remain 67.38 MiB; the writer adds a separate maximum of 32 MiB pending decoded pixels, including its active image, and at most 64 pending keys. These are cache/queue budgets, not RSS or decoder scratch memory. All synthetic source bytes matched afterward. Queue saturation drops optional persistence; quitting need not finish derived cache writes.

Reproduce with `sh scripts/benchmark.sh --thumbnail-cache` and `sh scripts/benchmark.sh --hot-paths`. The thumbnail report now separates first delivery from subsequent cache drain. Hot-path schema 2 adds cold indexing, native/ranked sort and selection-readiness scenarios; older warm lookup results did not cover those costs. The tests count two commits for 24 cold files rather than 48 individual discovery writes, verify restart/cache-seed recovery and prevent later autocommits after a SQLite automatic rollback.

Formatting/strict checks pass: 166 registered tests, 164 executed, two optional local RAW skips. Release Photo/PhotoBench builds pass. Native app inspection timed out during this run; no updated native responsiveness acceptance is claimed. Earlier native checks apply to the prior build only. Physical media, actual 10k/40k mixed-camera shoots, native frame traces/RSS, asynchronous disk reading, bulk user-decision transactions and cold CR3 EXIF remain separate work.

## Contact-sheet native diagnostics — 2026-10-21

[ADR 0028](decisions/0028-contact-sheet-rendering.md) simplifies unedited image rendering, replaces string task identities, formats labels once and clips viewport-based marquee geometry to visible regions. The proposed content-origin optimization failed native acceptance and was withdrawn. Original bytes/cache policy and the edited/full-detail renderers remain. The release app was profiled directly in Animation Hitches using a disposable 1,000-image JPEG/PNG corpus, 160-point thumbnails and the same window. [Anonymous diagnostic reports](benchmarks/2026-10-21-contact-sheet-native.json) preserve the actual limitations:

| Exploratory capture | Input | Potential main-thread stalls | Longest | Main sampled CPU weight |
| --- | --- | --- | --- | --- |
| Baseline `b3670ff`, 30 seconds | 24 one-page inputs, six down/six up twice | 45 | 305 ms | 5,445 ms |
| Baseline after indexing settled, 20 seconds | Same 24 inputs | 32 | 1,746 ms | 3,706 ms |
| Updated, settled/warmed, 20 seconds | Shorter ten inputs, five down/five up | 31 | 586 ms | 1,700 ms |

These are **not matched before/after runs**: input counts/durations differ, all input endpoints were not independently correlated to trace timestamps, and the settled baseline varies substantially. Do not divide by input count and claim a speedup. Scripted accessibility input adds focus/inspection overhead. Inclusive CPU categories overlap; the first baseline includes SwiftUI view rendering (3,079 ms), focus resolution (1,657 ms), lazy-grid layout (363 ms) and preferences (295 ms). Native traces support investigating UI processing rather than inferring scroll feel from image-worker microbenchmarks. They do not establish presented FPS, confirmed dropped frames, smoother scrolling, physical-trackpad acceptance or competitor parity. Process-less display surface/frame tables are excluded from app metrics.

A final matched scripted pair used **60-second captures and the same ten inputs** (five pages down/five back), settled indexing, warmed rows, first-photo selection, the same window and 160-point thumbnails. The final build retains viewport-based geometry; the failed content-origin candidate is excluded.

| Matched capture | Potential stalls | Stall union | Longest | Main sampled CPU weight |
| --- | --- | --- | --- | --- |
| Baseline `b3670ff` | 17 | 3,691 ms | 402 ms | 4,150 ms |
| Final implementation | 15 | 2,631 ms | 331 ms | 3,103 ms |

This is one pair, with uncontrolled OS caches and accessibility overhead. The observed reduction applies to this scripted diagnostic scenario. Each returning scrollbar endpoint was observed before capture ended; individual input events were not correlated to trace timestamps. No presented FPS, confirmed dropped-frame, general smoothness or competitor parity claim follows. Inclusive SwiftUI view-graph sample weight was 2,129 → 1,225 ms, focus 1,042 → 815 ms, lazy-grid 467 → 234 ms and preferences 171 → 122 ms; categories overlap.

Unlike earlier malformed SwiftUI recordings, these finalized Animation Hitches traces exported usable potential-hang/CPU tables. Wait for recording **and saving** to finish before exporting. The new `scripts/analyze-scroll-trace.py` emits process-filtered fixed aggregates, merges overlapping intervals and excludes raw paths, IDs, environment and arbitrary symbol text. Three parser tests cover those protections, reference resolution and missing/empty capture rejection; repository CI runs them. Raw traces/exports stay outside Git.

Strict format/build/tests pass: 167 registered Swift tests, 165 executed, two optional RAW skips. The new marquee regression clips partially visible tiles before drag intersection; existing geometry replacement/clearing tests remain. Native functional checks passed viewport-based marquee after vertical scrolling and horizontal filmstrip movement, group stars/flags and Undo, quick actions, rotate/mirror/crop rendering and Undo, density reflow, keyboard navigation/reveal and normal quit/relaunch. The content-origin candidate failed scrolled native selection and was withdrawn. Original browsing settings were restored, the disposable shortcut removed and all 1,000 source-image hashes matched. Full physical-trackpad/physical-media/real-camera/color-profile/RSS/large-shoot acceptance remains open.

## Ordinary-ingest journal — 2026-10-21

[ADR 0029](decisions/0029-ordinary-ingest-journal.md) replaces per-file growing snapshot rewrites with append-only durable records at both destinations and snapshot consolidation before/after the run. Source protection, both-copy/source verification, per-file synchronization and family arrival gating remain. UUID/offset checkpoints cover crash recovery and renamed destination mappings. [The optimization checklist](PERFORMANCE_BACKLOG.md) tracks other suggestions separately.

Two alternating release comparisons used the old `cbafe61` ingest implementation with the identical benchmark-only harness, then updated/updated/baseline order. Each run copies 100 and 1,000 synthetic 4 KiB marker files to two disposable folders, then re-ingests. Both builds finished before measurement; source generation and final byte comparison are outside initial-copy timing. Progress callbacks poll snapshot identities/sizes and journal growth in both builds. [Anonymous reports](benchmarks/2026-10-21-ordinary-ingest-journal.json) retain all samples.

| Files | Old initial copy | Updated initial copy | Old re-ingest | Updated re-ingest |
| --- | --- | --- | --- | --- |
| 100 | 1,159–1,168 ms | 1,074–1,087 ms | 562–568 ms | 430–445 ms |
| 1,000 | 18,870–18,935 ms | 10,356–10,685 ms | 14,872–15,132 ms | 4,252–4,320 ms |

At 1,000 files, old snapshot publications were 2,000 and encoded payload was 743,787,000 bytes. Updated snapshot publications were four: 1,486,300 snapshot bytes plus 1,288,116 journal bytes, 2,774,416 total. At 100 files the old payload was 7,508,700 bytes versus 277,814 updated. Increasing file count tenfold grew old snapshot payload about 99-fold versus about tenfold for updated bookkeeping. These are observed encoded filesystem payloads, **not physical disk I/O**. Durable per-file appends remain; this does not remove per-file fsync or copying/checksum work.

All source and both-copy payloads matched, all 100/1,000 arrivals completed, and re-ingest verified all 200/2,000 existing copies. Tiny marker files isolate bookkeeping and are not decodable images; no RAW throughput, native UI smoothness, physical-card interruption or representative 10k/40k claim. OS caches and storage state are uncontrolled; attribute polling adds callback overhead. Reproduce with `sh scripts/benchmark.sh --ingest-journal`.

## SQLite statement reuse — 2026-10-21

[ADR 0030](decisions/0030-sqlite-statement-reuse.md) adds a per-connection cache capped at 32 prepared record-query statements and reuses existing default JSON coders across database records. Leases reset execution and clear bindings on success/failure, check reset errors before acknowledging success, and finalize temporary/cached statements at the appropriate lifetime boundary. Schema, FULL synchronization, transaction boundaries, pending-intent/XMP order and filesystem checks remain. This does not batch user-decision saves.

Two alternating release pairs used baseline `2d7bd5d` with only the identical benchmark harness added. The final pairs were repeated after the Swift 6.1 compatibility adjustment; earlier pairs are retained separately in the JSON. Both builds and strict tests finished before timing. Each fresh run uses 1,000 synthetic marker files per workflow, cold initialization and 10,000 warm public image-state/protected-review reads. Source generation/final byte checks are outside timing; normal identity/protection checks and cold-write durability remain inside. [Anonymous reports](benchmarks/2026-10-21-sqlite-statements.json) retain all values.

| Workload | Baseline | Statement reuse |
| --- | --- | --- |
| Ordinary cold indexing, 1,000 files | 215–217 ms | 213–234 ms |
| Ordinary warm image-state reads, 10,000 | 1,786–1,799 ms | 1,685–1,695 ms |
| Protected-review cold discovery, 1,000 files | 561–562 ms | 546–625 ms |
| Protected-review warm reads, 10,000 | 1,994–2,012 ms | 1,959–1,969 ms |

These are modest observed service gains (roughly 5–6% ordinary warm reads and 2% review reads), not a general UI/RAW speedup. Cold timings varied and include slower updated samples, so no cold-start improvement is claimed. Filesystem checks and durable cold writes still cost time. The deterministic store regression executes 80 decision/path operations using four application prepare calls and 76 cache hits; SQLite may still internally recompile prepared statements after schema/plan changes. Tests also cover stale bindings, nested leases/capacity, step/body/prepare/decode errors, automatic rollback, schema changes, close/finalization and Unicode review-session isolation/reopening. All generated file bytes remained unchanged and no image sidecars were created.

OS caches/storage state are uncontrolled and two pairs do not establish statistical confidence, physical-media behavior or representative 10k/40k/native frame targets. Marker files are not decoded. Reproduce with `sh scripts/benchmark.sh --sqlite-statements`; narrower UI invalidation remains a separate [checklist](PERFORMANCE_BACKLOG.md) item.

## Thumbnail observation and selection summaries — 2026-10-22

[ADR 0031](decisions/0031-thumbnail-observation.md) isolates photo display/readiness dependencies and caches selected-family summaries. [Anonymous evidence](benchmarks/2026-10-22-thumbnail-observation.json) contains two alternating release pairs: main `4b385f3` with only the identical benchmark harness, updated, updated, main. No concurrent builds/tests/native inputs during the timed runs; OS caches/scheduling uncontrolled. Run `sh scripts/benchmark.sh --selection-summary`.

| Synthetic model workload | Baseline, two runs | Updated, two runs |
| --- | --- | --- |
| Initialize 10k / 40k items | 8.2–8.3 / 18.3–19.3 ms | 11.1–11.3 / 27.8–28.0 ms |
| Load sample decisions, 10k / 40k | 27.1–27.2 / 108.9–112.9 ms | 33.3–33.9 / 140.7–141.3 ms |
| Select all, 10k / 40k | 0.32–0.33 / 1.23–1.24 ms | 7.12–7.15 / 32.94–32.97 ms |
| 2,000 summary + readiness queries, 10k selected | 5,134–5,424 ms | 0.05–0.06 ms |
| 2,000 summary + readiness queries, 40k selected | 23,567–24,841 ms | 0.10 ms |

Every result matched expected count/stars/flags/readiness. Setup and membership costs increased: each live photo now owns a display object, and selection changes maintain a represented-record snapshot. Repeated queries reuse one summary and a maintained Boolean instead of repeatedly expanding/mapping selections. This deliberately repetitive microbenchmark demonstrates removal of that work, not an equivalent whole-app speedup. Items are synthetic sample models, with no image pixels, filesystem/XMP or personal database writes. Representative 40k-shoot memory/RSS remains acceptance work.

Five new regressions cover actual Observation notification isolation, cached mixed summaries/Undo, unknown-family gating, verified pair arrivals/removal/session replacement/persisted reopening and filters/rating order. Native release checks on 1,000 synthetic JPEG/PNG gradients passed group thumbnail stars/flags, repeat-star clearing, two-step Undo, rotation/crop and Undo, three pages down/back, contact-sheet/filmstrip selection, density reflow and EXIF label configuration. All 1,000 image hashes matched after image-edit checks. No native frame/body-evaluation comparison or physical-trackpad/competitor smoothness claim is made for this chunk.

## File-backed workspace scale and readiness correction — 2026-10-26

[ADR 0032](decisions/0032-workspace-scale-profile.md) and the [reproduction guide](PERFORMANCE_TRACING.md#file-backed-10k40k-profiling) add a real-file pipeline scenario. [Anonymous reports](benchmarks/2026-10-26-workspace-scale.json) retain four baseline, four readiness-only intermediate and four final release runs on the reference 18-CPU/128-GiB/macOS 27.0.1 Mac. Each phase uses fresh processes in 10k,40k,40k,10k order, with fresh temporary SQLite databases, unchanged FULL durability and no overlapping builds/tests/native inputs during service timing. Three synthetic gradient templates are cloned with distinct file identities; these repeat pixels and lack real shooting metadata/RAW diversity. Preflight byte hashing warms filesystem caches. These are sequential phases, not randomized trials or physical-media acceptance.

The scale run exposed a regression in ADR 0031: constructing unknown selected IDs with set subtraction could traverse the full loaded-ready set for a single selection. Check only represented selected IDs instead. Reuse represented snapshots when explicit membership stays unchanged through sorting/focus; preserve invalidation for actual selection/family/inventory changes and implicit focus. Two regressions cover large unrelated ready sets and unchanged membership across sort/focus plus filter removal. Existing Observation/group/session/Undo tests pass.

| Service workload | 10k baseline → final, two runs each | 40k baseline → final, two runs each |
| --- | --- | --- |
| Forward/reverse/spread selection-to-Fit p95 | 68–70 → 14.5–16.2 ms | 227–229 → 15.3–17.9 ms |
| ISO sort with all selected, tied values | 676–696 → 214–222 ms | 2,731–2,745 → 912–929 ms |
| Rating sort with all selected, tied values | 712–743 → 282–284 ms | 2,966–2,988 → 1,161–1,183 ms |
| Pick filter removing all selected files | about 540 → 97–99 ms | about 2,193 → 400–415 ms |
| Largest nominal-10ms main-actor heartbeat gap | 1,259–1,299 → 389–395 ms | 5,251–5,255 → 1,593–1,621 ms |
| Select All | 420–423 → 384–386 ms | 1,725–1,781 → 1,589–1,620 ms |

The separate selected-only time in final navigation has p95 below 0.12 ms. Total service request latency includes model selection and the 2560px Fit pipeline, with a 64 MiB RAM cache; source-decode counts remain in the reports. Reverse visits can decode again when that working set is exceeded. View debounce, grid thumbnails, rendering and displayed-image verification are omitted. The readiness-only intermediate phase already removes most navigation scaling; the final guards primarily reduce group/order/filter stalls. Additional sub-timing adds an elapsed-time read per request in intermediate/final reports.

Final folder open is about 0.84 seconds at 10k and 3.5–3.6 seconds at 40k. After that, first Fit during indexing is 46–51 ms and selected readiness about 8 ms; complete decision loading remains about 10.3–10.4 seconds / 41.7–44.9 seconds, and EXIF about 2.4–2.5 / 9.8–10.5 seconds. First-photo service work can finish before the background index. This does not establish equivalent native first-display timing.

Service sampled peak RSS is about 502–507 MiB / 939–940 MiB. Preflight/hash URL inventory remains allocated alongside workspace inventory: use the before-workspace and phase checkpoints, not these values as native-app memory bounds. Native RSS samples during recording/finalization reach about 478 MiB for the 10k hitch capture, 460 MiB in the later 10k CPU run and 803 MiB after the 40k request. These are one process's profiled samples, not equivalent settled runs, whole-session peaks, memory-pressure or physical-footprint acceptance. All 50,000 source hashes and distinct inodes matched after native work; no source XMP was created.

### Native acceptance remains failed

The corrected release app still struggles with large collections during indexing. The 60-second 10k Animation Hitches capture reports 628 potential stalls, 59.4 seconds of union intervals, a maximum about 402 ms, and about 60.1 seconds sampled main-thread weight. The automated six-input scroll sequence timed out before completion accounting could be recovered; it is **not** a matched scroll comparison. Indexing was explicitly still active. Finalization took several minutes; a premature export failed, and only the export after successful completion is retained.

Shorter 15-second Time Profiler captures also show sustained main-thread work. Fixed categories include view-graph, lazy-grid and preference processing; they overlap and are not complete CPU attribution. They do not establish a single root cause. The 40k folder request/inspection exceeded 30s/60s accessibility timeouts; complete native control/scroll acceptance was not verified. The unresponsive test process was stopped after parking only the generated corpus, then recovered through an unavailable-folder screen. Original browsing context was restored through UI, both test shortcuts removed and the corpus restored. No personal image edits or pending user file jobs were initiated.

CPU-only analyzer mode reports missing stall metrics as null, never perfect scrolling. Four Python analyzer regressions cover process/reference filtering, missing data, interval merging and CPU-only privacy/null semantics. **No native smoothness/FPS improvement or 10k/40k-shoot acceptance is claimed.** Next priority is isolating/profiled UI update/layout work during indexing and the remaining initial large-group selection cost, before speculative decoding or a framework replacement.
