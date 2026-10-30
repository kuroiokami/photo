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

A separate three-photo built-in-sample native regression passes group stars/flags, two-step Undo, empty filtering and Clear Filters; original browsing context is restored afterward. This limited semantic check does not satisfy failed large-folder acceptance.

CPU-only analyzer mode reports missing stall metrics as null, never perfect scrolling. Four Python analyzer regressions cover process/reference filtering, missing data, interval merging and CPU-only privacy/null semantics. **No native smoothness/FPS improvement or 10k/40k-shoot acceptance is claimed.** Next priority is isolating/profiled UI update/layout work during indexing and the remaining initial large-group selection cost, before speculative decoding or a framework replacement.

## Combined shoot browsing and isolated UI regions — 2026-10-26

[ADR 0033](decisions/0033-combined-shoot-browsing.md) adds optional parent-folder aggregation and isolates header/progress, preview and saving-status dependencies in separate SwiftUI bodies. Per-photo display records and collection observation remain active; legitimate selection, sort, filter, geometry and image changes still update. A rendering regression verifies that changing progress redraws its region without re-evaluating the neighboring grid, and that grid-owned changes still redraw it. Repeated identical source-review contexts no longer invalidate the workspace on every decision batch.

[Anonymous evidence](benchmarks/2026-10-26-shoot-tree.json) contains two sequential release runs each for 2k photos in eight folders and 10k in twenty folders, plus a retained flat 10k stress control. The order is tree2k, tree10k, tree10k, tree2k, flat10k, with fresh processes/temporary FULL-durability databases and no overlapping builds, tests or native inputs during timing. Three project-created gradients are cloned with distinct inodes. Preflight hashing warms filesystem caches; repeated pixels/missing camera metadata are not a real shoot.

| Service measurement | 2k distributed | 10k distributed |
| --- | --- | --- |
| Inventory/model opening | 125–130 ms | 602–610 ms |
| First Fit after inventory, while indexing | 43–50 ms | 47–50 ms |
| Selected decision ready after inventory | 8.8–9.0 ms | 8.4–8.8 ms |
| Complete EXIF / decision indexing | 0.27–0.28 / 2.51–2.52 s | 1.31–1.33 / 12.69–13.03 s |
| Forward/reverse/spread navigation-to-Fit p95 | 14.9–18.3 ms | 15.0–19.2 ms |
| Select All | 3.5–4.1 ms | 15.0–20.7 ms |
| Sampled service RSS maximum | 418–422 MiB | 574–578 MiB |

These are pipeline/model timings, excluding the view debounce, thumbnail grid, rendering and presented frames. Service RSS includes retained preflight inventory and decoder/allocator memory, not native app memory or a peak bound. **Do not attribute differing tree/flat selection timings to the UI change.** The distributed corpus has ASCII frame names; the retained flat corpus has accented names and different path structure. The flat control still takes about 397 ms for Select All, consistent with the earlier slow operation. This is an added workload, not a matched before/after speedup trial.

Native scripted checks now complete on the distributed 2k/10k collections **and the existing flat 10k stress corpus**. A 10k-tree reload/scroll witness advances EXIF progress from 131 to 575 of 10k while the scrollbar moves; the flat witness advances 156→581. Returning scrolls, keyboard next-photo, Z to JPEG 100%/Fit, Contact Sheet and Select All pass. In 2k, same-named photos from two cards receive group stars/flags without affecting other cards, two-step Undo restores them, the day/card views show 1000/250, direct mode retains focus, and relaunch resets the scope. Native Trash confirmation lists two photos and two sidecars with relative paths and is cancelled; actual cross-folder recoverable moves, stale snapshots and source protection use automated disposable tests. This does not claim a new native Finder Trash round trip.

A short 2k Time Profiler recording finalized but exported **zero time-profile rows**. The analyzer correctly rejected it; no CPU/stall improvement is inferred. Its recording/finalization RSS sampling reached about 310 MiB. A separate 30-second 10k contact-sheet/indexing/input window reached about 447 MiB RSS. Different scenarios and profiler/automation overhead prevent a matched memory comparison. The process CPU statistic in the JSON is not main-thread sampling or frame time. Raw traces/XML and all images remain outside Git.

All 12k distributed image hashes and distinct inodes match their pre-native manifests; the 10k flat images still match their original generator seeds. Two disposable 2k XMP files reflect the explicit native decisions and Undo. Service reports hash every original before/after and write no source sidecars. No personal decisions/file jobs were initiated; the original three-photo Preview/settings were restored and only test shortcuts removed.

**Remaining:** physical-trackpad/presented-frame acceptance, usable matched native CPU captures, 40k desktop retesting, real mixed-camera/EXIF shoots, memory pressure, concurrent card I/O, large-group selection and save throughput. The prior 40k failure is not declared fixed by a successful 10k scripted check. Decoder/cache/durability settings are unchanged.

## Rapid full-contact-sheet experiment — 2026-10-26

**Row prototype withdrawn; rapid grid lag remains unresolved.** A user still reports rapid scrolling lag in the full Contact Sheet. The candidate replaced vertical lazy-grid track measurement with arithmetic row ranges, explicit tile widths and row-aware selection reveal. It was removed before delivery because it did not establish a reliable benefit. The final diff changes diagnostic tooling/documentation only. See [ADR 0034](decisions/0034-contact-sheet-row-experiment.md) and the [anonymous record](benchmarks/2026-10-26-rapid-scroll-experiment.json).

On the existing 10k synthetic JPEG/PNG corpus, two unprofiled release repeats consume **6.04 / 5.56 seconds of process CPU for the baseline and 6.15 / 5.53 for the candidate**. Each version first warms the same rows, completes indexing and performs three four-page scrolls down/back with accessibility inspection between steps. Rows run before baseline; these are two same-process repeats per version, not independent randomized trials. There is no reliable overall CPU reduction. Process CPU includes all Photo threads and accessibility handling; it is not scrolling frame time.

A complete 30-second baseline `sample Photo 30 2` capture uses fixed-position input with only a final tree inspection. All six inputs finish during capture and return to the top. Of 11,512 main-thread samples, 1,595 include hosting-view layout, 1,244 include SwiftUI focus traversal and 7,929 include event-loop wait. Categories overlap, include waiting and are not CPU milliseconds or presented frames. These identify diagnostic paths, not a sole cause or comparative improvement. Repeated tree inspection itself adds work.

The attempted matched candidate capture was interrupted by the locked Mac. After unlock, fixed-position retries encountered `noWindowsAvailable` / `windowNotFoundAtPosition`; Photo remained running and could still be inspected through accessibility. The last retry completed zero scroll inputs, and resumed window geometry was not controlled against the baseline. These captures are excluded, rather than described as app crashes, perfect scrolling or a speedup. An accidental debug package and earlier captures with different methods/incomplete windows are also excluded. The corrected prototype release package was signature-verified and matched the release executable UUID.

