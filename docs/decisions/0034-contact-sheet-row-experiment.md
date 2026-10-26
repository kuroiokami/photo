# 0034 — Contact-sheet row layout experiment

- Date: 2026-10-26
- Status: Proposed experiment; performance acceptance incomplete. Do not treat this as a delivered speed fix.
- Extends ADRs 0028, 0031 and 0033.

## Context

The full Contact Sheet still lags during fast scrolling. Native sampling finds hosting-view layout, lazy-grid track sizing and responder traversal. Tool inspection contributes substantial work, so completed scripted inputs and decoder timings cannot establish photographer-visible smoothness.

## Candidate

Replace only the vertical lazy grid with lazy horizontal rows of explicitly sized tiles. Compute row ranges arithmetically, without chunking/copying the inventory; preserve per-photo identities and observable thumbnail records. Use row identities for offscreen keyboard/reflow reveal and photo identities for the horizontal filmstrip. Keep existing viewport geometry/marquee hit testing, culling controls, image tasks, cache limits, source protection and persistence semantics.

Retain a fixed-field sample analyzer. Sum exclusive tree weights for paths containing each category, counting recursive/branched occurrences once per sample. Validate weights and process/main-thread identity. Samples include waits and cannot be reported as CPU time or frame latency.

## Acceptance

Row mapping and strict checks pass. Broad disposable native controls checks pass in debug, and corrected release scrolling responds at 10k. Two unprofiled release repeats show no consistent overall process-CPU improvement. A matched fixed-position release sample pair, final release regressions and original-context restoration are blocked by the locked Mac. See [the tracker](../../PROJECT_STATUS.md) and [evidence](../PERFORMANCE.md#rapid-full-contact-sheet-experiment--2026-10-26).

Keep the UI candidate unmerged until the comparison supports it. Withdraw it if it adds complexity without a repeatable benefit; use the remaining native evidence to choose the next layout experiment. Physical-trackpad, representative photos, presented frames, memory pressure and 40k acceptance remain separate work.
