# 0055: Minhwa magpie native application icon

- Date: 2026-11-02
- Status: Implemented; native/artifact evidence recorded in the tracker

Use an original minhwa-inspired magpie sorting photo prints, generated through the built-in imagegen tool. Keep the selected 1254px RGBA PNG and exact prompt/provenance under [Assets/AppIcon](../../Assets/AppIcon/PROVENANCE.md). No third-party reference art or personal photography is used. The repository image policy permits this exact documented asset, with square/alpha/size/budget guards; generated ICNS containers remain build outputs.

Generate standard 16/32/128/256/512 point representations at 1x and 2x with macOS sips and iconutil. These are format/size derivatives of the preserved master, not a separate creative redraw. Declare `PhotoIcon.icns` through CFBundleIconFile before signing. Record source/ICNS hashes in BuildInfo and verify the actual decoded ten-size matrix, metadata and receipt. The generation/validation caches are bounded build-process caches and never participate in photo decoding or runtime cache budgets.

Both development and committed-source package assembly use this path. Legacy candidates without either icon declaration or icon receipt remain valid, so the already shared icon-less package is still verifiable/upgradable. Any declared icon must be present, valid and match its receipt. This adds no third-party package, photo-library read, persistence migration or signing/notarization change.

Inspect full art and a small derivative, run portable invalid-source and native complete-icon/migration tests, verify the earlier package, and inspect the system-loaded icon in a disposable app. The tracker and review record actual build/source identities and a new local disk image. The public-beta signing/Gatekeeper/platform gates from [ADR 0054](0054-local-app-and-disk-image-packaging.md) remain open.
