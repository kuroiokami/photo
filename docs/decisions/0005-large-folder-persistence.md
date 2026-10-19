# 0005: Bounded sidecar lookups and actor-owned SQLite connection

- Status: accepted
- Date: 2026-10-19

Large-folder measurement exposed repeated directory scans for each ARW and repeated SQLite connection/schema setup for every query. A 2,000-pair synthetic ARW/XMP corpus took about 36 seconds for initial and repeat decision loading.

Keep a single SQLite connection inside each DecisionStore actor, closed by a private owning wrapper on destruction. Statements remain scoped/finalized, busy timeout stays 3 seconds, synchronous mode stays FULL, and durable intent still precedes atomic XMP publication. Do not introduce a shared unsafe handle, deferred durability or bulk write buffering. Skip path-map writes only when the recorded identity already matches.

For ARW sidecar collision checks, query the eight ASCII extension case variants directly and compare their actual filesystem names. This bounds work per image without caching directory contents, so adding/removing a collision is rechecked on every operation. Distinct case-only files still conflict on case-sensitive filesystems; aliases on case-insensitive volumes count once. Existing malformed/symlink protections and explicit replacement conflicts remain.

Reject old-session work immediately after each awaited selected-photo read, before starting another snapshot read. Accepting external decisions must reposition the item in rating order while retaining selection. Keep the benchmark read-only with respect to its input folder and use an isolated temporary database.

Alternatives: caching directory scans needs invalidation and can miss newly introduced collisions; batch database transactions could hold locks or defer durability. Neither is needed for the measured improvement. Broader camera/storage and first-open decoder latency remain validation work, as documented in PERFORMANCE.md.
