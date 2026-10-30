# 0048 — Explicit workspace image-session ownership

Date: 2026-10-30

Status: Implemented; deterministic scheduling and strict local checks pass; scoped native restoration acceptance passes.

## Failure and decision

A request previously adopted any unseen non-retired session. During automatic folder restoration, sample-view tasks can first reach the thumbnail actor after the restored folder has started. That unseen old session retires the current UUID; further current requests cancel and their mounted image tasks do not retry. Retired-ID checks alone cannot reject an unseen old request. Reload creates a fresh UUID and hides the failure.

Once `startSession` explicitly establishes workspace ownership, image requests must match its active session and cannot change it. Standalone pipeline clients that never call `startSession` retain implicit session adoption. Cancelled resets remain no-ops; retired explicit resets remain rejected, and active decoder slots are held until opaque work returns.

The workspace mounts its preview/contact-sheet image subtree only after both thumbnail and Fit actors have started the current session. A cancellation/session guard prevents an obsolete setup from publishing readiness. Headers/sidebar remain available during this brief setup; display the normal opening indicator until ready. Existing workers, priorities, cache budgets/stamp validation, original bytes, detail inspection and decision persistence are unchanged.

## Evidence and limits

The new gated regression fails on the accepted code with four issues: unseen UUID/nil requests are admitted, the current cached image is lost and current navigation throws cancellation. It passes after the fix, verifies no stale decode is admitted and verifies continued current-folder navigation. All seven scheduling regressions pass, including bounded concurrency, coalescing, clear, retired sessions and uninterruptible decoder completion. Strict local checks register 275 tests, execute 273 and skip two optional RAW cases. Native restoration results and exact CI/delivery evidence belong in the tracker/PR. This is a lifecycle correctness fix, not a measured decode/FPS gain.

Native isolated release `A5A0E9D5-0F2F-3FDC-A082-710DAA6A6FB0` passes three verified fresh-process automatic restorations of a generated 10k Unicode JPEG collection without Reload. Each shows loaded Fit and filmstrip images during indexing. Full Contact Sheet End loads/selects the last thumbnail; Home/Space returns to loaded Fit. Temporary shortcut removed, sample image restored, only the isolated app quit and all 10k source aggregate hashes match across the remaining restoration checks. Native automation initially returns unusually slowly; tool durations are not app latency/FPS evidence. Broader camera/media/sleep-wake acceptance remains open.
