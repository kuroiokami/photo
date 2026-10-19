# 0002: Read-only folder browsing and contact sheet

- Status: accepted
- Date: 2026-10-19

## Context

The user authorized real-folder browsing for JPEG/PNG and requested a UI informed by Photo Mechanic. The approved slice includes a native folder picker, thumbnails and selected preview, asynchronous loading, bounded caching, cancellation on folder changes, recoverable errors, and protection of originals.

## Decision

Use a native NSOpenPanel and per-window File menu actions. Enumerate only immediate, visible, regular JPEG/PNG files; exclude symlinks and folders. Sort naturally by filename. Enumeration is read-only and actor-isolated away from the main actor. A monotonically replaced UUID identifies each folder session; cancel old requests and reject late results even when a provider ignores cancellation. Reload rescans and preserves selection when possible; watching external changes is deferred.

Add PhotoImaging as an ImageIO adapter module. Generalize the unused preview protocol to an associated Sendable result instead of requiring re-encoded image Data. Return immutable CGImage-backed results and original, orientation-adjusted dimensions. A documented unchecked Sendable wrapper shares only immutable images. No external consumers or persisted schemas need migration.

Use two serial decode actors, one for thumbnails and one for previews, so at most one decode per lane runs at once and preview work does not wait behind scrolling thumbnails. Decode to a maximum edge of 480/2560 pixels respectively, apply EXIF orientation, and cache by URL and requested size. Use least-recently-used decoded-cost budgets of 24 MiB for thumbnails and 64 MiB for previews; do not cache oversized results or failures. Replace the pipelines on folder changes/reload. Cancel view tasks on disappearance, release their images, and check cancellation before and after ImageIO work. In-progress filesystem and ImageIO calls cannot be interrupted mid-call.

Use a lazy contact sheet with filename labels, visible selection outline, density slider, resizable preview pane, and selection-following scroll. Arrow keys navigate in the focused grid, Space shows/hides preview, Escape hides it, and Home/End jump to the ends. Keep the split pane's identity stable across folder changes; explicitly restore grid focus after loading and picker cancellation. No rating/filter controls are shown until those behaviors exist.

## Alternatives and consequences

Loading full-resolution NSImages on the main actor would risk stalls and large memory use. A single decode queue could delay previews behind thumbnails. Eagerly creating a view and decoded image for every file would make large folders unnecessarily expensive.

SwiftUI LazyVGrid supplies lazy creation, not a guaranteed collection-view reuse pool. Visible views and transient ImageIO allocations sit outside the cache budgets. Separate real-camera benchmarks are required before claiming numerical responsiveness or total memory targets. Metadata reading beyond dimensions, security-scoped bookmark persistence, sandboxed release packaging, and 1:1 zoom remain later work.

A build helper wraps the SwiftPM executable and resource bundle in an unsigned local `.app` for native UI testing. It is not a distribution installer or signed/notarized release.

## Validation

Test natural sorting and format/hidden/symlink filtering, empty/missing folders, selection restoration, late folder results, return-to-samples cancellation, PNG and EXIF-rotated JPEG downsampling, source-byte preservation, corrupt/missing/unreadable file failures, retry after permission restoration, cancellation, and cache budgets. Render both empty and sample workspaces. Inspect the native app with disposable synthetic folders; keep the current observed results in PROJECT_STATUS.md.

## UI references

Camera Bits' documented contact-sheet screenshots and interaction guidance informed the grid, filename labels, thumbnail slider, and keyboard-driven browsing. No product assets or proprietary code were copied.

- [Contact Sheets: An Overview (legacy Photo Mechanic 6)](https://docs.camerabits.com/support/solutions/articles/48001252561-contact-sheets-an-overview)
- [The Preview Window](https://camerabits.freshdesk.com/support/solutions/articles/48001144384-the-preview-window)
