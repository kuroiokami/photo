# Changelog

User-visible changes are collected here before a release. Development evidence and detailed history remain in [PROJECT_STATUS.md](PROJECT_STATUS.md). There is no published stable or notarized release yet.

## Unreleased

### Documentation

- Add a sourced, code-informed performance research plan covering responsive culling, focus checks, metadata, verified ingest and deadline/large-shoot workflows; distinguish proposals from implemented behavior.

### Performance

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