The discarded prototype's functional checks on 115 disposable JPEGs covered End/Home, column reflow with partial rows, keyboard grouping, direct stars, group Pick/Undo, marquee after scrolling, quick rotation/Undo, correct-photo Crop/cancel, labels and Preview/JPEG focus. Broad checks used debug; release returning scrolls passed at 10k. These functional successes do not justify retaining the UI rewrite. All 10,115 source hashes match with distinct inodes; three disposable JPEG sidecars reflect decisions/Undo, none in the 10k corpus. The original sample view/settings/empty sidebar and existing release app are restored, preserving the user's current window size.

The retained [sample analyzer](../scripts/analyze-scroll-sample.py) exports fixed aggregate fields, unions recursive/branched paths per category, accepts both observed main-thread header forms and refuses missing/invalid graphs. Raw samples, symbols, paths and photos stay outside Git. Next, evaluate a bounded native collection view and collect frame/hitch evidence before accepting another grid replacement. No physical-trackpad, real-shoot, 40k, memory-peak or Photo Mechanic parity claim.


## Native reusable contact sheet — 2026-10-26

[ADR 0035](decisions/0035-native-contact-sheet.md) retains a reusable native full grid around existing culling controls/image services. [Anonymous reports](benchmarks/2026-10-26-native-contact-sheet.json) cover the reference 18-logical-CPU/128-GiB/macOS 27.0.1 Mac, the same 2560×1640 window screenshot, 160-point density, no extra labels, one selection, settled indexing and a warmed route. Each run completes 18 fixed-position inputs: three repetitions of three down/three up inputs, four pages each, with one final AX inspection. Captures are 20 seconds and all inputs complete within them; recording and saving finish before export. No builds/tests/export work overlap the timed controls.

| Control | Previous grid | Native reusable grid |
| --- | --- | --- |
| 115 JPEG process CPU, two unprofiled repeats | 2.57 / 2.55 s | 1.57 / 1.55 s |
| 10k JPEG/PNG process CPU, two unprofiled repeats | 5.56 / 5.38 s | 2.34 / 2.21 s |
| 115 potential stalls / longest / union | 15 / 327 ms / 2,425 ms | 14 / 132 ms / 1,479 ms |
| 10k potential stalls / longest / union | 20 / 344 ms / 5,218 ms | 21 / 130 ms / 2,227 ms |
| 115 main-thread sampled CPU weight | 2,736 ms | 1,538 ms |
| 10k main-thread sampled CPU weight | 5,627 ms | 2,309 ms |

The main inclusive focus category falls from 1,265→73 ms and 3,147→72 ms; inclusive categories overlap and cannot be summed. The native implementation reduces process CPU and stall duration on this controlled task; stall count alone does not capture this result. These are potential-hang diagnostics, not confirmed dropped frames or presented FPS.

Uniform native cards reserve an edit-status line. Equal density/wheel input therefore does not expose identical photos: at the verified far 10k endpoint, first visible ordinals are about 250 baseline and 225 native. Do not report an isolated renderer percentage. The 115 route reaches the final row in both implementations; both return to the first viewport. The synthetic files repeat three gradients and lack shooting EXIF/RAW diversity. Cache-route warmup is observed, not proof of all-RAM hits. Phases/repeats are sequential, not randomized. Scripted input and the final AX inspection contribute work; CPU intervals include tool-call idle time and use whole-process counters.

Profiled RSS samples during recording/finalization are about 605 MiB baseline vs 314 MiB native at 115, and 680 vs 415 MiB at 10k. Histories differ (notably baseline 115 follows 10k); these are not settled matched memory runs, whole-session peaks, cache budgets or memory-pressure acceptance. See raw checkpoint aggregates in the anonymous report.

Native checks pass offscreen keyboard reveal, range/marquee identity after scrolling, post-drag group stars/flags and independent Undo, rotation/mirror/Undo, filtering/Clear Filters, density/EXIF reflow, group IPTC target access and JPEG Fit/100% return. 10k Select All reports 10,000 ready targets. Three adapter tests plus existing suites pass: 201 registered Swift tests, 199 executed/two optional RAW skips. Exact release packaging/signature checks pass. All 10,115 original hashes/inodes match; six expected 115-folder XMPs reflect decisions/Undo, with no 10k XMP.

AX snapshots sometimes omit labels in both baseline and native after background scrolling. An additional stable-host trial did not resolve that shared observation and is excluded/withdrawn; no resolved VoiceOver issue is claimed. Earlier locked/incomplete attempts are excluded. Broad VoiceOver, physical pinch/trackpad, real camera/ingest contention, distributed large shoots, 40k and pressure acceptance remain open. After the final unlock, both test shortcuts were removed and Sample Collection/Dawn/full Contact Sheet, density 160 and an empty sidebar were verified. Native cleanup is complete; the current window size is preserved.

## Visible-demand thumbnail scheduling — 2026-10-26

[ADR 0036](decisions/0036-visible-thumbnail-scheduling.md) separates actor admission from blocking work and uses two thumbnail workers, retaining one independent Fit worker. Cancellation retains opaque-work slots until actual completion; shared requests, selected promotion and session/generation/retired-session checks protect reuse. No prefetch, full RAW browsing decode, cache-budget or durability changes.

[Anonymous release reports](benchmarks/2026-10-26-thumbnail-loads.json) compare **the current scheduler with one/two workers**, not old/new app executables. On the reference 18-logical-CPU/128-GiB/macOS 27.0.1 Mac, source order is 1/2/2/1, disk order 2/1/1/2, within each fresh corpus process. Timings are sequential with no overlapping builds/tests/native inputs. At most 48 naturally ordered files are requested in consecutive 16-photo bursts at 480 pixels. Each pass starts with fresh application RAM caches. Source passes disable disk; disk passes use prepopulated records and a one-byte RAM cache. Hashing warms OS caches. Disk population/drain and hashes are outside timing.

| Corpus / mode | One worker | Two workers |
| --- | --- | --- |
| 48 synthetic 2400×1600 JPEGs, total source thumbnails | 157.1–165.0 ms | 78.1–80.0 ms |
| JPEG viewport-ready maximum across three viewports per pass | 52.8–59.3 ms | 26.1–27.0 ms |
| JPEG disk-hit viewport-ready maximum | 4.3–4.5 ms | 3.2–3.4 ms |
| Nine Sony ARWs, one source viewport | 149.2–329.8 ms | 80.0–82.9 ms |
| Sony disk-hit viewport | 2.9 ms | 2.1–2.3 ms |

