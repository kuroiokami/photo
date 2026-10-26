# 0034 — Contact-sheet row layout experiment

- Date: 2026-10-26
- Status: Rejected UI prototype; diagnostic tooling retained.
- Extends ADRs 0028, 0031 and 0033.

## Context

The full Contact Sheet still lags during fast scrolling. Native sampling finds hosting-view layout, lazy-grid track sizing and responder traversal. Tool inspection contributes substantial work, so completed scripted inputs and decoder timings cannot establish photographer-visible smoothness.

## Evaluated candidate

Replace only the vertical lazy grid with lazy horizontal rows of explicitly sized tiles. Compute row ranges arithmetically, without chunking/copying the inventory; preserve per-photo identities and observable thumbnail records. Use row identities for offscreen keyboard/reflow reveal and photo identities for the horizontal filmstrip. Keep existing viewport geometry/marquee hit testing, culling controls, image tasks, cache limits, source protection and persistence semantics.

Retain a fixed-field sample analyzer. Sum exclusive tree weights for paths containing each category, counting recursive/branched occurrences once per sample. Validate weights and process/main-thread identity. Samples include waits and cannot be reported as CPU time or frame latency.

## Outcome

The prototype passed row-mapping and broad functional checks but showed no reliable overall process-CPU improvement in repeated release scroll sequences. Fixed-position candidate captures remained unusable because of lock/window-resolution interruptions; they cannot support a speedup claim. Withdraw the row implementation and its dedicated tests rather than add layout complexity without evidence. The final application code matches the existing grid.

Retain the sample analyzer, parser/privacy tests and anonymous findings. Source images are unchanged and the original sample view/settings/sidebar are restored. See [the tracker](../../PROJECT_STATUS.md) and [evidence](../PERFORMANCE.md#rapid-full-contact-sheet-experiment--2026-10-26).

Rapid full-contact-sheet lag remains open. The next experiment should evaluate a bounded native collection view, preserving current controls, selection, keyboard/marquee behavior, accessibility, preview/cache policies and original-byte guarantees. Require usable frame/hitch and representative-library evidence before accepting it. This decision does not authorize treating diagnostic sample counts as photographer-visible speed.
