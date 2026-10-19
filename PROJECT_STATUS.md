# Project tracker

Last updated: 2026-10-19

This is the maintained handoff for humans and AI contributors. Follow [AGENTS.md](AGENTS.md); update this file with behavior, setup, validation and delivery changes. See [development milestones](docs/DEVELOPMENT_PLAN.md), [design/research](docs/CULLING_DESIGN.md), [architecture decisions](docs/decisions/0004-fast-culling.md), and [performance evidence](docs/PERFORMANCE.md).

## Current state

Photo is a native SwiftUI/SwiftPM macOS 14+ folder-first photo culling app. The fast-culling implementation is pushed on `codex/fast-culling` in [draft PR #2](https://github.com/kuroiokami/photo/pull/2), in separate RAW/EXIF, ratings/persistence, and detail-view chunks. Original image bytes and embedded metadata remain untouched. Sony ARW browsing uses embedded previews; genuine RAW rendering happens only on explicit 100% inspection.

## Installation and use

Use macOS 14+, Apple Swift 6+ and built-in `swift format`. Clone `https://github.com/kuroiokami/photo.git`, enter the checkout, then run `swift run Photo`. For a Finder-launchable development bundle: `sh scripts/build-app.sh`, then `open .build/Photo.app`. The helper now seals the local bundle with an ad-hoc signature; it is not Developer ID signed, notarized or an installable release. No external packages, API keys or Package.resolved are required. System SQLite, ImageIO, Core Image and Foundation XML supply storage/imaging support.

- Command-O opens visible regular JPEG/PNG/Sony ARW files in one folder, case-insensitively. No recursion or symlink following. Command-R reloads and preserves selection where possible. No live file watching.
- Arrows navigate; up/down move a grid row, Home/End select ends. Navigate menu commands keep browsing available after preview/control interactions. Space toggles preview, Escape hides it. Thumbnail size and split pane are adjustable.
- P/X/U set pick/reject/unflagged; 0–5 set independent stars. Shift applies and advances once. Auto-advance is visible, initially off and remembered. Reject never deletes or moves an image. Edit menu provides Undo/Redo.
- Filters combine flag state and minimum stars; Clear Filters restores all. Rating sort is highest first. EXIF sorts are numeric, missing-last, with natural filename ties. Sorting waits for metadata indexing and preserves selection. The optional inspector shows capture time, camera/lens, exposure, ISO, focal length and dimensions; a compact exposure strip stays visible.
- Fit shows a fast bounded preview with source/resolution badge. 100% or double-click requests genuine detail around the pointer; scroll/drag to pan and inspect the navigator. One image pixel equals one physical display pixel. Fit/double-click returns; changing photo resets to Fit. Unsupported/oversized RAW detail retains the fit preview with an error/retry state.
- Samples are temporary. Real decisions persist in `~/Library/Application Support/Photo/decisions.sqlite`; normal quit drains queued saves. The UI distinguishes Saving, Saved, local-only failures and XMP conflict.

## Storage and recovery

SQLite saves decisions and pending sync before sidecar writes. ARW uses `basename.xmp`; JPEG/PNG use `filename.jpg.xmp` / `filename.png.xmp`. Other apps may not recognize JPEG/PNG sidecars. RAW+JPEG remain separate items. XMP stores stars independently of flags, preserves unrelated properties/develop settings semantically, and writes coordinated atomic replacements. Entities, symlinks, malformed/ambiguous packets and unsafe collisions are not rewritten.

Read-only folders retain local decisions and expose Retry XMP Sync. Reload imports external decisions when no local edit is pending. External changes conflicting with pending decisions require Use My Decisions or Use External Decisions. File identities plus replacement fingerprints and captured request identities protect queued decisions from attaching to replaced files. Direct Lightroom round-trip verification remains pending; field compatibility must not be presented as tested application interoperability. Sudden process termination can lose changes still marked Saving.

## Feature status

| Capability | State |
| --- | --- |
| Native shell, samples, lazy contact sheet and selected preview | Implemented; native checks passed |
| JPEG/PNG and case-insensitive Sony ARW | Implemented; real ARW/JPEG checks passed |
| Embedded-only RAW fit, provenance, separate image workers and LRU caches | Implemented; benchmarked on the reference Mac |
| EXIF inspector/background indexing and numeric sorts | Implemented; numeric/timezone tests and native inspector/ISO checks passed |
| Independent flags/stars, shortcuts, filters, auto-advance and Undo/Redo | Implemented; automated and native checks passed |
| Durable local SQLite and preserving XMP sync/conflicts | Implemented; fixture tests, native undo/reload and database restart tests passed |
| Fit/physical-pixel 100%, pan, navigator, explicit Apple RAW rendering | Implemented; fixture and local real-RAW tests passed; native detail/scroll checks passed |
| Lightroom application-level interchange | Not verified |
| Other RAW/HEIC, pairing, multi-select, batch file organization | Planned |
| RAW histogram, focus peaking, exposure adjustment, comparison | Planned |
| Wider hardware/camera/macOS/accessibility coverage and release distribution | Pending |

## Latest reliability follow-up — 2026-10-19

The large-folder follow-up adds a read-only `PhotoBench --workspace` mode with a temporary database, real concurrent metadata/decision indexing, first-preview timing, sorting and sampled main-actor gaps. It fixes per-photo whole-directory ARW collision scans, repeated SQLite opens/schema setup, redundant path-map writes, late-session metadata reads, external-decision rating order and misleading corrupt-detail memory errors. See [decision 0005](docs/decisions/0005-large-folder-persistence.md) and the [aggregate report](docs/benchmarks/2026-10-19-large-folder.json).

Observed initial/repeat decision loading for 2,000 synthetic ARW-name/XMP pairs fell from 35.90/35.53 seconds to 2.27/0.66 seconds. These are persistence fixtures with invalid image bytes, not camera compatibility evidence. For 2,000 valid synthetic JPEG/PNG files, initial/repeat loading fell from 2.54/1.73 seconds to 1.90/0.43 seconds; first preview stayed about 44 ms during indexing. Single before/after process runs, uncontrolled OS caches, and synthetic EXIF limits are documented in PERFORMANCE.md.

All nine user-supplied ARWs were copied into an isolated shallow test folder and checked individually for embedded previews, genuine full detail and byte preservation. All are Sony ILCE-7CR: eight orientation-1 images and one orientation-8 portrait. This broadens file/orientation coverage, not camera-model coverage. Preview phase p95 was 21.72 ms and cached p95 0.014 ms, but first preview in a fresh workspace process during indexing took 179.61 ms; the first thumbnail took 166.85 ms. Those first-open observations exceed 150 ms and remain explicit optimization work. Do not substitute the post-thumbnail preview phase for startup latency.

The final local suite passed **42 tests** (29 core + 13 UI/imaging), with the optional real-camera test enabled and checking all nine ARWs. CI without that local corpus executes 41 and skips one. New regressions cover eight ARW extension case spellings with actual sync/restart, external-rating reorder/selection, 10,000-item navigation followed by a late metadata/session change, and corrupt detail diagnostics. FULL SQLite synchronization, conflict checks and original-image protection remain in place.

Native checks confirmed pick/stars, external XMP conflict detection, Use External Decisions moving the selected item to the top of Rating sort, genuine 9504 × 6336 detail, one-step navigation resetting Fit, and opening/End navigation in a 2,000-image collection. Native picker observations sometimes reported a disabled confirmation button even though Return successfully confirmed the folder. Picker experiments were discarded; the existing implementation remains. These are functional checks, not measured frame/input latency. Lightroom application-level exchange remains unverified because the earlier isolated import UI could not be controlled; no new Lightroom verification is claimed.

## Validation

Historical fast-culling evidence before the reliability follow-up: `sh scripts/format.sh` formats; `sh scripts/check.sh` performs strict lint, warnings-as-errors build and Swift Testing. The real-camera-enabled local run passed **35 tests** (23 core + 12 UI/imaging), with `PHOTO_RAW_TEST_FOLDER` pointing at a disposable folder. The recovery follow-up adds one fault-injection case: the final standard run passed **37 tests**, with the optional real-camera case skipped (38 registered tests: 26 core + 12 UI/imaging). Without that environment variable the real-camera integration case is skipped; CI must not be described as testing personal ARWs. Tests cover existing browsing/session/cache behavior, EXIF numeric/timezone handling, source-byte preservation, independent decisions, filtered advancement/empty recovery, rating ordering, Undo/Redo, restart persistence, external conflicts, namespace/develop preservation, malformed/entity/symlink sidecars, read-only retry, replacement identity, ordered quit-time saves, full-detail orientation/limits/cancellation, and local genuine Sony RAW detail. Ambiguous case-only filenames are representable only on case-sensitive volumes; that test branch is conditional.

Reference release results: three 61 MP Sony ARWs returned embedded previews at p95 19.31 ms and cached p95 0.016 ms, sampled CLI peak RSS 87.16 MiB. Seventeen real 50 MP JPEGs returned preview p95 142.14 ms and cached p95 0.017 ms, peak RSS 447.38 MiB. All hashes matched and image failures were zero. These are pipeline timings from small corpora with uncontrolled OS caches, not UI frame timing or universal camera guarantees. See the aggregate report and performance limits.

Native validation additionally confirmed visible/remembered Auto-advance, picks filtering and undo recovery, actual 9504 × 6336 RAW detail, ratings during scrolling, Retina sample scale, and double-click entry to detail. The final native build also passed double-click entry followed by one-step arrow navigation/reset to Fit, Space hide/show after preview interaction, and the corrected empty-filter message. Auto-advance persisted through restart and was restored to its original off setting. Disposable personal-photo copies were removed after rechecking original hashes; the app was left on samples. An isolated Lightroom catalog was created for an interchange attempt, but its import controls were not usable through the available UI automation. Zero photos were imported; the disposable catalog was confirmed closed and removed, and both original/copy ARW hashes matched. After explicit user approval, the original catalog identity was verified and Lightroom was quit; process checks confirmed it had closed. No imports or edits were made in the original catalog. The round trip therefore remains unverified. Minimum macOS and Intel remain untested. Linker warnings about missing developer framework directories were nonblocking in the local CLT toolchain.

## Architecture and next work

PhotoCore remains independent of AppKit/SwiftUI: workspace models, metadata/sort/decision semantics, async service boundaries and actor-isolated SQLite/XMP. PhotoImaging owns ImageIO property/preview reads and a separate Core Image detail lane. PhotoUI supplies native scrolling, focused-window commands and SwiftUI contact sheet/inspector. PhotoApp drains saves on normal termination.

Cache budgets remain 24 MiB thumbnails / 64 MiB fit previews; one full-detail image is limited to 256 MiB decoded bytes. Visible views, transient decoders and OS/GPU allocations are additional. In-progress ImageIO/Core Image work is cooperatively cancellable around synchronous calls, not interrupted mid-call. No speculative RAW rendering or prefetch is implemented.

Next: investigate first-open RAW/decoder latency; broaden Sony camera models and real-EXIF/large-folder native frame measurements; verify Lightroom round trips; add RAW+JPEG pairing and batch organization; evaluate focus/exposure inspection; review accessibility, minimum macOS/Intel and release packaging. License and distribution requirements remain open.

Preserve the user's pre-existing unstaged `native rightmacOS` edit in the development plan. It is unrelated and must not be committed or reverted. Personal test-photo copies and metadata must stay outside Git.

## Change log

- **2026-10-19 — Reliability and large-folder measurements:** added isolated workspace benchmarks, bounded ARW sidecar checks and actor-owned SQLite reuse; fixed external rating order, old-session reads and corrupt-detail errors. Expanded the real-camera test from the first file to every supplied ARW. All nine ILCE-7CR copies and 42 local tests passed; first-open latency and Lightroom exchange remain open.

- **2026-10-19 — Fast culling:** implemented embedded Sony ARW/EXIF (`bb4e9a3`), durable ratings/flags/filtering/XMP (`406637a`), and genuine detail inspection with interaction hardening. Full local checks and reference benchmarks passed; delivery/remote evidence follows below.
- **2026-10-19 — Browser tuning:** prior JPEG/PNG browser merged through [PR #1](https://github.com/kuroiokami/photo/pull/1) as `24b7cff`; [merged-main CI passed](https://github.com/kuroiokami/photo/actions/runs/39268580403). Prior paired performance evidence remains in PERFORMANCE.md.
- **2026-10-19 — Foundation:** SwiftUI/SwiftPM modules, samples, contributor/tracking docs and CI established; historical [initial CI](https://github.com/kuroiokami/photo/actions/runs/39257940587) passed.

### Delivery follow-up

All three implementation chunks are pushed to `origin/codex/fast-culling`. A final fault-injection regression now covers a crash after atomic XMP publication but before SQLite acknowledgement: reopening recognizes matching decisions and completes the acknowledgement without rewriting the sidecar. Modal folder dialogs also disable app decision undo/redo commands. The follow-up passed strict lint, warnings-as-errors build, 26 core tests and 11 UI/imaging tests; the optional real-camera case was skipped after disposable files were removed. Native preview-click → one-step arrow navigation → Fit reset and Space hide/show passed. Remote delivery evidence follows below.

The retained-filter follow-up now waits for decision loading before publishing filtered results and restarts metadata/decision tasks on sample-session changes. A path-to-identity table also prevents an image replacement from automatically inheriting a predecessor's leftover XMP: it presents an explicit image-replaced conflict. Both behaviors have restart/reload regressions; the standard suite passed with 37 executed tests and the optional real-camera case skipped. The paths table is created additively for existing local development databases.

### Remote and final native evidence — 2026-10-19

Implementation commit `371d83d` passed both [push CI](https://github.com/kuroiokami/photo/actions/runs/39276938844) and [PR CI](https://github.com/kuroiokami/photo/actions/runs/39276972124). Prior `fc38508` checks also passed. PR #2 remains a draft and has not been merged. A documentation-only follow-up records these observed results; it does not change tested implementation code.

The final native build confirmed a retained Picks filter survives Reload with the same selected photo/stars, Show Sample Collection reloads sample decisions, Clear Filters restores samples, and sample P/U shortcuts work afterward. The locally signed bundle verifies successfully. Photo is left on samples with Auto-advance off. All disposable photo/synthetic/interchange copies and the isolated Lightroom test catalog were removed after validation. Only the user's original development-plan edit remains unstaged.
