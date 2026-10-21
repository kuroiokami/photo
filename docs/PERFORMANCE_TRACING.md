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