Every source pass reports exactly 48/9 decodes; every disk pass reports 48/9 hits and no source decodes. All have zero failures, correct one/two-worker active bounds and successful selected Fit requests. Fit uses a separate serial pipeline with one concurrent 2560-pixel request: JPEG source timings are 12.8–54.8 ms and Sony 16.5–197.3 ms overall. First decoder initialization strongly affects those ranges and the first RAW pass; do not claim an isolated Fit speedup. Disk total duration can include waiting for Fit after thumbnails finish. The reported p95 is effectively the maximum of only three JPEG or one RAW viewport, not a robust tail-latency estimate. Cache bytes are retained thumbnails, not RSS/transient decoder limits. Repeated synthetic gradients lack camera EXIF; the RAW sample covers Sony only. First-touch hardware initialization, OS caches and fixed phase order remain confounders.

Native validation uses a separate temporary app identity/preferences while the user's personal browsing session stays intact. A new 115-JPEG fixture has distinct inodes to avoid previous derived-cache reuse. Cold thumbnails populate; ten rapid forward/reverse scroll inputs, End/Home, twelve Right/Left inputs, three-photo stars/Pick and independent Undo, Space/Z Fit/100% and switching to the 640×400 sample succeed without unavailable/stale pixels. All 115 source hashes match; three expected XMPs reflect explicit test decisions/Undo. No personal image changes or source-copy jobs. Final release UUID `98510087-AE2D-3975-AA42-5050FDA43735` passes two additional folder/sample cycles after the retired-session guard; the isolated shortcut is removed and only the test app is quit. The original folder/focus/Photo Home remain intact. Strict bundle verification passes. Retired-session request/reset rejection also has deterministic regression coverage.

These checks do not measure UI publication deadlines, presented frames, physical trackpad smoothness or old/new native CPU. Broad Canon/Olympus RAW, real removable media, large real shoots, concurrent ingest and memory pressure remain open. Nearby Fit preparation and cache-lock/metadata/CR3 work follow independently.

## Foreground-first nearby Fit preparation — 2026-10-26

[ADR 0037](decisions/0037-nearby-fit-preparation.md) adds one optional worker beside the reserved selected Fit worker, with 150 ms settling, at most two sequential neighbors and protected admission to the same 64 MiB cache. Active single-image Fit only; file workflows across windows, protected review, detail/comparison/setup/inactive scenes and ineligible storage suppress preparation. Opaque cancellation retains its slot. Ordinary thumbnails/detail and embedded-only RAW browsing remain.

[Anonymous reports](benchmarks/2026-10-26-nearby-fit.json) use the release executable UUID `2665CC6F-A7E6-335B-84C9-0059E21761D9` on the reference 18-logical-CPU/128-GiB/macOS 27.0.1 Mac. Read eight naturally ordered synthetic 2400×1600 JPEGs or eight local Sony ARWs, forward then reverse plus last/first jumps: 17 selections. For each fixed 250 ms or zero-dwell group, run preparation off/on/on/off in one quiet process, fresh 64 MiB cache per pass and no disk cache. No builds/tests/automated native inputs overlap timing. Hashing warms OS caches; order, first decoder initialization, other system activity and small repeated/single-camera data limit interpretation. Initial Fit is reported separately; later navigation has only 16 samples per pass. The service omits SwiftUI debounce, rendering and presented frames.

| Metric | Preparation off | Preparation on |
| --- | --- | --- |
| JPEG, 250 ms dwell, RAM-ready selections | 4/17 | 14–15/17 |
| JPEG, later navigation median | 19.5–23.0 ms | 0.038–0.046 ms |
| JPEG, source decodes including optional work | 13 | 14–15 |
| Sony ARW, 250 ms dwell, RAM-ready selections | 9/17 | 15–16/17 |
| Sony ARW, source decodes including optional work | 8 | 8–9 |
| JPEG, zero-dwell RAM hits / source decodes | 4/17 · 13 | 4/17 · 13 |
| Sony ARW, zero-dwell RAM hits / source decodes | 9/17 · 8 | 9/17 · 8 |

All selected requests succeed and original hashes match. Settled JPEG navigation maxima remain 24.1–26.2 ms with preparation versus 26.6–27.9 ms without: jumps or unfinished background work can still need a decode. Sony later-navigation maxima are 0.10–20.8 versus 29.0–31.0 ms; its baseline already caches the entire eight-image set, making medians uninformative for cold selection. Optional decoding is a modest additional cost on the settled route, not an I/O reduction claim. Sampled retained cache maxima are 58.6 MiB JPEG and 53.3 MiB Sony, not RSS/whole-session peaks or transient decode limits. There are no physical card/network/Canon/Olympus/concurrent-ingest results.

Native checks run in a separately identified temporary app, preserving the user's original Photo session. On 115 disposable JPEGs: settled forward/reverse Fit, twelve-step rapid forward/reverse, Z genuine 2400×1600 100%/Fit, fixed-reference comparison with candidate navigation, full-grid first/last endpoints, empty Picks filtering and Clear Filters pass. Three hash-verified disposable Sony clones with `.ARW`/`.arw`/`.ArW` extensions pass forward/reverse embedded previews. Returning to samples shows 640×400 rather than stale pixels. All 115 JPEGs, three RAW copies and their original sources match hashes; no RAW sidecars are created. No decisions or file-copy jobs were initiated this round. Both temporary shortcuts are removed and only the isolated app quit; original folder/focus/view/Photo Home remain intact. Strict ad-hoc bundle verification passes.

A finalized 20-second Time Profiler capture targets only the isolated process and confirms **14 Begin/End preparation intervals, five Begin/End nearby Fit loads and five Begin/End source decodes** during the native navigation/filter witness. Process identity and fixed event names are verified before aggregation; raw trace/XML stays outside Git. This confirms UI integration, not frame/input/CPU speed. One Command Line Tools `xctrace` lookup failed; the installed full-Xcode tool completed capture/save/export successfully. The isolated app's first automation launch took about 347 seconds; exclude that tool step from app-preview latency claims. Initial picker automation selected the previous folder; RAW checks are accepted only after the intended folder and all three files were explicitly verified. Physical trackpad/frame, broad-camera/large-shoot, pressure and concurrent-ingest acceptance remain open.

## Cache-read bookkeeping — 2026-10-27

[ADR 0038](decisions/0038-cache-read-bookkeeping.md) replaces the disk-hit publication-lock touch with bounded admission-lock recency hints. Writers still serialize index/filesystem work and merge hints before eviction. Existing source stamps, clear generations, record validation, budgets and original-byte protections remain. Hint saturation is approximate: one prior hint is discarded to accept a newly visited key.

