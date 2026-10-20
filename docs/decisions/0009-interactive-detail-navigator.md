# 0009 — Interactive detail navigator

- Date: 2026-10-19
- Status: Accepted

## Context

The overview showed the visible rectangle but could not move it. Users need quick spatial navigation without repeatedly dragging the large image or triggering additional decoding.

## Decision

Map overview pointer positions to the oriented image’s top-left unit square and clamp the center by the visible span. Clicking outside the frame centers the view; grabbing inside preserves the pointer offset. Send uniquely identified navigation requests to the existing AppKit scroller, so repeated identical targets after manual scrolling still apply. Scrolling changes position only: it does not request another detail decode. Retain the same canvas through progressive image replacement and center images smaller than the viewport without changing pixel scale.

Use a bounded aspect-fit overview, white viewport outline, dimmed surroundings and explicit focus ring. Focused menu commands pan a quarter viewport with arrows or a full viewport with Shift; Home/End reach opposite corners. Outside navigator focus, existing photo navigation remains. Supply named accessibility actions and position percentages, with broader assistive-technology testing recorded separately.

## Consequences

The existing native scroll view remains the single owner of visible bounds and physical-pixel scale. No parallel pan model, new image cache or dependency is introduced. Overview coordinates have unit tests; native-scroller tests cover repeated commands and progressive replacement. Full accessibility and compact-window validation remain follow-up work.
