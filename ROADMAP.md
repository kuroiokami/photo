# Photo roadmap

Photo focuses on getting photographers from a full memory card to a useful set of keepers, ready for publication or further editing. Fast previews, keyboard culling and reliable file operations guide the work.

This roadmap describes direction, not release dates. Suggestions and contributions are welcome through [GitHub issues](https://github.com/kuroiokami/photo/issues/new/choose).

## Available today

- Folder browsing with saved folders, a contact sheet and a large preview with bottom filmstrip.
- Embedded RAW previews, on-demand detail inspection, comparison and shooting information.
- Stars, pick/reject flags, group decisions, filters and selected-only review.
- Protected review before copying, selective two-destination copying and saved-session recovery.
- Batch renaming, field-specific IPTC edits, presets, hierarchical keywords and metadata Undo.
- Photo-local rotate/mirror/crop and metadata-aware delivery copies.
- An in-app workflow walkthrough, installation instructions and a full user guide.

See the [User guide](docs/USAGE.md) for controls and current limitations. Recognizing a RAW extension does not establish support for every camera or shooting mode.

## Next priorities

### Make the existing workflow easier to trust

Finish native review → copy → resume checks, test interruption with physical removable media, and broaden keyboard, VoiceOver and compact-window checks. Measure representative large shoots and concurrent copying before claiming 10–40k-photo performance. Continue work on first-open and full-detail responsiveness.

### Make Photo easier to install

Add clean, versioned app/DMG packaging, then Developer ID signing, notarization and installation/update checks on a clean Mac. The [distribution plan](docs/DISTRIBUTION.md) tracks the steps. Apple silicon is the current tested development setup; wider macOS and Intel support need verification.

### Improve camera and editor compatibility

Expand real-camera/mode coverage, including Canon CRW. Verify ratings, flags and descriptive metadata through actual Lightroom workflows. Keep a clear distinction between metadata interchange and Photo-local composition edits.

## Further possibilities

Publication-ready image rendering, transferring composition edits, exposure/focus aids, color labels, external-editor integration and richer keyword vocabularies remain future work. Priorities depend on photographer feedback and validation of the core workflow.

## Follow development

The [changelog](CHANGELOG.md) summarizes changes. The [project tracker](PROJECT_STATUS.md), [development plan](docs/DEVELOPMENT_PLAN.md) and [performance notes](docs/PERFORMANCE.md) hold detailed implementation status, acceptance criteria and measurements.
