# Photo

**Fast photo culling and organization for macOS.**

[![Swift checks](https://github.com/kuroiokami/photo/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/kuroiokami/photo/actions/workflows/ci.yml)
[![Repository checks](https://github.com/kuroiokami/photo/actions/workflows/repository.yml/badge.svg?branch=main)](https://github.com/kuroiokami/photo/actions/workflows/repository.yml)

[Get started](docs/INSTALLATION.md) · [User guide](docs/USAGE.md) · [Roadmap](ROADMAP.md) · [Contribute](CONTRIBUTING.md)

Photo helps you get from a card full of images to a set of keepers. Browse folders, review RAW previews, flag your picks, add captions and keywords, and prepare photos for publication or your favorite editor.

Built for photographers working to a deadline and photographers sorting through a large shoot. Start reviewing before copying, or begin culling as verified copies arrive. Lightroom is optional. Group ratings and flags save in the background; normal Quit waits for pending saves.

Photo is open source and in active development. You can build it from source today; a signed installer is still on the [roadmap](ROADMAP.md).

Bring back a hidden, minimized or closed workspace with **Window → Show Photo Window (⌘0)** or by clicking Photo in the Dock.

## What you can do

| Feature | What it does |
| --- | --- |
| **Browse without importing** | Open a folder or memory card. Explore the sidebar tree or turn on **Include Subfolders** to review a whole shoot together. |
| **Revisit photos quickly** | Reuse thumbnails from bounded memory and disk caches; load new thumbnails with a small worker pool, save disk thumbnails in the background and clear them from the View menu when needed. |
| **Find the keepers** | Use keyboard shortcuts, stars, pick/reject flags, filters and group selection. Work in a contact sheet or a large preview with a bottom filmstrip. Review selected rejects and move them to macOS Trash. |
| **Check the details** | Prepare nearby Fit previews while you pause, zoom to 100%, pan with the navigator, compare photos side by side, and see shooting information. RAW browsing uses embedded previews; full RAW rendering happens when you request detail. |
| **Review before copying** | Make culling decisions locally while Photo keeps the source protected. Choose which photos to copy, verify both destinations, and carry your decisions to the working copies. |
| **Organize a shoot** | Rename batches, add shared IPTC fields without replacing unrelated metadata, and apply captions, copyright and hierarchical keywords. |
| **Prepare the next step** | Create delivery copies with metadata for publication, Lightroom Classic or another editor. Rotate, mirror and crop within Photo for review. |

JPEG (`.jpg` and `.jpeg`), PNG, Sony ARW, Canon CR2/CR3/CRW and Olympus/OM System ORF are recognized, including uppercase extensions. RAW preview and detail availability depend on the camera, file and installed macOS decoder. See [camera coverage and performance](docs/PERFORMANCE.md).

## Build and run

You need **macOS 14 or later** and **Apple Swift 6 or later**, including `swift format`. No third-party Swift packages or API keys are required.

```sh
git clone https://github.com/kuroiokami/photo.git
cd photo
sh scripts/build-app.sh --release
open .build/Photo.app
```

The [installation guide](docs/INSTALLATION.md) walks through installing Apple's developer tools, copying Photo to Applications, updates and troubleshooting. Quit Photo before replacing its app bundle. Local builds are ad-hoc signed; a Developer ID-signed, notarized download is not available yet.

## Your first culling session

1. Open a working folder with **⌘O**. To review a memory card before copying, choose **Workflow → Ingest → Choose keepers before copying → Start Culling**. Turn on **Include Subfolders** to combine the card’s folders, or expand the sidebar and choose one subfolder.
2. Move through photos with the arrow keys. Press **P** to pick, **X** to reject, **U** to clear a flag, and **0–5** to rate. Rejecting never deletes a photo.
3. Use **⇧⌘F** for Focus on Photo and **⌥⌘T** to hide the filmstrip. Press **Z** to switch between Fit and 100% for focus inspection; **[ / ]** rotate, and **B / N** always browse previous/next photos. Compare similar frames, then filter down to your keepers.
4. Copy reviewed photos to your Photo and Backup folders, or continue organizing existing working copies. Add metadata, rename, and prepare delivery copies when ready.

The app includes a walkthrough under **Help → Photo Quick Start & Shortcuts**. You can dismiss the introduction permanently and reopen the walkthrough whenever you need it.

## Documentation

- [Installation](docs/INSTALLATION.md) — build, install, update and troubleshoot.
- [User guide](docs/USAGE.md) — controls, selection, previews, culling and metadata.
- [Copy, cull and deliver](docs/WORKFLOW.md) — choose a workflow and understand recovery.
- [Review before copying](docs/PRE_COPY_CULLING.md) — source protection, copy choices and saved sessions.
- [Roadmap](ROADMAP.md) — what works today and what's next.
- [Changelog](CHANGELOG.md) — changes as the project develops.

### Current limitations

Photo keeps original image bytes unchanged. Explicit **Move to Trash** removes selected working files and exclusive sidecars from their folder; Finder can restore them. Protected pre-copy sources cannot be trashed. Rotate, mirror and crop edits currently stay within Photo; they are not applied to delivery copies or transferred to Lightroom. Ratings, flags and descriptive metadata use a separate XMP workflow.

Large-shoot performance is still being tuned. Prepared photo identities and indexing storage reduce selection/publication costs in separate Unicode/ASCII 10k controls; [measurements and limits](docs/PERFORMANCE.md#prepared-identities-and-indexing-capacity--2026-10-29) distinguish these model timings from displayed frames. The reusable full Contact Sheet grid reduces process CPU and potential-stall duration in controlled 115-photo and synthetic 10k scrolling checks. Those scripted results do not establish physical-trackpad smoothness, competitor parity or representative RAW/40k performance. See the [measurements and remaining limits](docs/PERFORMANCE.md#native-reusable-contact-sheet--2026-10-26).

The earlier running-icon/no-window report now has explicit [window recovery](docs/INSTALLATION.md#photo-is-running-but-no-window-appears). Local diagnostics remain available if it recurs.

Lightroom application-level round trips, real Canon CRW files and broader camera/platform coverage still need testing. See the [current boundaries](docs/USAGE.md#14-current-boundaries) and [project tracker](PROJECT_STATUS.md) for details. Source protection covers operations inside Photo.

## Contributing

Bug reports, documentation improvements, workflow feedback and code contributions are welcome. Start with [Contributing](CONTRIBUTING.md), or [open an issue](https://github.com/kuroiokami/photo/issues/new/choose) to describe a problem or idea. Please follow our [Code of Conduct](CODE_OF_CONDUCT.md).

For local development:

```sh
swift run Photo
sh scripts/format.sh
sh scripts/check.sh
python3 scripts/check-repository.py
```

The app uses SwiftUI and Swift Package Manager. PhotoCore contains models, metadata, storage and file operations; PhotoImaging handles previews and RAW detail; PhotoUI provides the workspace; PhotoApp manages startup and windows. See the [development plan](docs/DEVELOPMENT_PLAN.md), [architecture decisions](docs/decisions/0004-fast-culling.md) and [repository conventions](docs/REPOSITORY_STANDARDS.md) for more.

## Help and security

See [Getting help](SUPPORT.md) for questions and bug reports. Please report security issues through [private vulnerability reporting](SECURITY.md).

## License

Photo is dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option. See [NOTICE](NOTICE) for attribution. Photo is an independent project; references to other photography apps describe workflows or interoperability.