[Anonymous release reports](benchmarks/2026-10-27-cache-contention.json) compare identical harness/core sources with only the disk-cache implementation restored to accepted HEAD for the baseline. Run fresh quiet processes in baseline/candidate/candidate/baseline order on the reference 18-logical-CPU/128-GiB/macOS 27.0.1 Mac. Nine synthetic 2400×1600 JPEG copies provide eight cached foreground photos and one cold writer. Clone 4,000 derived records to force lazy indexing of 4,008 records; no physical cold-media claim. Admit the writer before eight bursts of eight foreground requests, using two reader workers and one-byte RAM caching, then await maintenance and perform eight settled reads. Prepopulation/cloning warms OS caches; scheduling overlap is not deterministic. No builds/tests/native inputs overlap measured runs.

| Metric | Baseline repeats | Candidate repeats |
| --- | --- | --- |
| First eight-photo viewport | 2.24 / 1.76 ms | 2.51 / 2.47 ms |
| Maximum queued disk-hit readiness | 124.63 / 129.84 ms | 2.46 / 2.42 ms |
| p95 queued disk-hit readiness | 2.17 / 129.34 ms | 2.02 / 1.88 ms |
| Foreground disk hits / source decodes | 72 / 0 each | 72 / 0 each |

All original hashes match. The writer starts late enough that the first viewport is unaffected; baseline p95 varies with overlap. Report the observed maximum-wait reduction without inventing a universal p95/FPS improvement. Maintenance drain includes the foreground route before the final barrier, not isolated writer duration. Pixels repeat and metadata is synthetic. Cache budgets are not RSS bounds; no real-shoot, card, cold-device or native frame speed acceptance.

A deterministic test holds the writer under its publication lock: the candidate read completes before release, while the same regression against the old implementation fails after its five-second deadline. The gate is released and workers joined before cleanup. Bounded/coalesced hints, eviction, clear and concurrent read/store/clear tests pass; four Thread Sanitizer tests pass. The first sanitizer build could not discover Testing macros; retry with the standard repository plugin path succeeds.

## Reported idle exit and lifecycle diagnostics — 2026-10-27

No recent matching Photo crash report was found in local user/system diagnostics. Existing PhotoBench traps belong to separate earlier benchmark executions; older CPU-resource reports and a jetsam inventory do not identify this reported exit. One approximately eight-hour run of the installed build ends through AppKit's ordinary quit path and the user confirms choosing Quit. That is evidence about that run, not a dismissal or explanation of another disappearance.

[ADR 0039](decisions/0039-local-lifecycle-diagnostics.md) adds fixed local notices under `org.photo.lifecycle`, actual loaded-image UUID, uptime, optional RSS/physical footprint, active/window state, termination support and pending-work flags. Heartbeats run about once a minute when scheduled; App Nap/sleep/OS log buffering can delay observation. No photo data or network transmission, app-owned growing log, termination-policy change or unsafe crash signal handler. Initial native diagnostics report automatic-termination support false and match the executable UUID. Short synthetic idle/native results are below; crash/root-cause status remains open.

[Anonymous idle evidence](benchmarks/2026-10-27-idle-stability.json) records 61 liveness/RSS samples over 30 minutes for the accepted baseline and 41 over 20 minutes for an intermediate candidate, each viewing the generated 10k collection. Every sampled process remains alive until deliberate cleanup/Quit. RSS ranges are about 396.9–413.9 / 422.2–438.9 MiB; different histories, overlapping builds and sparse sampling prevent matched memory/CPU/peak claims. Automated Hide attempts still leave the recorded activity flag true: **do not claim continuous hidden/background coverage**. No overnight, sleep/wake or induced-pressure stability result. All 10k original hashes and unique inodes match, with no sidecars. Only isolated app shortcuts are removed; personal browsing preferences are untouched.

The intermediate idle executable `BC1922B4-0609-3E94-87AF-B843699B5A5B` precedes the final saturated-hint admission adjustment. Final executable `60BD8320-01FA-3162-BFC0-8B833B447675` separately passes native sample forward/reverse, genuine JPEG 100%/Fit, Contact Sheet, cache clearing/return-to-Fit and normal Quit; strict signatures pass. Loaded UUIDs match diagnostics for both builds. Intermediate logs contain launch/ready, 22 heartbeats and normal quitRequested/willTerminate; final logs include launch/ready/heartbeat and the same orderly quit pair. No background/sleep/wake/memory-pressure events were demonstrated natively. Raw logs stay outside Git. One first-launch automation call took about 265 seconds; it is not an app startup benchmark and is excluded from latency claims.

## Bounded Canon CR3 container reads — 2026-10-27

[ADR 0041](decisions/0041-buffered-cr3-container.md) replaces tiny per-field seeks/reads with one 4 KiB header window, capped at 1 MiB speculative bytes per request, and removes temporary integer arrays. Existing box/CMT1/JPEG bounds, cancellation, orientation, source-change checks and embedded-only fallback remain. A 128 MiB sparse sensor-payload regression reads less than 256 KiB; it does not decode sensor data.

The [anonymous release report](benchmarks/2026-10-27-canon-container.json) uses the SHA-verified CC0 EOS R fixture documented in [provenance](fixtures/public-raw-provenance.json), three warmups per mode and thirty alternating buffered/unbuffered pairs. Both modes use the same current parser and JPEG decode, maximum edge 2048; the actual embedded image is 1620 × 1080. The control isolates buffering, not the old integer-array implementation.

| Mode | File reads | Bytes read | Median | Nearest-rank p95 |
| --- | ---: | ---: | ---: | ---: |
| Unbuffered control | 27 | 233,724 | 8.277 ms | 16.018 ms |
| 4 KiB buffered | 12 | 278,112 | 8.449 ms | 10.614 ms |

Read calls fall at the cost of 44,388 extra bytes on this fixture. Warm preview latency stays approximately 8 ms; variable tails/background load do not establish a speedup. A 32 KiB pilot also had no median improvement and read 396,896 bytes, so the smaller window limits read amplification. OS caches/user load are uncontrolled. This is not app first paint, full RAW rendering, card throughput, frame smoothness, peak memory or broad-camera acceptance. EXIF/XMP source reuse and cold ImageIO metadata startup remain separate work.

Reproduce with `sh scripts/benchmark-canon-container.sh /disposable/public-eos-r.CR3 /tmp/canon-container.json`; the helper accepts only the documented public fixture and verifies its hash before/after. Native Canon-check release `9522ECFB-589E-322B-9FEF-A3936729D41B` displays the labeled 1620 × 1080 embedded preview while shooting information is still indexing. The original hash remains unchanged and no sidecars are created.

## Workspace recovery acceptance — 2026-10-27

The user clarifies the reported symptom as a running Dock icon with no window, rather than a confirmed process crash. [ADR 0040](decisions/0040-workspace-window-recovery.md) handles reopen requests and adds **Show Photo Window (⌘0)**. [Anonymous final-build evidence](benchmarks/2026-10-27-window-recovery.json) records final loaded UUID `60EB1FDB-DD31-30FB-BF89-4E099F4081FA` and local reopen/window-count events alongside isolated native close/reopen, minimize/reopen, menu/shortcut and normal-Quit checks. Canon Fit was checked in the preceding `9522ECFB-589E-322B-9FEF-A3936729D41B` build with identical imaging sources. Initial CI required extracting window commands from the large workspace builder; final native checks are repeated after that compiler fix. Unit tests cover weak lifetime, coalescing, missing openers, multi-window choice and offscreen geometry.

