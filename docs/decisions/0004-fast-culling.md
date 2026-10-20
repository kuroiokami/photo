# 0004: Fast culling, metadata decisions and detail inspection

- Status: accepted
- Date: 2026-10-19

Prioritize embedded Sony ARW previews, then independent flags/stars stored locally and synchronized to XMP, then on-demand full-detail inspection. ImageIO must not demosaic RAW while browsing. Thumbnail/preview workers retain their existing cost limits and cancellation boundaries. EXIF reads do not request pixels; sort changes publish complete orderings and preserve identity.

Use system SQLite for durable decisions and pending sync, Foundation XML for namespace-aware preservation of unrelated XMP, and Core Image RAW rendering only on explicit detail requests. No external package dependency is needed. Original image bytes are never written. File identities, replacement fingerprints, XMP conflicts and bounded detail memory must have dedicated tests. JPEG/PNG sidecars have limited interoperability. Lightroom interchange must be marked unverified unless tested with Lightroom itself.

Use Lightroom-compatible P/X/U and 0–5 controls, explicit auto-advance, filters and undo. Keep embedded-preview dimensions distinct from sensor dimensions. Full detail uses physical-pixel scaling; do not claim efficient RAW region decoding.

## Validated refinements

The development bundle is sealed with a local ad-hoc signature after wrapping the SwiftPM executable; otherwise native panel services can reject its stale standalone signature. This adds no distribution certificate or sandbox permissions.

Persist durable intent before publishing coordinated atomic XMP. Recover a lost acknowledgement when the sidecar already matches the pending decisions. Track path-to-identity associations as well as identity-keyed decisions so leftover sidecars cannot silently attach predecessor ratings to replacement images. Retained filters wait for decision loading; load tasks are keyed by both folder session and load state, including returning to samples.

Focused-window Navigate commands preserve browsing after preview/control interaction and are disabled during the folder picker. Undo history is per folder session and resets on Reload or a new folder.
