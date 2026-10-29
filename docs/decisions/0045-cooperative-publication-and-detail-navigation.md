# 0045 — Cooperative publications and isolated detail navigation

Date: 2026-10-28

Status: Implemented; performance and native acceptance in the tracker.

## Background publications

Earlier collection publication waited for 64 results or 50 ms and applied the whole pending dictionary in one main-actor turn. Use at most 16 records per background publication, with an adaptive **2 ms model-work target**: halve the next item limit after an overshoot, down to one; grow slowly after sustained headroom. Yield between decision publications and final drains. Metadata reads already yield individually; publish when pending values reach the current limit, or the existing progress/time threshold is due. Keep selected-photo/family promotion immediate, guarded by current session and decision versions.

Drain remaining metadata before clearing indexing and allowing completed EXIF order; drain decisions before clearing readiness/loading and rebuilding filters/rating order. Never publish an obsolete session or overwrite a user decision with an older read. Preserve read-only indexing, per-file errors, cancellation/retry, final numeric sorting and source context checks. Save durability and the independent decision-save queue are unchanged.

This is a cooperative target, **not a hard 2 ms deadline or FPS guarantee**. A single update, Observation, OS scheduling and later SwiftUI layout cannot be preempted. Count actual maximum records, measured synchronous duration and overshoots for both metadata and decision publication; schema 3 of the scale harness exports these fixed aggregates. Whole-job timing, native presented frames and layout costs remain distinct. Retain overshoots/slower controls honestly.

## Detail navigation

Move visible-rectangle, focal point, magnification and programmatic-navigation state into a separate observable viewport. The navigator observes its rectangle; the native surface observes commands. Decoded images, RAW loading and detail error state no longer depend on every pan/pinch report. Fit/100% controls and the percentage label observe magnification in their own children. Keep magnification, genuine physical-pixel scaling, crop/orientation transforms and image lifetime limits unchanged.

Use one observable command channel per comparison pane, with routing bookkeeping ignored by Observation. A linked pan invalidates only its receiving channel. A small command-relay child applies pan commands to the viewport; Fit/zoom still deliberately updates image/loading controls. Preserve independent/unlinked panes, explicit detail admission, last normalized center, resets and loop prevention.

Coalesce native visible/pan callback bursts into one weak deferred main-actor task carrying the latest rectangle and center. Rebind handlers during representable updates and cancel/clear on teardown so a released or replaced viewport cannot receive late reports. No Task per individual callback and no new image decode is needed for panning.

## Validation

Regressions exercise budget reduction/recovery and bounded complete indexing; real rendered navigator pixel changes without rebuilding its parent image controls; per-pane Observation invalidation; callback burst coalescing and late-result rejection; plus existing progressive RAW region, orientation/crop, linked comparison, repeated navigator and genuine-pixel tests. Use generated/redistributable inputs for matched scale and native controls, preserve hashes, and report model timings separately from physical frames and representative-camera/media acceptance.

The scale heartbeat also compares elapsed `ContinuousClock` and [Apple’s system-awake `SuspendingClock`](https://developer.apple.com/documentation/swift/suspendingclock) intervals. Report the largest positive clock difference so machine sleep cannot masquerade as an application stall. This is a suspension indicator, not a precise CPU-time measurement. Exclude contaminated trials; temporary idle-sleep assertions do not prevent every physical-lid or OS sleep event.
