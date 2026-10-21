# 0024 — Keep scroll geometry out of workspace state

- Date: 2026-10-21
- Status: Implemented; native functional checks complete, broader performance/device acceptance open

## Context

A 115-JPEG Contact Sheet was reported slow. Every visible tile publishes viewport-relative geometry for marquee selection. Updating the workspace's state dictionary for every scrolling position also invalidates the workspace view. Hover actions introduced additional invisible button/menu layout. A short native CPU sample included lazy-grid sizing/layout and geometry preference reduction, supporting investigation of this path; it is not a full performance benchmark.

## Decision

Hold transient viewport frames in a stable, main-actor, non-observable reference. Replace the frame snapshot when preferences change, without publishing UI state. Marquee events read that snapshot and still publish actual selection/drag changes. Retain viewport clipping and clear frames on folder/session and layout-mode changes. Test replacement, clipping and reverse-direction drag behavior.

Construct quick actions only when the tile is hovered or selected. Keep hover state local to the tile. Preserve thumbnail selection/decision semantics, visible fallback controls and all decoder/cache limits. Do not increase background decoding or memory budgets to address a UI-layout issue.

## Acceptance

Strict checks and release packaging pass; see the tracker. After unlock, native same-folder traversal/return scrolling, eventual thumbnail completion, marquee and selected-tile controls passed; the original browsing context was restored. Cold/evicted thumbnail loads and physical trackpad/hover-only and broad platform coverage remain distinct acceptance work. No frame-time, FPS or large-collection improvement is claimed until measured. Keep raw process traces and private collection details outside Git.
