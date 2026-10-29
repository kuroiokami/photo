# 0044 — Give the photo the workspace

Date: 2026-10-28

Status: Implemented; actual checks and delivery evidence in the tracker.

## Problem and direction

The preview was surrounded by a collection header, filters/selection tools, a second flag row, image-edit row, preview navigation, Fit controls, another decision block and a tall filmstrip. Sidebar branding, repeated guidance and duplicate workflow buttons displaced folder rows. The user prioritizes fast culling and critical-focus inspection; the photo needs a larger usable viewport.

## Decision

Use a compact collection row and culling row. Keep stars, flags, rotate, mirror, crop and IPTC directly accessible with names/tooltips and keyboard equivalents. Retain two-row fallback when controls cannot fit horizontally. Put filters/selection in a named popover, keep active filter descriptions and one-click Clear Filters visible, and expose Show All Photos during selected-only review. Browsing options hold subfolder scope, pairing, EXIF labels and a real thumbnail-size slider. Moving a setting never changes its scope or file semantics.

Give the folder tree the sidebar: small header/open button, empty-state instructions only when needed, compact Home/help footer and indentation capped to retain room for names. Sidebar remains resizable/collapsible. Do not remove discoverable help; existing Help menu/walkthrough and control tooltips remain.

Use smaller filmstrip thumbnails with direct flag/star controls and filenames. Keep metadata/folder labels when enabled, and use compact pair/edit badges. Six large thumbnail image-action overlays remain in the Contact Sheet; the preview's visible culling bar supplies those actions above its filmstrip. Keep grid and filmstrip size choices independent.

Add **Focus on Photo (Shift-Command-F)**, which temporarily hides collection/culling controls, sidebar, filmstrip and inspector. Keep preview navigation, Fit/100%, exposure/source information, save/recovery status and protected-source copy access. Arrow/B/N navigation, decisions and image-edit keyboard/menu actions remain. Escape first exits Focus; another Escape returns to the contact sheet. Restore the previous sidebar and filmstrip preferences, including an already hidden sidebar/filmstrip. Focus is per window and starts off, rather than restoring a confusing panel-free launch.

Add **Show/Hide Filmstrip (Option-Command-T)** and a preview button, independently of Focus. Space still switches preview/contact sheet; returning to the grid exits Focus. Closing option popovers on entering Focus prevents them reopening when panels return. Popovers have explicit Done/Escape actions and suspend background culling/navigation shortcuts. The preview retains keyboard focus when its filmstrip is absent; an explicit native cancel action exits Focus or returns to the grid, including after navigator/comparison focus changes. Modal crop and picker dismissal take priority. Keep source protection and decision recovery visible; these cannot be permanently dismissed as incidental help.

## Validation and limits

Offscreen hosting tests measure the actual active-photo GeometryReader at normal and compact window sizes, require a useful normal canvas and verify Focus expands it. Tests cover restoring layout choices; native inspection must also check window resizing, both views, popovers, inspection/navigation/comparison, keyboard/group decisions, source workflows and save/error access as practical. Record actual results in the tracker rather than equating layout formulas with measured viewport size. No decoder, cache-budget, image-pixel scaling, original file or persistence change follows from panel sizing.
