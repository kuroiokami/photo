# 0011 — Comparison, selected review and EXIF labels

- Date: 2026-10-20
- Status: Accepted

Pin a reference beside the active preview, sharing workspace selection but keeping separate demand-only detail workers. Explicit normalized zoom/pan requests route once to the peer; programmatic scrolling does not echo. Unlink retains independent navigation; relinking uses the active viewport. Photo/view/session changes reset both to Fit. Decisions follow thumbnail selection.

Retain at most 256 MiB decoded region/full detail per pane (512 MiB total in comparison). This explicit increase permits two 60 MP images; decoder/GPU/transient memory is additional. No speculative RAW work or detail cache is added. Fit/close/navigation releases images.

Selected review snapshots physical identities independently of ongoing selection, applying existing filters and grouping. Optional thumbnail labels use indexed EXIF, bounded to two remembered rows; missing metadata is explicit. Core review/label models stay independent of SwiftUI/AppKit. See WORKFLOW.md for commands and recovery.
