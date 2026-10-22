# 0030 — Actor-owned SQLite statement leases

- Date: 2026-10-21
- Status: Implemented; local acceptance passed, exact-head delivery evidence belongs in the PR
- Refines ADRs 0004, 0019 and 0027. Database schema, payload format and transaction/durability policy remain.

## Context

Decision/path, descriptive metadata, image-edit, source-review, copy-receipt and metadata-history queries prepared and finalized the same SQL on every operation. Source-review and several related record paths also constructed default JSON coders per item. This creates repeated allocation/compilation work independently of the separate cost of durable commits and filesystem/sidecar checks.

## Decision

Keep one connection wrapper owned by each DecisionStore actor. Cache at most 32 SQL strings/statements per connection. A synchronous nonescaping lease supplies the database/statement only while the actor executes the query; no lease crosses an await. A nested request for already-leased SQL receives a temporary statement, and cache overflow also uses a temporary statement. Both are finalized at lease end. Cached statements finalize before the connection closes. No connection pool or concurrency-policy change.

Reset execution and clear all parameter bindings on success or failure. Capture/propagate body errors before cleanup; reset can report the previous failing step while resetting the execution state. After a successful body, check reset/clear return codes before returning success, since reset can reveal a late SQLite error. Retain prepare_v2 automatic schema recompilation; failed preparation is never cached. Existing row/blob data is copied before the lease ends. Do not cache transaction commands or interpolate new user data into SQL.

Use the existing actor-owned default JSONEncoder/JSONDecoder for decision, metadata, source-review, image-edit, receipt and history records. Their configuration and stored encodings stay the same. Do not batch user decision commits or change pending-intent/XMP acknowledgement order as part of this optimization.

## Validation and limits

Regressions cover reset/cleared bindings, throwing bodies, nested identical SQL, bounded cache/temporary finalization, rollback/schema changes, failed prepare, connection destruction, persisted decision/path reads after reopening, independent Unicode source-review sessions and recovery after malformed JSON. Existing pending-save, conflict, interrupted-copy, metadata Undo, automatic-rollback and source-preservation suites remain required.

`sh scripts/benchmark.sh --sqlite-statements` measures public ordinary image-state and protected source-review APIs over fresh disposable databases: 1,000 marker files per workflow, cold discovery and 10,000 warm reads. Generation/final source checks are outside timing; normal file-identity/protection checks and cold-write durability remain inside. An unchanged-main baseline receives only the identical benchmark harness. Report actual values, including neutral/regressed results. No native UI frame-time, RAW decoding, physical-media or bulk-save batching claim follows.

## SQLite references

- [reset](https://www.sqlite.org/c3ref/reset.html): resets execution, retains bindings and can return a previous or late execution error.
- [clear_bindings](https://www.sqlite.org/c3ref/clear_bindings.html): clears parameter values separately from reset.
- [prepare_v2](https://www.sqlite.org/c3ref/prepare.html): schema-aware prepared statements and automatic recompilation.
- [finalize](https://www.sqlite.org/c3ref/finalize.html): release every statement before releasing its database connection.

[Two alternating release pairs](../PERFORMANCE.md#sqlite-statement-reuse--2026-10-21) show modest ordinary/review warm-read service gains, with unchanged values/source bytes. Local strict checks pass: 180 registered Swift tests, 178 executed and two optional RAW skips. Six new regressions include prepare-count reuse and successful connection destruction with cached statements. No native UI/RAW or physical-media claim.

Full repository checks pass for 192 tracked files; three Python analyzer tests, release packaging and strict signature verification also pass. Native normal quit/relaunch restored the current folder/focus/Contact Sheet/density/filter context without personal edits. UI code is unchanged; changed database behavior is exercised on disposable fixtures.

The first remote Swift 6.1.2 build rejected forwarding an actor-bound query body through a nested actor-bound initialization closure, although local Swift 6.4 accepted it. Initialize the connection separately, then forward the synchronous body once. Do not erase isolation or add Sendable casts. Final supported-toolchain CI evidence belongs in the PR.
