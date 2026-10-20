# 0014 — Interactive contact sheets and non-destructive image composition

- Date: 2026-10-20
- Status: Accepted for the first rotate/mirror/crop chunk

## Context

The user requested interactive thumbnail stars/flags, trackpad zoom wherever zoom is available, complete installation/usage guides, and an audit of Photo Mechanic’s basic editing functions. The user explicitly prioritized rotate/mirror and crop before color classes or external-editor launching. Original-byte preservation and fast embedded RAW browsing remain primary constraints.

## Decision

Separate thumbnail selection buttons from decision controls. A direct decision on a selected tile targets the selection; an unselected tile becomes the target first. Suppress auto-advance for direct tile actions, retain existing filter-neighbor behavior, and expose explicit 0–5/flag context commands. Image/filename buttons retain modifier selection and image double-click Preview.

Represent composition as quarter-turn rotation, reflection and a normalized rectangle relative to the EXIF-oriented original. Rotating/mirroring transforms the crop too. Persist edits by existing volume/file identity plus replacement fingerprint in a separate SQLite table. Batch writes preflight every identity and commit in one transaction, using the existing save queue/normal-quit barrier. Optimistic saving has a visible status and Retry Image Edit Save. Session Undo/Redo interleaves decisions and image edits; Reload/new folder clears history while durable values remain.

For this first chunk, image edits are **Photo-local**. Do not claim Adobe crop/orientation exchange or bake edits into handoff copies. Existing XMP/develop settings remain untouched. Writing Adobe develop fields would require an explicit ownership/conflict model, crop-coordinate/orientation interoperability tests and derived-output validation. Local composition provides working editing without silently replacing Lightroom settings. The UI, guides and tracker state this boundary.

Paint the same affine transform/crop in thumbnail/Fit images, full detail, progressive regions and navigator. Draw CGImage directly in top-left coordinates; avoid allocating an additional full-size edited bitmap. Detail canvas dimensions are edited pixels divided by backing scale and multiplied by magnification. Inverse-map inspection focus into original coordinates; source pixels remain available to the detail worker. A crop does not bypass full-image decoding or its memory limit.

Fit pinch uses SwiftUI magnification; native detail magnify events adjust a bounded 5–800% scale without decoding again. Two-finger scrolling remains pan. Preserve the active pinch anchor, route actual resulting normalized centers/scale to linked comparison, and keep explicit Fit and exact 100% controls. Pinching the grid/filmstrip changes thumbnail density within existing limits. Physical trackpad input remains a distinct native acceptance check when automation cannot generate pinch gestures.

## Consequences and remaining work

Image edits survive restart/rename when the protected file identity still matches. They do not follow a new copied image or replace externally changed originals. They require the local database in backups. Crop ratios seed a centered rectangle; locked-ratio drag, arbitrary straightening, external crop import/XMP synchronization and applied export remain future work. Per-file image edits are separate from descriptive metadata history. Existing decoder/cache/detail budgets and demand-only rendering remain in force.

See [usage](../USAGE.md), [the Photo Mechanic audit](../PHOTO_MECHANIC_REVIEW.md) and the tracker for actual validation.