A locked Mac interrupted an attempt; final checks resumed after unlock. Direct physical Dock input/monitor removal and overnight/sleep/wake/pressure acceptance are not claimed. The initial native-tool connection delay is excluded from startup timing. The incident's original root cause is not established by adding explicit recovery; normal close/Quit/save barriers remain.

## Validated metadata read reuse — 2026-10-27

[ADR 0042](decisions/0042-metadata-read-reuse.md) retains one reader per workspace, independent lazy EXIF/embedded-XMP results and at most one short-lived ImageIO source. File identity, size and nanosecond modification/change times guard reads and hits. Defaults are 128 entries / 4 MiB accounted result bytes, separate from keys/allocator overhead and opaque ImageIO memory. Source cleanup is normally within roughly two to four idle seconds; App Nap/scheduling can defer it, but an expired source is not reused. Reload explicitly clears results. Sidecar parsing/conflict/write safeguards stay fresh and independent.

The [anonymous release report](benchmarks/2026-10-27-metadata-read-reuse.json) uses 512 generated 16 × 12 files, reuse off/on/on/off, with a fresh reader per phase. The first three phases use the first 24 files (18 JPEG with known EXIF/IPTC, six PNG) or four selected files; the fourth scans all 512 to exercise eviction. Paired queries request EXIF then XMP; repeated visits cycle through four files eight times. Returned dimensions/fields and all source hashes match. The uncached control is this same reader with entry retention disabled, including the same stamp checks; it does not recreate the historical implementation.

| Workload | Uncached sources → reused sources | Median per visit, uncached | Median per visit, reuse |
| --- | ---: | ---: | ---: |
| Cold EXIF, 24 files | 24 → 24 | 0.747–0.761 ms | 0.752–0.757 ms |
| Paired EXIF/XMP, 24 files | 48 → 24 | 1.467–1.469 ms | 0.864–0.967 ms |
| Repeated panel visits, 32 visits/four files | 64 → 4 | 1.457–1.468 ms | 0.031–0.032 ms |
| Cold EXIF beyond capacity, 512 files | 512 → 512 | 0.746–0.747 ms | 0.758–0.760 ms |

Cold EXIF performs **zero XMP reads** in both modes. The 512-file route retains exactly 128 entries with reuse enabled and none in the control; it establishes no cold-scan speedup. Repeated visits perform four property reads/four XMP extractions instead of 32 each, with 56 result hits. Paired queries retain about 27 KiB of accounted results at the phase endpoint; this is not RSS. No metadata values/paths or pixels are included in output. Run `sh scripts/benchmark.sh --metadata-reads` to reproduce; generated inputs are removed after the run.

Native release `F637E0D2-B198-31E6-8C93-78E9366F20C0` displays the expected generated camera/lens/ISO as keyboard focus moves. Reopening IPTC retains its embedded title, a newly added external sidecar overrides it, and removing that sidecar restores the embedded title. Reload retains selection/shooting information. The public EOS R fixture displays the 1620 × 1080 embedded preview, 6720 × 4480 sensor dimensions and shooting information, and its IPTC workflow opens. All original hashes remain unchanged; only a disposable test sidecar is written/removed. Temporary shortcuts and isolated test state are cleaned up.

This is a small metadata-service control with uncontrolled filesystem caches/background load, not a scrolling/frame, full RAW render, cold RAW initialization, card, large-shoot or memory-peak comparison. Downstream sidecar XML parsing is unchanged. Physical-input/media, broad cameras, pressure and concurrent-workflow latency acceptance remain open.

The initial CI compiler reaches a type-inference limit in the cost-accounting expression. Rewriting it as explicit Int additions preserves its result; strict tests and all release controls are repeated. Final native build `455ECDB5-F4AF-37B3-B053-C306091448EA` repeats embedded IPTC, Reload/shooting-strip and clean Quit; the broader sidecar/Canon checks above apply to preceding `F637E0D2-B198-31E6-8C93-78E9366F20C0`.

## Bounded decision saves — 2026-10-27

[ADR 0043](decisions/0043-bulk-decision-transactions.md) saves a rating/flag action or Undo/Redo group with one queue entry and chunks of at most 32 physical files. Ordinary saves commit pending intent before any XMP, publish coordinated atomic sidecars with fresh identity/digest checks, then acknowledge and rebase metadata together. Protected pre-copy review commits locally without source writes. Exact publication receipts recover interrupted acknowledgements, including before an immediate retry replaces intent; mismatching external metadata remains a conflict. SQLite FULL durability remains.

The [anonymous release report](benchmarks/2026-10-27-decision-saves.json) uses final executable UUID `102EED8D-7328-3C66-93EB-05C8A2DC55CF` on the reference 18-logical-CPU/128-GiB/macOS 27.0.1 Mac. Three iterations each create matched 1,000-file ordinary and protected-review workloads; mode order reverses in iteration two. Singleton and 32-file modes run the same final implementation, rather than a historical executable comparison. Fixture/schema/index setup and verification are outside timing; protection/identity checks, durable saves, ordinary XMP publication and yields are included. No builds/tests/native input overlap measured execution.

| 1,000 decisions | Singleton median (range) | 32-file median (range) | Save commits, singleton → batch |
| --- | --- | --- | --- |
| Ordinary folder with XMP | 2,266.9 ms (2,191.7–2,291.0) | 1,849.2 ms (1,812.4–1,899.8) | 2,000 → 64, intent plus acknowledgement |
| Protected pre-copy review | 806.1 ms (773.9–883.6) | 412.2 ms (404.1–415.2) | 1,000 → 32, local review only |

These medians are approximately **18% / 49% lower** for ordinary/review service time. Ordinary XMP still publishes 1,000 separate files. Counters exclude initial-index work and exceptional recovery commits; all measured saves succeed without rollbacks. Prepared-output retention peaks at 9,568 bytes in the batched ordinary control, under its 1 MiB limit. This accounts for retained output only, not parser/source buffers or RSS. Original marker bytes, restarted decisions and ordinary XMP values all match; protected review creates no sidecars.

Fifteen new regressions exercise transaction/automatic/nested rollback, partial publication/restart, descriptive baseline recovery and immediate retry, late external edits, malformed/conflicting sidecars, replacement, cancellation before/after intent, alias ordering, output bounds, protected-review composition/ownership, one queue entry per action, grouped Undo/Redo and persistence after workspace release. Full strict checks pass **255 registered Swift tests, 253 executed/two optional RAW skips**.

