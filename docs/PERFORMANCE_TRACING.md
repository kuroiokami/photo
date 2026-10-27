# Measuring interaction and background work

Photo emits local Apple signposts under subsystem **org.photo.performance**, category **PointsOfInterest**. Names/generated request IDs contain no photo names, paths, EXIF, captions or hashes. There is no network telemetry. Disabled tracing skips interval-state allocation. Raw system/process traces may contain private information; keep them outside Git and publish anonymous aggregates only.

## Native Instruments workflow

Build an optimized app with `sh scripts/build-app.sh --release`. Full Xcode/Instruments is optional for profiling; ordinary builds can use Command Line Tools. In Instruments' SwiftUI or Time Profiler template, include the `os_signpost` instrument and filter to Photo and the subsystem above. Add Hitches/Allocations/File Activity as appropriate.

Record folder reload/scrolling, rapid forward/reverse navigation, stars/flags during loading, EXIF/rating sorting, focus inspection and culling during ingest. Use disposable images for writes. Repeat with identical corpus, window, display and storage. Separate cold from warm visits. Service timers/accessibility-tool wall times are not frame latency.

| Marker | Meaning |
| --- | --- |
| OpenFolder / FolderInventory | Workspace folder operation / off-main inventory |
| MetadataIndex / ReadEXIF / PublishMetadata | Indexing / property reads / grouped publication |
| DecisionIndex / PublishDecisions / SelectedDecisionReady | Loading / grouped publication / focused-photo readiness |
| ThumbnailRequest / FitRequest | View task, including waits and cold Fit debounce |
| ThumbnailLoad / FitLoad / SourceDecode | Actor work / decoding; compare with request to inspect queue delay |
| ThumbnailCacheWrite / DiskThumbnailHit | Background disk-cache writing / synchronous cache reuse; writer intervals have their own IDs |
| RAMResultPublished / ImageResultPublished / ImageRequestCancelled | Accepted view state or cancellation, not compositor presentation |
| ApplyDecision | Immediate decision/filter/selection work |
| DecisionSaveQueueWait / DecisionPersistence | Waiting for previous saves / persistence work |
| SaveDecision / LocalDecisionCommitted / DecisionXMP | Regular decision commit / sidecar sync; local commit does not mean XMP completed |
| SaveSourceDecision / LocalReviewCommitted | Protected-source local saving without a card sidecar write |
| FullDetail / FocusRegionReady | Explicit detail work / early full-quality RAW patch |
| VerifiedIngest / ReviewedIngest / VerifiedFamilyArrival | Copy job / arrivals after existing verification/receipt rules |

Preview request and worker/decode/cache intervals share generated IDs across actor calls. Independent jobs have their own IDs. Attaching mid-request can yield incomplete intervals. A long request can include actor wait, storage or publication; inspect stages separately.

## Repeatable service scenarios

```sh
swift run -c release PhotoBench --generate /tmp/photo-tracing-corpus 1000
swift run -c release PhotoBench --workspace /tmp/photo-tracing-corpus > /tmp/photo-workspace.json
swift run -c release PhotoBench --workspace-ingest /tmp/photo-tracing-corpus > /tmp/photo-workspace-ingest.json
```

Generation refuses an existing folder. Synthetic JPEG/PNG gradients vary in orientation, dimensions and extensions; this is not a real-camera RAW/focus corpus. The workspace harness uses a fresh temporary SQLite database; metadata/decisions overlap the first Fit preview. All original image bytes are hashed before/after. Reports omit source names, paths, hashes, metadata values and pixels.

`--workspace-ingest` makes a disposable card folder from up to 24 input images, then verifies copies to two temporary destinations while selecting first/middle/last during indexing. Readiness waits poll at 1 ms, not keyboard-to-screen timing. It measures same-machine contention, not physical card/network throughput. Temporary copies/databases are removed; generated inputs remain for repeats.

Publication counters count model update groups, not SwiftUI body evaluations or per-dictionary notifications. The nominal 10 ms heartbeat includes OS/scheduler delay and is not frame time. Report stage timings/counts/errors/source-byte protection together. See [results](PERFORMANCE.md) and [remaining experiments](WORKFLOW_PERFORMANCE_RESEARCH.md).

