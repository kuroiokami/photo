# Changelog

User-visible changes are collected here before a release. Development evidence and detailed history remain in [PROJECT_STATUS.md](PROJECT_STATUS.md). There is no published stable or notarized release yet.

## Unreleased

### Photo workspace

- Give the preview more space with compact culling controls, a shorter filmstrip and a folder-focused sidebar. Keep stars, flags and image edits directly accessible; move filters and browsing options into named popovers.
- Add Focus on Photo (⇧⌘F) and Hide/Show Filmstrip (⌥⌘T), preserving previous panel choices. Keep source protection, save/recovery status and inspection commands accessible.
- Bound/adapt background model publications and yield between them. Isolate navigator/comparison pane updates and coalesce native callback bursts without changing genuine-pixel scaling or RAW decoding.

### Window recovery

- Restore an existing workspace on a macOS reopen request, including minimized and completely offscreen windows; open a workspace after the last window closes. Add **Window → Show Photo Window (⌘0)** and local reopen events. The reported Dock-icon/no-window symptom is distinct from a confirmed crash.

### Folder browsing

- Add **Include Subfolders** for combined parent-folder review, relative folder labels and separate identities/pairing for repeated filenames. Keep ingest arrivals verified, including when browsing above the destination.
- Extend confirmed Trash cleanup across included subfolders, with relative confirmation names and independent sidecar ownership/inventory safeguards.


### Documentation

- Add local fixed-field lifecycle/resource diagnostics and instructions for unexplained exits. The reported intermittent idle/background disappearance remains under investigation; normal Quit and sleep behavior are unchanged.

- Add a pinned source review of RAWviewer, RawSpeed and Geeqie, with ranked Photo performance experiments and explicit decoder, cache and benchmark limits.

- Add a sourced, code-informed performance research plan covering responsive culling, focus checks, metadata, verified ingest and deadline/large-shoot workflows; distinguish proposals from implemented behavior.

### Performance

- Save group ratings/flags with one queued action and bounded durable transactions, including pre-copy review and grouped Undo/Redo. Recover interrupted XMP acknowledgements together with metadata baselines; preserve external conflicts, source protection and original bytes. Add matched decision-save controls.

- Reuse validated EXIF and embedded XMP per workspace with bounded results and one short-lived ImageIO source. Keep XMP lazy, invalidate changed/replaced files and Reload, and reread sidecars so external edits remain visible. Add synthetic metadata-read controls and source-preservation regressions.

- Buffer small Canon CR3 container reads within 4 KiB and a capped read-ahead budget; skip large sensor payloads and remove temporary integer arrays. Add malformed/sparse/cancellation regressions and a matched CC0-reference benchmark. Warm preview latency remains dominated by JPEG decoding; no new UI-speed claim.

- Keep disk-hit thumbnails independent of cache directory scanning/publication/eviction locks, with bounded recency hints and generation checks. Add matched contention controls and concurrency/sanitizer regressions.

- Prepare the next/previous Fit previews after a short pause, with reserved selected-photo capacity and the existing cache budget. Pause optional reads during file workflows/detail/comparison and on cards or network/ejectable/unknown storage. Add measured settled/rapid navigation controls and native integration checks.

- Load uncached thumbnails on two bounded workers while keeping scheduling/cancellation available. Share duplicate requests, prioritize selected photos and reject obsolete folder work; Fit remains independent. Small JPEG/Sony RAW service controls improve; broader media/frame acceptance remains open.

- Reuse native Contact Sheet cells and stable layout while preserving interactive thumbnail controls and image services. Keep rows steady when adding edits and restore culling-key focus after group drags. Controlled 115/10k scrolling uses less process CPU and shorter potential stalls; physical-trackpad/real-shoot acceptance remains open.

- Add privacy-safe macOS sample analysis and parser tests for scrolling investigations. Record and withdraw a row-layout experiment that did not establish a reliable speedup; rapid grid lag remains open.

- Isolate header/progress, preview and saving-status view dependencies from the contact sheet. Extend read-only profiling to shoots distributed across subfolders.