Native isolated release checks use 65 generated JPEG copies: Contact Sheet Select All, keyboard stars/pick, grouped flag Undo/Redo, direct thumbnail flag/star controls, a new group pick followed by normal Quit, relaunch/reloaded values and sample-view restoration. All 65 originals retain SHA256 and all 65 sidecars contain the final five-star pick. The temporary shortcut is removed and only the isolated app quits; personal Photo state stays intact. Protected-review native interaction is not repeated this round; its batch/Undo/protection behavior is covered by core regressions.

These are local-storage save/model controls and a small native functional check. Warm fixture/index activity, three trials, repeated synthetic bytes and background system load limit interpretation. No historical before/after, scrolling FPS, physical-card/large-shoot, concurrent-ingest, peak-memory or power-loss acceptance is claimed. UI publication budgets, detail navigation isolation, cold RAW startup and representative media/shoots remain separate work. Reproduce with `sh scripts/benchmark.sh --decision-saves`.

## Photo-first workspace and cooperative updates — 2026-10-28

[ADR 0044](decisions/0044-photo-first-workspace.md) replaces repeated rows with compact collection/culling controls, a shorter filmstrip and folder-focused sidebar. Stars, flags, rotate/mirror, crop and IPTC stay directly accessible; filters/options have named popovers and Done/Escape dismissal. **Focus on Photo (⇧⌘F)** and **Hide/Show Filmstrip (⌥⌘T)** restore prior panel choices. Native cancel actions retain Escape routing after navigator/comparison focus changes and give modal/popover dismissal priority.

At the same 1280 × 820-point native window, manual inspection of 2× screenshots estimates the old/new/default/Focus photo canvases as **1055 × 231 → 1071 × 472 → 1272 × 681 points**. These are approximate image-area bounds, not frame timings or sharpness measurements. The default preview gains roughly twice its previous height. Separate actual GeometryReader hosting tests measure **1002 × 484.2 / 1192 × 693** normal/Focus at 1200 × 800, and **762 × 374.2 / 952 × 585** at 960 × 640; hosting and native window chrome differ.

[ADR 0045](decisions/0045-cooperative-publication-and-detail-navigation.md) caps background model publications at 16 records, adapts toward a 2 ms target and yields/drains before final ordering. Selected promotion remains immediate. Per-photo exposure/inspector reads and local save/retry regions cannot invalidate the whole preview pane. Rectangle, focal point, magnification and commands use separate observable navigation state; comparison has per-pane channels. Native callback bursts coalesce into one weak deferred publication with teardown cancellation. Decoding, cache/durability budgets, orientation/crop transforms and genuine physical-pixel scaling remain.

[Four anonymous awake controls](benchmarks/2026-10-28-photo-workspace.json) compare accepted `919fc98` and candidate release processes in ABBA order over 10k generated distinct-identity 2400 × 1600 JPEG copies, fresh temporary SQLite databases and unchanged FULL durability. Preflight hashing warms filesystem caches; inputs repeat three gradient templates and lack real camera diversity. No builds/tests/automated native input overlap timing. Temporary idle-sleep assertions cover the runs. Candidate continuous-versus-awake heartbeat differences are below 0.001 ms; the unmodified baseline does not export this new field. Earlier trials coincided with verified OS sleep/wake and are excluded.

| Model service | Baseline range | Candidate range |
| --- | --- | --- |
| Metadata index | 3,208–3,286 ms | 3,182–3,187 ms |
| Decision index | 10,663–10,947 ms | 10,662–10,721 ms |
| Whole-job maximum main-actor scheduling gap | 391–411 ms | 391–397 ms |
| Select All | 390–402 ms | 385–389 ms |

Overall service throughput is similar in these two-per-mode trials; no robust speedup is established. Publications increase deliberately: metadata **159 → 654**, decisions **162–164 → 1,314–1,360**. Candidate maximum synchronous publication durations are **11.1–11.3 ms metadata / 61.9–64.4 ms decisions**, despite the 16-record cap; three metadata and 8–11 decision publications exceed 2 ms. Later rehash/allocation, Observation work and scheduling can exceed the target; these costs require further profiling. The ~0.4 s Select All operation remains a separate large-selection limitation. The cooperative controller does **not** establish a hard deadline or native scrolling FPS. Every report verifies original hashes and has zero metadata failures/decision errors.

Eight new tests cover panel restoration, real rendered navigator/scale-label isolation, per-pane Observation, native-report coalescing/teardown, actual window/canvas space, adaptive admission and complete metadata/decision drains without sidecars. Full strict checks pass **263 registered Swift tests, 261 executed/two optional RAW skips**. Existing progressive RAW, pixel/crop/orientation, keyboard comparison, source protection, filters, Undo and session rejection tests remain.

Native isolated release checks cover compact preview/grid, full-resolution JPEG Fit/100%, navigator panning, linked/unlinked comparison, B/N and decision keys with panels hidden, rotate/crop access and modal Escape priority, Focus/filmstrip restoration, settings-popup Escape and blocked background culling, visible active filters/clear, folder-tree parent/child navigation, group stars/flags and original SHA256 preservation. The extensive native pass uses `C12E4BA1-2DDB-3A4F-9D18-2D24D7061014`. Selection follow-up `AC7C02AB-BDFE-3F32-8D23-750791D4AA09` additionally verifies Select All → immediate keyboard stars, selected-only review → immediate navigation and visible Show All Photos, Focus/Escape and sample cleanup. Source model/imaging code is unchanged between these two builds. The temporary shortcut is removed, samples/Preview restored and only the isolated app quit; personal Photo stays untouched. Physical trackpad gestures/presented frames, full VoiceOver, Intel/minimum-OS, representative RAW/media/pressure/long-session and concurrent-ingest acceptance remain open.

Compatibility follow-up — 2026-10-29: Older CI Swift reaches an inference limit in the original workspace modifier chain and requires explicit actor isolation on the navigator callback. Smaller opaque view sections preserve modifier order and the callback explicitly remains on MainActor. Final compatibility release `286446C0-3CA1-3A78-A565-2273DF5E7C44` repeats strict local checks and native Focus/Escape, genuine JPEG 100%, navigator pan (50 → 62% vertically), crop/modal cancellation, filmstrip toggle and next-photo keyboard navigation. The temporary shortcut is removed, sample Fit preview restored, only the isolated app quit and all three original hashes match. Model/imaging code and benchmark controls are unchanged.

## Prepared identities and indexing capacity — 2026-10-29

[ADR 0046](decisions/0046-prepared-identity-and-index-capacity.md) addresses the profiled Unicode hashing and table-resize costs beneath ADR 0045's bounded publications. `PhotoItem` prepares native UTF-8 storage once while preserving every path byte and its original URL/filename. Indexing reserves model tables against the known inventory; selection avoids redundant expansion/Set construction. File validation, source protection, decoding, FULL durability and save boundaries are unchanged.