API reference: [Apple OSSignposter](https://developer.apple.com/documentation/os/ossignposter).

## Contact-sheet native stall reports

With full Xcode selected and the release app open, warm the same rows, finish indexing, use a fixed window/display and record a repeatable scroll sequence:

```sh
xcrun xctrace record --template 'Animation Hitches' --attach Photo --time-limit 30s --output /tmp/photo-scroll.trace
python3 scripts/analyze-scroll-trace.py /tmp/photo-scroll.trace > /tmp/photo-scroll-summary.json
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
```

Wait for xctrace to finish saving and exit successfully before exporting; an early export can report Document Missing Template Error. If Command Line Tools is selected, use the full Xcode developer directory or pass `--xctrace /path/to/xctrace` to the analyzer. Only attach to one Photo process. Keep raw traces/XML outside Git: they can include process environment, symbol and filesystem information. The analyzer emits fixed aggregate fields and discards temporary exports.

Compare equal input counts and fully captured input windows, with warm/cold state and indexing recorded. Scripted accessibility input adds focus/inspection overhead; a native physical-trackpad run is separate acceptance. Reports contain potential main-thread stall counts, their union/maximum duration and sampled CPU weight. These are not displayed FPS, confirmed dropped frames or body-evaluation counts. Inclusive CPU categories overlap. Frame-lifetime/surface tables without reliable app attribution are deliberately excluded. Baseline findings and incomplete comparisons belong in [performance notes](PERFORMANCE.md), not fastest/smoothest claims.

## File-backed 10k/40k profiling

Generate only into **new disposable folders** on a filesystem supporting `clonefile` (normally APFS). This reuses the existing three project-created JPEG/PNG gradients with distinct inodes and mixed extension spellings. It saves physical storage; repeated pixels/no EXIF are not a representative camera shoot. Unsupported cloning or existing output folders fail rather than fall back to large physical copies. Hidden seed images stay outside the browsed inventory. No generated pixels belong in Git.

```sh
sh scripts/benchmark.sh --generate-scale /tmp/photo-scale-10000 10000
sh scripts/benchmark.sh --generate-scale /tmp/photo-scale-40000 40000
sh scripts/benchmark.sh --scale /tmp/photo-scale-10000 > /tmp/photo-scale-10000.json
sh scripts/benchmark.sh --scale /tmp/photo-scale-40000 > /tmp/photo-scale-40000.json
```

Run fresh processes sequentially without overlapping builds, tests or native inputs. Repeat in reverse size order. The database is temporary and FULL durability remains enabled; no source-image/sidecar or shared thumbnail-cache writes occur. All image bytes are hashed before/after. That hashing warms the filesystem cache: process/database freshness is not physical cold storage.

Reports separate folder inventory/model construction, first Fit and selected readiness during concurrent indexing, full indexing, forward/reverse/spread Fit requests, cached Fit and Select All/filter/sort costs. Updated reports include selection-only navigation time. Returned model identity checks are not displayed-image verification. The service pipeline omits the view's 35 ms cold debounce, grid thumbnails and native rendering. Revisited rows can decode again when the 64 MiB Fit working set is exceeded; source-decode counts are reported.

Sampled process RSS includes preflight inventory/hash allocations and a retained input URL list alongside workspace inventory. Use the pre-workspace/phase checkpoints; do not call it native Photo memory or a peak bound. Capture the actual app separately with the same window/density, settled EXIF and all-selected readiness, then return to one selected photo and warm the same rows. Record scripted inputs and capture duration alongside native RSS samples and finalized Animation Hitches aggregates. Accessibility inspection and tracing add overhead; potential stalls/main-thread sample weight do not measure presented FPS or physical-trackpad feel. Raw traces/exports stay outside Git.

See [ADR 0032](decisions/0032-workspace-scale-profile.md) and [performance results](PERFORMANCE.md) for the readiness traversal regression, correction and remaining large-group costs. Mixed-camera/EXIF, physical media, concurrent-copy pressure and real-shoot memory acceptance remain separate.

### Short CPU-only native captures

If Animation Hitches capture/finalization overhead is excessive, use a short Time Profiler recording to inspect work without inventing absent hang statistics:

```sh
xcrun xctrace record --template 'Time Profiler' --attach Photo --time-limit 15s --output /tmp/photo-index-cpu.trace
python3 scripts/analyze-scroll-trace.py /tmp/photo-index-cpu.trace --cpu-only > /tmp/photo-index-cpu.json
```

Wait for successful recording/finalization exit before exporting. CPU-only schema 2 reports `stallDiagnosticsMeasured: false` and null stall values, with fixed anonymous CPU categories. It does not measure scrolling FPS, potential-hang counts or displayed images. If input inspection times out or indexing never settles, report that failed acceptance rather than treating the run as warm/complete. External RSS sampling around record/finalization must identify its full sampling window and profiler overhead.

## Shoots spread across subfolders

Prefer a parent shoot with card/day folders as the routine workload. Use the single-directory 10k/40k runs above as additional stress checks. Build only disposable synthetic trees; the generator refuses existing leaf folders:

```sh
sh scripts/benchmark.sh --generate-scale '/tmp/photo-shoot/Day 1/Card A' 500
sh scripts/benchmark.sh --generate-scale '/tmp/photo-shoot/Day 1/Card B' 500
sh scripts/benchmark.sh --generate-scale '/tmp/photo-shoot/Day 2/Card A' 500
sh scripts/benchmark.sh --scale-tree /tmp/photo-shoot > /tmp/photo-shoot-report.json
```

Schema 2 reports `includesSubfolders`; the 40k file ceiling applies to the entire chosen tree. This command runs the real recursive workspace pipeline with distinct identities, relative labels, complete indexing, selection and navigation. It retains the same hashing/cache/database/RSS limitations as `--scale`. In the native app, select the parent and turn on **Include Subfolders**; record whether EXIF indexing is still active during input. Also test a normal individual card folder. Match scope, files, window/density, input count, cache and indexing state before interpreting before/after timings. Neither a successful scripted input nor CPU-only tracing measures presented FPS.

## Native `sample` fallback

When an Instruments capture exports no usable CPU rows, a short macOS sample can expose layout/responder stacks:

```sh
sh scripts/build-app.sh --release
xcrun dwarfdump --uuid .build/release/Photo .build/Photo.app/Contents/MacOS/Photo
# Verify the two UUIDs match, then launch the packaged app.
sample Photo 30 2 -file /tmp/photo-scroll.sample
python3 scripts/analyze-scroll-sample.py /tmp/photo-scroll.sample > /tmp/photo-scroll-sample-summary.json
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
```

The build script defaults to debug when `--release` is omitted. Verify the actual packaged binary for every comparison; discard mixed-configuration runs. Only sample one Photo process. Keep raw sample files outside Git. The analyzer emits no raw symbols, paths, captions, addresses, identifiers or filenames. It checks sample-weight consistency and unions stack branches/recursion within each category; categories overlap and must not be added together.

These are **stack sample counts including waits**, not CPU milliseconds, frame/body counts, hitches or FPS. Sampling and accessibility inspection can substantially change the workload. Finish indexing, warm the same rows, hold the window/density/selection/labels fixed and ensure all input ends before capture stops. Record activation and inspection steps too. Use fixed-position input with a final inspection to reduce repeated accessibility serialization; confirm scrolling actually occurred and returned. Retain unprofiled controls and report an inconclusive result honestly. [The row-layout experiment](PERFORMANCE.md#rapid-full-contact-sheet-experiment--2026-10-26) was withdrawn because no reliable overall improvement was established.

## Cold application-cache viewport scheduling

```sh
sh scripts/benchmark.sh --thumbnail-loads /path/to/disposable-jpegs
sh scripts/benchmark.sh --thumbnail-loads-tree /path/to/reference-raw-shoot
```

Read-only original hashing surrounds at most 48 supported photos; the tree option includes subfolders. Derived disk records are temporary. The report compares the current scheduler with one/two workers, source order 1/2/2/1 and disk order 2/1/1/2, using 16-request bursts and a concurrent independent Fit request. Source passes use fresh RAM/no disk; disk passes force record reads. Failures, Fit success, active bounds, source/disk counts and retained cache bytes are explicit. Empty/unreadable input returns an error. Run quiet release processes sequentially; hashing warms OS caches, initialization and phase order matter, and these are service timings, not physical cold-card, UI/FPS or RSS measurements. See [ADR 0036](decisions/0036-visible-thumbnail-scheduling.md) and [evidence](PERFORMANCE.md#visible-demand-thumbnail-scheduling--2026-10-26).

## Nearby Fit preparation controls

```sh
sh scripts/benchmark.sh --nearby-fit /path/to/disposable-jpegs
sh scripts/benchmark.sh --nearby-fit-tree /path/to/reference-raw-shoot
```

At most eight images, 17 forward/reverse/jump selections, fresh 64 MiB Fit caches and preparation off/on/on/off per 250 ms/zero-dwell group. Reports separate first Fit, subsequent service times, RAM-ready hits, selected failures, source decodes including optional work, active bounds and sampled retained cache bytes. Original hashing warms OS caches; disk thumbnails, view debounce/rendering, physical input and ingest are excluded. Eligibility can suppress optional work on cards/networks/ejectable/unknown volumes. Run sequential quiet release processes; wait for cancelled workers to finish before the next phase. Empty/one-photo input returns an exit-2 error.

In native captures, fixed `NearbyFitPreparation`/`NearbyFitLoad` intervals distinguish optional work from foreground Fit. Confirm the target process and matched event types before exporting anonymous counts; raw traces can contain private data and stay outside Git. See [ADR 0037](decisions/0037-nearby-fit-preparation.md) and [actual evidence](PERFORMANCE.md#foreground-first-nearby-fit-preparation--2026-10-26). Integration counts do not measure presented frames or physical input.