- Fix selection readiness work growing with the whole loaded folder, and avoid rebuilding unchanged selection snapshots during sorting/focus changes. Add file-backed 10k/40k profiling; native large-folder indexing/scrolling remains an open performance issue.

- Isolate thumbnail display and selection-readiness updates, and reuse mixed-selection summaries. Preserve group decisions, unknown-file gating, filters and Undo; model timing evidence is separate from native frame smoothness.

- Reuse bounded actor-owned SQLite record-query statements and JSON coders while preserving durable saves, recovery and source protection.

- Append durable ordinary-ingest records instead of rewriting growing manifests for every file; retain verified copying, interrupted recovery and rename mappings.

- Simplify unedited thumbnail/Fit rendering, reuse typed image-request identities and EXIF labels, and clip marquee hits to visible thumbnail regions. Add native main-thread trace analysis and a matched scripted comparison; physical-trackpad and representative-library smoothness acceptance remains pending.

- Reuse selection-readiness checks and native filename ranks, batch initial decision indexing, and move optional thumbnail-cache writes onto a bounded background queue. Preserve source-change checks, cache clearing and durable decisions.

- Publish background EXIF/decision results in small groups while keeping selected-photo information immediate; add local performance markers and a concurrent-ingest service scenario.

- Reuse thumbnails with a larger bounded RAM cache, persistent local disk caching and immediate RAM-hit display; add View → Clear Thumbnail Cache.

- Remove cache-order scans from preview hits and eviction; reuse EXIF date parsers/JSON coders and avoid duplicate file identity reads. Add measured evidence and a review of the remaining performance suggestions.

### Licensing

- Offer Photo under MIT or Apache-2.0, at the recipient’s option, with both license texts and updated contribution/distribution guidance.

### Performance

- Avoid rebuilding the workspace for every scrolling thumbnail-position change, and construct thumbnail quick actions only while visible.

### Image controls

- Add thumbnail rotation, mirror, IPTC, crop and Preview quick actions on hover or selection, in Contact Sheet and the Preview filmstrip.

- Show labelled Rotate Left/Right, Mirror and Crop controls in both Contact Sheet and Preview, with visible keyboard hints.

### Culling and cleanup

- Add Z for Fit/100%, [/] for rotation and B/N for photo navigation while zoomed.
- Clarify Review Only Selected / Show All Photos and stabilize normal decision-saving layout.
- Add Select Rejects and confirmed Move Selected to Trash (⌘Delete), with protected-source checks, exclusive sidecars and Finder recovery.
- Move workflow setup into the main window with explicit return-to-photos actions.

### Workflow

- Replace the scrolling ingest form with explicit source, destination, confirmation and progress steps; explain how to start culling and copy picks.

### Documentation

- Simplified the README and contribution/support guides, added a public roadmap, and kept detailed validation in the project tracker.

### Added

- Native macOS 14+ folder browsing, saved Photo Home/subfolders and Preview/contact-sheet layouts.
- Fast embedded Sony/Canon/Olympus RAW previews, asynchronous EXIF, deliberate full-detail inspection and comparison.
- Independent flags/stars, multi-selection, filters, shortcuts and Undo.
- Protected pre-copy culling, explicit copy scopes, dual-destination verification, decision/composition handover and resumable saved copy lists.
- Field-specific IPTC/keywords, preserving XMP synchronization, metadata history, reviewed rename/recovery and delivery copies.
- Photo-local rotate/mirror/crop and a dismissible workflow walkthrough.
- MIT OR Apache-2.0 licensing, contributor/support/security policies, issue/PR templates and repository hygiene/secret checks.

### Current limits

- Composition is saved and transferred inside Photo, not rendered into delivery pixels or exchanged as Lightroom crop settings.
- Signed/notarized downloads, agency upload, broad platform/VoiceOver acceptance and representative 10k/40k measurements remain planned or unverified.
- Reviewed-copy core/model integration is tested; final native copy/resume/restart clicks remain pending after the native automation bridge disconnected. See the tracker for exact evidence.
