# 0010 — Preview above a horizontal filmstrip

- Date: 2026-10-20
- Status: Accepted

## Context

Side-by-side contact sheet and preview divide the image’s width. Fast culling benefits from a dominant preview and adjacent frames in a compact strip, with a full grid available for organizing groups.

## Decision

Use Preview as a large upper image and a single-row LazyHStack below it. Contact Sheet uses the existing lazy vertical grid. An explicit segmented view control, Space, Escape and thumbnail double-click share the same mode state. Keep the workspace identity/selection, filters, ordering, batch decisions and image workers shared. Each view keeps its own thumbnail size in the current session. A one-row filmstrip uses one-photo vertical keyboard steps as well as left/right navigation.

Place filename/navigation above the image and compact decisions/exposure below. Show optional shooting information in a separate scrollable right pane. Empty, filtered and failed collections use the whole browsing area so recovery actions remain visible. Reveal the focused thumbnail when identity or ordered index changes, and after size/mode reflow. Keep viewport rectangle selection and native horizontal scrolling; edge auto-scroll remains future work.

## Consequences

No new decoding, speculative RAW work, persistence schema, dependency or cache budget is introduced. Changing view removes the detail view and resets to Fit, releasing detail ownership. Filmstrip sizing uses a bounded separate control rather than a freely dragged divider; persistent layout preferences remain future work. Two-photo comparison and selected-only review are proposals, not part of this layout change.
