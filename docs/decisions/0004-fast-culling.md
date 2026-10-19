# 0004: Fast culling, metadata decisions and detail inspection

- Status: accepted
- Date: 2026-10-19

Prioritize embedded Sony ARW previews, then independent flags/stars stored locally and synchronized to XMP, then on-demand full-detail inspection. ImageIO must not demosaic RAW while browsing. Thumbnail/preview workers retain their existing cost limits and cancellation boundaries. EXIF reads do not request pixels; sort changes publish complete orderings and preserve identity.

Use system SQLite for durable decisions and pending sync, Foundation XML for namespace-aware preservation of unrelated XMP, and Core Image RAW rendering only on explicit detail requests. No external package dependency is needed. Original image bytes are never written. File identities, replacement fingerprints, XMP conflicts and bounded detail memory must have dedicated tests. JPEG/PNG sidecars have limited interoperability. Lightroom interchange must be marked unverified unless tested with Lightroom itself.

Use Lightroom-compatible P/X/U and 0–5 controls, explicit auto-advance, filters and undo. Keep embedded-preview dimensions distinct from sensor dimensions. Full detail uses physical-pixel scaling; do not claim efficient RAW region decoding.
