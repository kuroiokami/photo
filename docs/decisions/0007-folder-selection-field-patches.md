# 0007 — Persistent folder shortcuts and explicit batch field patches

- Date: 2026-10-19
- Status: Accepted

## Context

A folder-first culling app needs reusable locations, direct subfolder browsing and clear group operations without loading an entire directory tree. A batch IPTC edit must preserve each photo's unrelated values.

## Decision

Persist sidebar root paths, disclosure paths and the last folder in UserDefaults. A main-actor observable library asks a separate actor for immediate visible directories on disclosure, skipping packages and symlinks. Missing folders remain listed with recoverable errors until explicitly removed. This is a shortcut library, not a photo catalog or recursive image index. Restoring the selected folder uses the existing asynchronous session-isolated loading pipeline.

Keep focused preview identity separate from the selected set and a stable range anchor. Command/Shift-click, Shift-arrow, viewport rectangle selection and selection commands share the same state. A unique grouped RAW+JPEG representative targets both physical files; all targets must be decision-ready. Native culling menus and buttons use that readiness condition.

Populate descriptive fields from the first selected visible representative. Per-field preview passes exactly one field to the existing preserving metadata patch/store. Typing marks fields for the combined preview; Clear remains explicit and keyword action defaults to Leave. The actual reviewed plan, rather than current controls, determines writes. Applying metadata refreshes values without reopening the folder or losing selection.

Expose hover help and an optional Quick Start sheet. Adopt useful Photo Mechanic shortcut patterns while retaining Lightroom flags and native macOS Minimize. Browser commands do not take over text editing while a workflow sheet is open.

## Alternatives and consequences

A recursive photo view or a catalog would add latency and ownership complexity; explicit child navigation keeps the selected-preview priority intact. Paths are sufficient for shortcuts but do not follow folders moved elsewhere; users can remove/reopen them. There is no live file watching or network-volume monitoring. Rectangle selection has no edge auto-scroll. Photo does not mirror every Photo Mechanic command or metadata field.

Whole-record metadata copying would overwrite unrelated captions/locations. One-field patches are more explicit and reuse existing XMP conflict/preservation protections. Metadata Undo and mixed-value summaries remain future work. Automated checks cover a 50-target field edit, an excluded photo, independent stars, unique captions, unchanged image bytes and retained selection.
