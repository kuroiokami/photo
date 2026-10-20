# Installing Photo on macOS

Photo is a native, folder-first culling app. This guide covers getting the source, building an optimized app, putting it in Applications, updating it, and troubleshooting installation.

**Current delivery:** a local development build. There is no downloadable signed installer, automatic updater, Developer ID signature or notarized release yet. A license has not been selected. See the [tracker](../PROJECT_STATUS.md) for verified platforms and remaining release work.

## Contents

1. [Requirements](#1-requirements)
2. [Install Apple’s developer tools](#2-install-apples-developer-tools)
3. [Download the repository](#3-download-the-repository)
4. [Build and open Photo](#4-build-and-open-photo)
5. [Install a convenient app copy](#5-install-a-convenient-app-copy)
6. [First launch](#6-first-launch)
7. [Update an existing installation](#7-update-an-existing-installation)
8. [Develop and run checks](#8-develop-and-run-checks)
9. [Troubleshooting](#9-troubleshooting)
10. [Local data and uninstalling](#10-local-data-and-uninstalling)

## 1. Requirements

| Requirement | Details |
| --- | --- |
| Operating system | macOS 14 or newer |
| Toolchain | Apple Swift 6 or newer, with `swift format`; matching Xcode or Command Line Tools and macOS SDK |
| Git | Supplied by Apple developer tools |
| Network | Needed to clone/update the repository; normal local browsing needs no account or cloud service |
| Dependencies | No third-party Swift packages, API keys or environment files |
| Images | JPEG (`.jpg` / `.jpeg`), PNG, Sony ARW, Canon CR2/CR3/CRW, Olympus/OM System ORF; extension matching is case-insensitive |

Recognition does not guarantee a preview or RAW decoder for every camera/mode. Real-camera coverage and minimum-platform/Intel acceptance are recorded in the [tracker](../PROJECT_STATUS.md). Fit previews, decoded detail and Apple’s transient RAW/GPU allocations use memory separately. One detail pane retains up to 256 MiB; comparison allows two such panes. Cropping does not reduce the full RAW decoding budget.

## 2. Install Apple’s developer tools

Open **Terminal** and run:

```sh
xcode-select --install
```

Complete Apple’s installation dialog. If Xcode is already installed and selected, its matching toolchain can also build Photo.

Check the selected tools:

```sh
xcode-select -p
xcrun swift --version
xcrun swift format --version
```

Swift must report version 6 or newer, and the formatter command must work. If the tools are missing or too old, update Command Line Tools/Xcode through Apple’s supported installation mechanism. Keep Swift and its SDK from the same installation.

## 3. Download the repository

Choose a parent directory, then clone:

```sh
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/kuroiokami/photo.git
cd photo
```

If you already have the checkout, enter that folder instead. For example:

```sh
cd ~/Projects/photo
```

Confirm you are in the project:

```sh
pwd
git status
ls Package.swift
```

Use `main` for merged work. Preserve any local modifications before changing branches or pulling updates; do not use a hard reset to resolve them.

## 4. Build and open Photo

From the folder containing `Package.swift`:

```sh
sh scripts/build-app.sh --release
open .build/Photo.app
```

The first build takes longer. The helper builds the optimized executable, copies bundled resources, writes the macOS app wrapper and applies a local ad-hoc signature. The output is **`.build/Photo.app`**.

Use the release build when judging responsiveness. For faster development iterations:

```sh
swift run Photo
```

Or build a debug app bundle:

```sh
sh scripts/build-app.sh
open .build/Photo.app
```

Quit an existing Photo instance with **⌘Q** before replacing its bundle. Running a stale copy while rebuilding can make testing confusing.

### Build with Xcode instead

Open `Package.swift` in Xcode, select the **Photo** scheme and run it. No separate `.xcodeproj` is required. The shell helper remains the documented way to create the local Finder-launchable bundle.

## 5. Install a convenient app copy

After building successfully, quit Photo and optionally copy the complete bundle into your own Applications folder. For a first installation where that app copy does not already exist:

```sh
mkdir -p ~/Applications
ditto .build/Photo.app ~/Applications/Photo.app
open ~/Applications/Photo.app
```

If a copy already exists, use Finder to replace the complete app bundle instead of merging into it. You can drag that app to the Dock. Keep track of which copy you launch: rebuilding `.build/Photo.app` does not automatically update `~/Applications/Photo.app`.

The copied app still has a local ad-hoc signature. It is not a notarized distribution build. If macOS refuses to open it, check the build/signature and the system’s stated reason; this guide does not require disabling Gatekeeper or removing security protections.

## 6. First launch

1. Open Photo and choose **Choose Photo Home…** in the sidebar to set your usual photo folder. **Open Folder…** (**⌘O**) adds other locations.
2. Choose a folder on your photo drive or in Pictures; changing Home never moves photos. For a first trial, open a small folder. You can browse the bundled synthetic collection with **Show Sample Collection** before making decisions on real files.
3. In Preview, the large image appears above the filmstrip. Choose **Contact Sheet** for the full grid.
4. Expand a saved folder’s sidebar arrow and click a subfolder to browse it. Removing a shortcut never deletes its files.
5. Read the [usage guide](USAGE.md) for stars/flags, selection, trackpad zoom, editing and metadata. The in-app **Quick Start & Shortcuts** sheet is also available from Help.

macOS may request normal folder/removable-volume access when you choose protected locations. Grant only the access needed for the folders you intend to use. No Photos-library import or Lightroom account connection is required.

## 7. Update an existing installation

Quit Photo. From a checkout without conflicting local work:

```sh
git switch main
git pull --ff-only
sh scripts/build-app.sh --release
open .build/Photo.app
```

If you use the Applications copy, quit it and drag the new `.build/Photo.app` into `~/Applications` in Finder and choose **Replace**. Replace the complete bundle; a folder merge can retain obsolete resources and invalidate its signature. Avoid launching an old Dock copy when verifying a new build.

`--ff-only` refuses to invent a merge when your local branch has diverged. Inspect `git status` and your branches if it fails; keep your changes and resolve the divergence deliberately.

Updating the app does not remove the local database, folder shortcuts, presets or image sidecars. For an important library, include these in your normal backups before updating.

## 8. Develop and run checks

Read [CONTRIBUTING](../CONTRIBUTING.md), [AGENTS](../AGENTS.md) and the [tracker](../PROJECT_STATUS.md) first.

```sh
sh scripts/format.sh
sh scripts/check.sh
```

The check script verifies formatting, builds in Swift 6 language mode with compiler warnings treated as errors, and runs the tests. Ordinary checks need no private photographs. Optional real-RAW tests require `PHOTO_RAW_TEST_FOLDER` pointing to disposable copies; CI skips those tests when it is unset.

For read-only performance measurements, use the commands and interpretation limits in [PERFORMANCE](PERFORMANCE.md). Do not infer release speed from an unoptimized debug run.

## 9. Troubleshooting

| Symptom | What to check |
| --- | --- |
| `Package.swift` cannot be found | Run the command inside the cloned `photo` directory. |
| `swift`, Git or the formatter is missing | Complete developer-tool installation and verify the three toolchain commands above. |
| Swift reports an unsupported tools version | Update/select a compatible Apple toolchain. Photo requires Swift 6+. |
| Native folder panels fail, or the bundle signature is invalid | Quit Photo and rebuild with `scripts/build-app.sh`; the helper seals the complete app after copying resources. |
| An old UI opens after a successful build | Quit other Photo instances and launch the exact `.build/Photo.app` path, or update your Applications copy. |
| The chosen folder looks empty | Check supported extensions, filters, selected review and whether the photos are in a subfolder. Browsing is shallow. |
| A RAW has no Fit preview or fails detail rendering | Recognition is separate from embedded-preview availability and installed macOS camera support. Keep the file, try another supported sample and record camera/mode/macOS details. |
| First RAW access is slower | Decoder initialization and metadata indexing can affect the first request. See recorded performance limits; avoid rebuilding/benchmarking while testing responsiveness. |
| A save says local-only or XMP conflict | Follow [save/recovery instructions](USAGE.md#12-saving-conflicts-and-recovery); reinstalling does not resolve metadata conflicts. |
| A build fails after an update | Save the first meaningful error and toolchain versions. Confirm the supported toolchain and run the required checks before removing generated build output. |

## 10. Local data and uninstalling

| Location | Contents |
| --- | --- |
| `~/Library/Application Support/Photo/decisions.sqlite` | Decisions, descriptive intent, metadata batch history and Photo-local image edits |
| `~/Library/Application Support/Photo/Operations` | Rename/recovery journals |
| App preferences | Folder shortcuts, last folder, auto-advance, EXIF labels, saved presets and naming preferences |
| Beside photos | XMP/ACR companions and ingest/handoff manifests where those operations created them |
| Repository `.build` | Generated executables, app bundle and build products |

Quit Photo before backing up its local data or moving the app. Deleting an app copy does not delete source photos, XMP sidecars or local application data. Removing local data would discard Photo-only edits/history and possibly unsynchronized intent, so it is not a routine troubleshooting step. Keep recovery journals until their operations are resolved.

Continue with the [complete usage guide](USAGE.md).
