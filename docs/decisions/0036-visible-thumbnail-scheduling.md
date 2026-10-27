# 0036: Schedule visible thumbnail demand outside blocking image workers

- Status: Accepted with limited service/native acceptance
- Date: 2026-10-26

## Context

Native cell reuse improves warmed scrolling, but uncached disk reads and ImageIO still serialize inside the thumbnail actor. Cancellation, queue promotion and newly visible demand cannot be serviced while that actor blocks. Large worker counts risk source-card contention and transient decoder memory.

## Decision

Keep actor-owned admission, session/generation state, shared continuations and RAM-cache insertion. Run blocking source stamps, disk reads/record decode and ImageIO in private serial Dispatch workers. Configure two workers for the app thumbnail lane, one for Fit; callers default to one and are clamped to one through four. Full RAW detail remains separate and deliberate. No source read-ahead or new dependency.

Requests share work by URL, size and session UUID. Selected demand precedes ordinary FIFO demand; existing queued jobs can be promoted without restarting. Each caller has an independent cancellation signal/continuation. Last-waiter cancellation drops queued work and signals active work, but an opaque ImageIO call retains its slot until return. Active tokens and load IDs prevent an old completion freeing a newer slot. Explicit cancellation probes work outside Swift task context, including CR3 header reads.

Generation/session/load checks gate cache insertion and deferred disk storage. Retired non-nil session UUIDs are remembered for the pipeline lifetime so a late old request or reset cannot revive its folder; a new browsing session must use a new UUID. This small session-history set grows with folder-session changes, not photo count, and is released with the pipeline. Clear invalidates results even if a decoder ignores cancellation. Cache source-stamp validation, derived-write generation checks and byte budgets remain. Disk reads and source decodes use the same bounded pool; disk accounting-lock contention is not resolved here.

Queues represent live view demand, with cancelled ticket compaction; only active decoder work has a hard numerical bound. There is no claim of a fixed live-request queue cap or time-budgeted main-thread publication. Existing native-cell/SwiftUI task lifecycle defines the requested working set. Group-selected visible tiles receive selected priority. Fit does not wait in the thumbnail queue, although hardware resources remain shared.

## Validation and consequences

Six deterministic gated tests cover concurrency bounds, cancellation that cannot interrupt decode, cancelled queued jobs, independent coalesced waiters, promotion, session/clear/late-request rejection and independent Fit access. Existing image/cache/CR3 tests exercise production workers and explicit cancellation probes. Strict checks pass 207 registered tests, 205 executed and two optional RAW skips.

The release benchmark compares the current scheduler with one/two workers in source order 1/2/2/1 and disk order 2/1/1/2. Synthetic JPEG viewport readiness improves; nine Sony ARWs also complete with two workers, with initialization/order caveats. Native isolated-app cold JPEG, reverse scrolling, decisions/Undo, Fit/100% and source-switch checks pass. Originals are hash-verified. See [performance evidence](../PERFORMANCE.md#visible-demand-thumbnail-scheduling--2026-10-26).

Nearby Fit preparation, explicit UI publication deadlines, physical media, mixed cameras, concurrent verified ingest, pressure and physical-input/frame evidence remain separate work. Two decoders can retain more transient memory than one; cache accounting is not total RSS. Do not infer competitor parity or presented-frame improvements from this service experiment.