[Complete anonymous controls](benchmarks/2026-10-29-selection-publication.json) use retained accepted `99aa59f` and the candidate, sequential **baseline/candidate/candidate/baseline** processes for **each** 10k corpus. A separate owned debug-signed CLI copy supplies stack evidence; profiled/preliminary trials are excluded. Both fixtures use distinct-identity generated JPEG/PNG clones on local storage, fresh temporary databases and byte hashes before/after. Hashing warms OS caches. Temporary idle assertions and the suspension indicator show no material clock suspension in these controls. No builds/tests/native input overlap them.

| Model/service metric | Unicode baseline | Unicode candidate | ASCII baseline | ASCII candidate |
| --- | --- | --- | --- | --- |
| Select All, ms | 377.9–393.0 | **60.6–63.7** | 15.1–16.2 | **9.6–9.8** |
| Maximum decision publication, ms | 61.84–63.71 | **0.36–0.58** | 2.24–2.27 | **0.15–0.20** |
| Maximum metadata publication, ms | 11.95–13.47 | **0.216–0.224** | 0.65–3.45 | **0.068–0.077** |
| Metadata index, s | 3.26–4.22 | 2.35–2.37 | 1.75–1.79 | 1.72–1.81 |
| Decision index, s | 10.85–11.86 | 9.50–9.69 | 8.78–8.89 | 8.65–8.68 |
| Maximum whole-job actor gap, ms | 379.8–398.3 | 94.0–102.2 | 22.7–23.9 | 21.6–22.4 |

The median of two Select All samples improves about **84% in this Unicode-heavy case / 38% for ASCII names**. The earlier 0.4 s figure was not a universal camera-folder cost. All eight runs preserve originals, return 10,000 selected files and report zero metadata/decision errors. Four candidates publish at most 16 records per batch with zero measured 2 ms overshoots; this does not establish a hard deadline or native FPS. Unicode ISO/rating order plus collection rebuild falls from 221–225 / 279–286 ms to 62–63 / 78–82 ms; filtering falls from 96–100 to 28–29 ms. ASCII order/filter timings remain much smaller, with modest changes.

Earlier allocation has a startup tradeoff: selected-ready latency after opening is 8.2–9.4 → 10.5–10.6 ms in the Unicode controls; first Fit is 50.2–51.0 → 50.8–54.2 ms. ASCII selected readiness is about 7–8 ms in both, while first Fit varies 48.8 → 43.9–56.0 ms. Folder-open Unicode model work improves 843–860 → 691–714 ms; ASCII stays about 449–468 ms. No first-preview speedup is claimed. Sampled RSS overlaps (Unicode roughly 516–521 MiB; ASCII 484–493 MiB), with earlier model allocation; there is no memory-reduction or peak-RSS guarantee.

Strict local checks pass **266 registered Swift tests, 264 executed/two optional RAW skips**, including three new semantic regressions. Native isolated signed `E63B1DB1-0FB7-3C7C-8D1F-6DB8FBA1376F` verifies full-grid 10k Select All, inverse/deselect, unknown-group disabled actions and enabled controls after indexing. Three disposable 2400×1600 JPEGs with decomposed, Japanese and emoji filenames retain hashes after group stars/Pick, independent Undo/Redo, filtered group removal/Undo/Clear and persisted Reload. Both temporary shortcuts are removed; sample Fit preview restored and only the isolated app quit. No decision writes target the 10k corpus or personal photos.

Remaining work includes ~61–64 ms Unicode large-selection work, ~94–102 ms whole-job scheduling gaps and collection order/rebuild costs, plus native physical gestures/presented frames and representative RAW/media/40k/pressure/long-session acceptance. The service corpus, two samples per mode and native scripted checks establish limited scope; they do not establish universal throughput, camera-card behavior or competitor parity.

## Prepared collection updates — 2026-10-29

[ADR 0047](decisions/0047-prepared-collection-updates.md) moves membership/index construction and rating-map preparation into the existing background sort path, rejects superseded/stale/cancelled results, reuses a full-order index when clearing filters and short-circuits unrestricted visibility. Immediate decisions, filtering, selection fallback and history semantics remain; file I/O/validation, original-image bytes, source protection, durability, decode/cache budgets and genuine-pixel inspection are unchanged.

[Eight complete controls](benchmarks/2026-10-29-collection-updates.json) compare accepted `11290c4` with final release `647282D0-DE13-33F0-BA9A-F1C32B383D29` in quiet sequential baseline/candidate/candidate/baseline order for each 10k generated-file corpus. Databases/processes are fresh; hashing warms filesystem caches. No builds/tests/native input overlap controls; no material clock suspension occurs. Sampled/preliminary runs are excluded. The fresh baseline is faster than the preceding session, so compare these matched controls rather than historical absolute timings.

| Model/service metric | Unicode baseline | Unicode candidate | ASCII baseline | ASCII candidate |
| --- | --- | --- | --- | --- |
| ISO order and publication, ms | 40.4–40.7 | **34.5–34.6** | 6.7–6.9 | **5.3–5.5** |
| Rating order and publication, ms | 50.2–51.0 | **33.4–33.6** | 7.5–7.6 | **4.6–4.7** |
| Pick filtering after Select All, ms | 17.7–18.2 | 17.4–17.7 | 3.2–3.5 | 2.6–2.8 |
| Largest whole-job actor gap, ms | 61.9–68.1 | **51.7–54.5** | 18.5–21.7 | 15.1–18.8 |
| Select All, ms | 40.5–40.8 | 40.3–40.8 | 6.4–6.6 | 6.4–6.5 |

Medians of two samples show rating order about **34% faster for Unicode / 38% for ASCII**, and ISO order about **15% / 22%**. Unicode pick-filter cost is similar; releasing a large selection still contributes to it. Whole-job heartbeat gaps remain, and a 10 ms service heartbeat is not presented-frame latency. Every original hash matches; all runs return 10,000 selected files and zero metadata/decision errors. Generated EXIF/star values are tied, so diverse-metadata correctness comes from regressions, not a real-camera sort-throughput claim.

Metadata/decision indexing stays broadly similar (Unicode about 1.54–1.56 / 6.00–6.16 s; ASCII 1.14–1.16 / 5.56–5.63 s). First Fit is 39.2–40.3 → 35.2–39.1 ms for Unicode, 36.3–38.2 → 36.1–36.9 ms for ASCII; selected readiness varies 7–13 / 5–6 ms. No first-preview or general throughput claim. Sampled Unicode RSS overlaps roughly 503–506 MiB; ASCII baseline 478–488 / candidate 489–491 MiB retains an earlier/higher memory result. The full-order cache can remain with a filtered subset; no memory-reduction or peak-RSS bound is claimed.

