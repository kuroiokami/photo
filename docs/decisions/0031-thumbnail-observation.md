# 0031 — Photo-specific thumbnail observation and selection summaries

- Date: 2026-10-22
- Status: Implemented; validation and delivery evidence in the tracker
- Refines ADRs 0027 and 0028. No persistence, image-cache or file-operation changes.

## Context

The cached readiness revision still belonged to WorkspaceState. Tiles read shared decision, readiness, selection, edit and metadata containers, so unrelated publications could invalidate their display. Selection summaries expanded the same selected families and mapped their decisions on every query.

## Decision

Keep a stable observable display object for each live photo, owned by the workspace. Publish only changed selected/readiness/decision/edit/metadata/family-count properties. Selection changes update the symmetric difference of selected IDs. Preserve objects across sorts, filters and verified arrivals; remove them with inventory membership and replace them on a folder/session reset. Grouping retains physical-file decisions and readiness.

Move selection presentation to a separate observable object. Rebuild its represented-file records on selection/focus, grouping or inventory changes, and update only affected selected records on decision publication/edits to stars or flags. Maintain readiness from represented-file membership plus unknown IDs. Notify readiness subscribers only when its Boolean changes; rating-summary subscribers have a separate revision. Lazily compute and cache the summary until represented decisions/membership change. Unknown records keep the prior unrated summary behavior while disabling decisions and image edits. Existing operationPhotos remains authoritative for operations.

Extract the thumbnail into its own SwiftUI View. Its body reads its photo object and, only for selected tiles, selection readiness. An Equatable boundary skips parent toolbar/status publications with unchanged inputs. Equality includes photo identity/value, display/selection object identities, pipeline, session, cache generation, density, labels, grouping and crop-clipboard availability. Callback closures use the owning WorkspaceView's stable State storage; do not capture independent changing values without adding them to equality. Keep explicit IDs/viewport geometry, selection semantics, quick actions, context menus and image task identity.

The extra display objects and selected-record snapshot trade memory and membership-construction work for narrower dependencies. They are not decoded images and do not alter cache budgets. Do not infer whole-app memory bounds or faster folder opening. High-frequency detail pan state, first-selected lookup and decision transaction batching are separate work.

## Validation

Observation regressions verify unrelated photo edits/decisions/metadata do not notify another tile; readiness ignores pure decision-value changes; summaries cache, notify and recover through Undo/Redo. Unknown family members gate operations. Tests exercise arrivals/pair membership, removed objects, same-folder session replacement, persisted read-back, rating sorting and filters with independent stars/flags. Existing background-session/cancellation and source-protection tests remain required.

`sh scripts/benchmark.sh --selection-summary` measures the same public workspace API on baseline and updated builds, with initialization, decision loading and selecting separately from repeated summary/readiness queries. It uses synthetic in-memory items, not real images, large-shoot acceptance or SwiftUI body/frame measurements. Native disposable-file checks cover the extracted controls, scrolling, selection, editing and view/density/label changes; results and limits belong in the tracker and performance notes.
