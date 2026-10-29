# 0047 — Prepared visibility, collection ordering and reusable indexes

Date: 2026-10-29

Status: Implemented; local regressions and matched service controls pass. Native validation is pending Mac unlock; delivery evidence belongs in the tracker/PR.

## Evidence and membership

Separate accepted-release stack sampling places collection work in `matches`, `visiblePhotos`, `makeIndex`, selection intersection and sort publication. The comparator already runs off-main, but membership/index preparation returns to the main actor. Raw samples remain outside Git; sample counts include waits and are not CPU milliseconds or displayed frames.

Use an immutable Sendable visibility value containing relevant grouping, review, flag/star, loading, decision and readiness inputs. Bulk evaluation reads it once rather than repeatedly entering workspace Observation accessors. Unrestricted views reuse the candidate array. Decision-filtered views remain empty during decision indexing and exclude unknown records afterward. Grouped representatives and companion-only review membership retain their existing rules. Single-photo decision advancement uses the same membership predicate.

## Prepared sorts and stale-result rejection

Prepare numeric/rating order, visible membership and aligned full/visible indexes on a detached worker. Build the rating dictionary there; unrelated sorts do not create it or retain irrelevant metadata/decision maps. Transfer the prepared values in one main-actor publication, preserving current selection by identity.

Guard results by session, inventory revision, requested sort and monotonic request generation, visibility scope, loading state and relevant decision/metadata revisions. Retry the latest inputs when still the current request; older same-sort requests cannot overtake or restart newer ones. Rating order at decision-index completion uses this lane too. One worker is tracked; replacement, session reset and parent cancellation cancel it. Checks between phases reject cancelled results. An opaque standard-library sort cannot be preempted midway, so brief overlap remains possible. Release worker snapshots after completion; no new persistence/termination barrier is needed for in-memory ordering.

## Reusable indexes and immediate actions

Keep a full-order ID/index map aligned with `allPhotos`; every array mutation invalidates it. Inventory loading and prepared sorting supply already-built maps. An unrestricted rebuild/cleared filter can reuse the map; filtered subsets build their own aligned map. Intersect selection by walking selected IDs against that map, avoiding a Set of every visible ID. Selection/filter/flag/history actions retain their synchronous membership behavior, fallbacks and auto-advance rules.

One full map may be retained alongside a filtered map. This trades model memory for less repeated hashing; it does not raise image-cache budgets or promise lower RSS. Immediate bulk rating/Undo resorting, initial locale rank computation and large selection summaries remain separate costs.

## Validation

Eight new deterministic tests exercise filter changes during preparation, same-sort overtaking without obsolete retries, late metadata, cancellation/lane reuse, session replacement, decision-index rating completion, cache invalidation by rating/Undo, and companion-only grouped review. Existing arrivals/removal/filter/auto-advance/source protection/history tests pass. Internal gates are test-only injection, not a user API.

Quiet Unicode/ASCII 10k ABBA controls retain complete anonymous reports, errors, hashes, memory, first preview/readiness and suspension. See PERFORMANCE.md. Native controls and app-attributed physical frame evidence remain pending unlock; model timings are not FPS or broad camera/media/40k/pressure acceptance.
