# 0018 — Contextual workflow guidance

- Date: 2026-10-20
- Status: Accepted

## Decision

Offer a compact invitation inside Ingest rather than a launch-time modal or a tour overlay on the photo canvas. An optional five-step sheet explains routes and operations with concrete deadline/large-shoot examples. Back/Next/Close and scrollable content let users read at their own pace; no action in the guide executes photo/file operations. Use existing hover help for individual controls.

A shared SwiftUI AppStorage boolean (`Photo.workflow.hideIntroduction`, default false) persists only explicit permanent dismissal. Not Now is panel-session State. Help → Photo Quick Start & Shortcuts and the workflow header always reopen the guide, including when dismissed. The same checkbox can re-enable the introduction. Do not version-reset dismissal and surprise experienced users with another interruption; keep operational source-protection/save/conflict messages independent of help dismissal. No network, photo scan or database work is added to browsing.

The current pre-copy feature is review-only and lacks copy/unprotect. Explain this before entry, and recommend ordinary verified ingest/early-arrival culling for output today. Photo-local composition is separate from exported image processing; captions, backup freshness and editor/submission limits remain explicit. A future working reviewed-copy route must update the walkthrough and guides together.

## Alternatives and validation

Avoid forced first-launch tours (interrupt keyboard culling), hover-only prose (too little space for route examples) and a hidden Help-only manual (poor discovery). This implementation is explanatory, not a resumable operation wizard. Native checks must cover all steps, Close/Escape, Back/Next, transient dismissal, persistent dismissal/relaunch, Help reopen and re-enabling. Record actual outcomes in the tracker; do not claim physical-device or broad accessibility acceptance from compilation.
