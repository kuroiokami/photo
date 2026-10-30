# 0050: Crop locks, adaptive thumbnails and temporary Quick Preview

Date: 2026-10-30
Status: Implemented; limited native acceptance and controlled developer experiments

## Context

Crop presets previously seeded a rectangle, then all gestures and dimensions were free-form. Contact-sheet/filmstrip cells requested 480 pixels even when much smaller. A quick large view should preserve the photographer's current layout and keep embedded previews separate from genuine RAW detail. LibRaw/RawTherapee/darktable research offers useful policies but does not justify replacing the decoder or copying GPL implementation code.

## Decision

Keep crop proportions as editor-local state: Free, Original and common ratios with reciprocal portrait/landscape titles. Constrain drawing, corner dragging and numeric dimensions in oriented original-image pixel proportions, preserve opposite corners/center where appropriate, and clamp within the existing normalized one-percent crop model. Moves preserve size. Unsupported extreme ratios explain the limit instead of drifting. Save existing crop geometry and use existing Undo/persistence; ratio choice is not a new persisted schema.

Choose stable 160/240/320/480 thumbnail classes from point size and display scale, within existing 480-pixel/RAM limits. Probe only those classes in the same session: adequate larger images can satisfy a request; smaller images are temporary stand-ins. Tag displayed pixels/errors by file, pipeline, session and generation so cell reuse cannot flash a different photo. Keep selected priority, cancellation, source validation, worker bounds and Fit/detail separation.

Use a window-local AppKit key monitor for hold W, so native collection cells and SwiftUI share the behavior. Release, Escape, lost key-window focus and teardown clear temporary state. Text editing, modified shortcuts, attached sheets, menus, unavailable sessions and other windows retain their input. A View-menu preview can remain open until Close/Escape. An overlay preserves browsing layout; Z/Inspect at 100% dismisses it and deliberately requests the existing genuine detail path.

Keep PNG production disk records. Experimental JPEG quality 0.90 is opt-in, uses distinct versioned keys/type validation and falls back to PNG for alpha/high-depth/non-RGB inputs. Legacy PNG reads remain compatible. Keep LibRaw in a standalone API probe outside SwiftPM; no runtime library, GPL source copy or original-image write is added.

## Evidence and remaining work

Geometry, Retina classes, fixed-probe cache/session/clear/budget behavior, source identity, codec/alpha/Display P3/high-depth/grayscale and window-local hold/text/modifier/teardown regressions supplement the existing suite. Native disposable checks exercise ratio drag/numeric edits, swap, explicit Free, Apply/Undo, Quick Preview menu/Escape/genuine-detail transition, thumbnail resizing, scrolling and endpoint Fit. The source hashes remain unchanged. Physical hold/gesture frame timing, broad VoiceOver/cameras/displays, pressure and long sessions remain open.

[Codec controls](../benchmarks/2026-10-30-thumbnail-strategies.json) show fourfold fewer decoded bytes at 240 versus 480, but JPEG changes high-contrast pixels; no production codec switch. The [RAW review](../RAW_BACKEND_REVIEW.md) records separate extraction/decode/unpack/render, requested cancellation, memory and active-area/quality limits. Larger camera JPEG/metadata integration remains a later decision; the pilot does not replace true 100% RAW inspection.
