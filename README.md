# Photo

A native macOS app for fast folder browsing, culling and organization for publication or an editing workflow. Built with SwiftUI and Swift Package Manager; normal RAW browsing prioritizes embedded JPEG previews.

## Start here

| Guide | What you’ll find |
| --- | --- |
| **[Installation](docs/INSTALLATION.md)** | Requirements, developer tools, clone/build, app installation, updates and troubleshooting |
| **[Complete usage guide](docs/USAGE.md)** | Workspace, selection, stars/flags, trackpad zoom, compare, rotate/mirror/crop, ingest, rename, IPTC and recovery |
| [Copy, cull and deliver workflow](docs/WORKFLOW.md) | Operational sequence, metadata ownership and detailed interchange/recovery limits |
| [Project tracker](PROJECT_STATUS.md) | Implemented/planned/verified status, evidence and current handoff for humans and AI |

## Quick installation

Requires macOS 14+ and Apple Swift 6+ with `swift format`. No external Swift packages or API keys.

```sh
git clone https://github.com/kuroiokami/photo.git
cd photo
sh scripts/build-app.sh --release
open .build/Photo.app
```

Quit Photo before replacing its app bundle. This is a locally ad-hoc signed development build, not a notarized distribution release. See [installation](docs/INSTALLATION.md) for developer-tool setup, an Applications copy and update instructions.

## Main features

- Folder-first JPEG/PNG/Sony/Canon/Olympus browsing, a remembered Photo Home, saved folders and clickable subfolders.
- Large preview above a bottom filmstrip, plus a full contact sheet.
- Independent stars and pick/reject flags, interactive thumbnail controls, batch decisions, filters and Undo.
- Async EXIF indexing, numeric sorting, optional inspector and configurable thumbnail labels.
- Fit, genuine physical-pixel 100%, trackpad magnification, pan/navigator and pinned comparison.
- Selected-only review and RAW+JPEG grouping.
- Non-destructive Photo-local rotate/mirror/crop, crop copy/paste and session Undo.
- Dual-destination verified ingest with automatic verified arrivals, reviewed bulk renaming and recovery.
- Field-specific IPTC patches, presets, hierarchical keywords, persistent metadata batch Undo and preserving XMP synchronization.
- Verified delivery copies with metadata for publication, Lightroom Classic or another editor.

Original image bytes remain untouched. Image edits are currently Photo-local and do not transfer to Lightroom or handoff copies; ratings/flags/descriptions have their separate XMP synchronization. See the [usage boundaries](docs/USAGE.md#14-current-boundaries) and tracker before relying on interoperability. Real CRW, application-level Lightroom round trips and wider platform/accessibility acceptance remain open.

## Development

```sh
swift run Photo
sh scripts/format.sh
sh scripts/check.sh
```

Read [CONTRIBUTING](CONTRIBUTING.md), [AGENTS](AGENTS.md) and [development milestones](docs/DEVELOPMENT_PLAN.md). CI runs the same strict formatting/build/test script. Benchmark commands and measured limits are in [PERFORMANCE](docs/PERFORMANCE.md).

| Module | Responsibility |
| --- | --- |
| PhotoCore | Workspace/metadata/edit models, file enumeration, SQLite, preserving XMP and file operations |
| PhotoImaging | Embedded previews, bounded caches, EXIF, deliberate full-detail RAW rendering |
| PhotoUI | Native workspace, interactive thumbnails, crop editor, gestures, menus and workflow panels |
| PhotoApp | Startup and window lifecycle |

## License and distribution

No license has been selected. Choose one before external distribution or outside contributions. Builds, personal libraries and local catalogs are excluded from Git.
