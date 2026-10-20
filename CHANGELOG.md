# Changelog

User-visible changes are collected here before a release. Development evidence and detailed history remain in [PROJECT_STATUS.md](PROJECT_STATUS.md). There is no published stable or notarized release yet.

## Unreleased

### Documentation

- Simplified the README and contribution/support guides, added a public roadmap, and kept detailed validation in the project tracker.

### Added

- Native macOS 14+ folder browsing, saved Photo Home/subfolders and Preview/contact-sheet layouts.
- Fast embedded Sony/Canon/Olympus RAW previews, asynchronous EXIF, deliberate full-detail inspection and comparison.
- Independent flags/stars, multi-selection, filters, shortcuts and Undo.
- Protected pre-copy culling, explicit copy scopes, dual-destination verification, decision/composition handover and resumable saved copy lists.
- Field-specific IPTC/keywords, preserving XMP synchronization, metadata history, reviewed rename/recovery and delivery copies.
- Photo-local rotate/mirror/crop and a dismissible workflow walkthrough.
- Apache-2.0 licensing, contributor/support/security policies, issue/PR templates and repository hygiene/secret checks.

### Current limits

- Composition is saved and transferred inside Photo, not rendered into delivery pixels or exchanged as Lightroom crop settings.
- Signed/notarized downloads, agency upload, broad platform/VoiceOver acceptance and representative 10k/40k measurements remain planned or unverified.
- Reviewed-copy core/model integration is tested; final native copy/resume/restart clicks remain pending after the native automation bridge disconnected. See the tracker for exact evidence.
