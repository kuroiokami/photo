# 0008 — Progressive full-quality RAW inspection

- Date: 2026-10-19
- Status: Accepted

## Context

A whole-image RAW render delays first 100% inspection. Core Image can defer a CGImage's pixels until first draw, placing expensive work in the UI display path. Recreating contexts also discards reusable renderer state. The app must preserve actual image-pixel/display-pixel mapping and bounded detail ownership.

## Decision

On an explicit 100% request, render a small full-quality focus region first, then the entire oriented RAW image on the same serial actor. Use unchanged CIRAWFilter defaults at scale 1: no draft mode, reduced resolution, disabled noise reduction or substituted embedded preview. Carry the region's top-left pixel bounds and full image dimensions to a single native scroll view. Pixels outside the ready region remain black until the full image arrives, with a visible loading explanation. Retain pan position through the transition; use the existing Fit image for the navigator.

Reuse one CIContext with intermediate caching disabled. Render into owned RGBA8/sRGB bitmaps using CIRenderDestination and wait for successful completion off the main actor. Full-height renders proceed in 1024-row strips, releasing context caches between strips and checking cancellation. Strip rendering bounds temporary output surfaces; it does not promise that Apple's RAW decoder avoids full-source processing. SwiftUI consumes an AsyncThrowingStream; terminating the consumer cancels the producer. Apple decoding/render calls cannot be interrupted mid-call; stale results are rejected and subsequent strips/queued requests are skipped.

The focus region is capped at 2048 pixels per edge and 32 MiB, and is omitted if its conservative aligned byte cost plus the full image would exceed 256 MiB. This refines the former single-detail-image rule: one temporary region can coexist with the completing full image within the same combined limit. Fit, selection changes and disappearing views release both. There is no full-detail cache or speculative RAW processing. Driver/decoder/context working memory is separate from retained decoded-image bytes and must be measured explicitly.

Cache the AppKit drawing wrapper per image and avoid redundant navigator state updates. Offer Cancel while rendering. Add a release bundle option and a repeatable aggregate, read-only --detail benchmark including a legacy first viewport draw.

## Alternatives and consequences

Draft decoding showed little benefit in the local probe and can affect focus judgments. Turning off sharpening/noise reduction changed appearance, so neither ships. Rendering only a crop forever would require a separate tile scheduler and panning policy. Eagerly rendering one full surface had higher measured transient memory; strips trade some total completion time for bounded output surfaces and finer cancellation. First inspection is the primary culling metric; full-image completion and memory remain separately reported.

The legacy benchmark's first viewport draw may not materialize every offscreen pixel, so it has no comparable full-completion measurement. New progressive completion is measured explicitly. Service timings do not establish native frame latency or broad camera performance.

References: [Apple performance guidance](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_performance/ci_performance.html), [deferred CGImage rendering](https://developer.apple.com/documentation/coreimage/cicontext/createcgimage(_:from:format:colorspace:deferred:)), [render destinations](https://developer.apple.com/documentation/coreimage/cirenderdestination).