Strict local checks pass **274 registered Swift tests, 272 executed/two optional RAW skips**, including eight new late-result/cancellation/index/history/grouped-review regressions; release products build. Native isolated signed `647282D0-DE13-33F0-BA9A-F1C32B383D29` passes: 10k endpoint selection retained under ISO order; two-photo selected-only review, Rating order and full restoration; empty Picks/Clear and endpoint recovery; three Unicode 2400×1600 JPEGs with rating reposition/focus, individual/bulk Undo/Redo, minimum-star filtered removal/restoration and saved Reload. Original SHA256 values match. Both temporary shortcuts are removed, sample Fit/Filename restored and only the isolated app quit. No physical gesture/FPS, broad-camera/card/network, 40k/pressure/concurrent/long-session claim.

After unlock, a 20-second Animation Hitches capture per accepted/healthy candidate uses the same 1280×820-point window, settled 10k generated collection, four forward/reverse page warmups, six down/six up pages and Select All/Deselect. Accepted/candidate main-thread sample weight is **2,758/2,772 ms**, potential-stall union **2,579/2,492 ms**, maximum **258/271 ms**, count **17/16**. One pair, profiling/accessibility overhead and similar/mixed values do **not** establish a scrolling gain. Raw traces remain outside Git; anonymous summaries are retained. Exported displayed-surface/frame-lifetime tables have 1,202/1,203 rows but no direct process column; visual-connection mapping has zero rows. These display events cannot establish Photo's presented FPS. Actual app-attributed physical-frame acceptance stays open.

An initial candidate capture is unusable as a warm-grid control because restored-folder thumbnails stay pending. Retain its worse diagnostics (5,037 ms main-thread sample weight; 4,366 ms stall union) as an excluded diagnostic with reason. The same issue is reproduced in accepted `E63B1DB1-0FB7-3C7C-8D1F-6DB8FBA1376F` and candidate builds; large Fit/EXIF/decisions work, the process is idle and Reload restores thumbnails. Cause is not established; initial session ordering is a hypothesis. [Issue #47](https://github.com/kuroiokami/photo/issues/47) tracks it as pre-existing. Native acceptance uses explicit-open/reloaded healthy sessions. One menu inspection timed out; fresh AX state and separate activation verified ISO/focus without an app hang.

Remaining costs include large selection/summary publication, immediate bulk rating/Undo resorting, first locale collation, actor gaps and native rendering. These changes do not complete broader acceptance.

## Restored-folder session repair — 2026-10-30

Native isolated release `A5A0E9D5-0F2F-3FDC-A082-710DAA6A6FB0` passes three verified fresh-process automatic restorations of a generated 10k Unicode JPEG collection without Reload. Each shows loaded Fit and filmstrip images during indexing. Full Contact Sheet End loads/selects the last thumbnail; Home/Space returns to loaded Fit. Temporary shortcut removed, sample image restored, only the isolated app quit and all 10k source aggregate hashes match across the remaining restoration checks. Native automation initially returns unusually slowly; tool durations are not app latency/FPS evidence. Broader camera/media/sleep-wake acceptance remains open.

[ADR 0048](decisions/0048-explicit-workspace-image-sessions.md) records the unseen-session race and explicit ownership/readiness boundary. The new deterministic negative control fails on the accepted code with four issues, then passes with the repair. Strict checks register 275 tests, execute 273 and skip two optional RAW tests. This corrects startup lifecycle behavior; cache/decode throughput and presented-frame targets are unchanged.

## Bulk actions and prepared rating keys — 2026-10-30

[ADR 0049](decisions/0049-prepared-rating-keys-and-bulk-actions.md) and [full ABBA reports](benchmarks/2026-10-30-bulk-actions.json) describe identical optimized public-API harnesses separately linked against accepted/candidate core objects. Generated sample IDs have varied initial stars and complete selections in Rating order. Correctness/focus/history checks run outside timing. No image/sidecar/database-record writes; this isolates synchronous model cost, not save completion.

| Action | ASCII 10k baseline → candidate | Unicode 10k baseline → candidate | Unicode 40k baseline → candidate |
| --- | --- | --- | --- |
| Select All + first summary | 4.0 → 3.0 ms | 30.8–32.3 → 25.5–25.6 ms | 131.3–131.9 → 112.1–112.2 ms |
| Flag all | 14.7–14.9 → 11.1–11.2 ms | 90.2–94.0 → 60.0–60.4 ms | 384.2–386.1 → 266.6–266.7 ms |
| Undo rating | 33.9–34.3 → 9.5–9.8 ms | 323.4–325.1 → 55.2–55.6 ms | 1450.9–1456.1 → 246.7–249.9 ms |

All 16 sample cases pass values/focus/history checks. Full reports include rating/Redo, ASCII 40k and all costs; the initial exploratory run is excluded from the matched comparison. Per-row prepared keys add transient memory, with no RSS/peak bound measured. Large batches still have material synchronous work. No physical frames, camera/media/40k-shoot, pressure/concurrent/long-session or broad smoothness claim. Run `sh scripts/benchmark.sh --bulk-actions` to reproduce model actions. Isolated signed release `987347F9-2D04-3D38-BAEC-70543B300E46` verifies 65 selected Unicode JPEGs in Rating order: independent stars/flags, flag and rating Undo/Redo, Picks/min-four-star removal by rejection, Undo restoration, Redo removal and Clear Filters. All 65 original hashes match; all sidecars contain Rating 4 plus independent reject fields pick -1/good false. A native automation timeout was recovered through fresh state and separate actions. The Mac locked before normal Quit/restart and shortcut cleanup; an asynchronous unlock request is pending. Do not claim restart/cleanup complete.

### Limited current RAW recheck

The [headless current-build report](benchmarks/2026-10-30-raw-culling-checks.json) reads the SHA-verified public Canon EOS R CR3 and nine supplied Sony ARWs across subfolders, with scratch databases and original hashes. Canon first Fit during indexing is **35.5 ms**, metadata completion **459.5 ms** and selected decisions ready **8.4 ms**. Sony parent-folder browsing produces first Fit **113.6 ms**, metadata completion **100.7 ms** and selected decisions ready **5.6 ms**. Both report zero decision/metadata errors, unchanged originals and less than 1 ms measured clock suspension. Sampled process peaks are 38.4 / 93.0 MiB for these small routes, not large-shoot budgets or peak guarantees. Metadata and Fit are independent; cold Canon EXIF work remains to investigate. No new RAW parser/backend is shipped here.

These are single current-build observations. Hashing warms the OS cache; no controlled cold-media or historical gain is inferred. They do not complete physical frames, broader cameras, removable/network media, 10k/40k mixed shoots, pressure, concurrent ingest or sustained sleep/wake acceptance. Raw traces/reports and personal filenames remain outside Git.
