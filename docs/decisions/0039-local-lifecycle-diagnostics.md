# 0039: Record local lifecycle/resource diagnostics for unexplained exits

- Date: 2026-10-27
- Status: Implemented; reported intermittent idle exit remains unconfirmed

## Evidence and scope

The user reports Photo disappearing while idle/in the background. Local inspection finds no matching recent Photo crash report; existing PhotoBench traps are separate benchmark executions. An approximately eight-hour run of the currently installed Photo build ends through AppKit's normal quit path, and the user confirms choosing Quit. That run does not establish the cause of another disappearance. Do not label a normal exit a crash or claim the report fixed.

Apple documents automatic termination as opt-in and notes that setting its support property to false currently has no effect ([property documentation](https://developer.apple.com/documentation/foundation/processinfo/automaticterminationsupportenabled)). Initial candidate diagnostics report support false. Neither this observation nor the user's confirmed Quit proves what happened on another occasion. Do not change termination policy based on this hypothesis.

## Decision

Record fixed-field notices in the local unified log under `org.photo.lifecycle`: launch/ready, active/background, about-minute heartbeats, sleep/wake notifications, memory-pressure events, quit request/waiting-for-saves and termination. Include actual loaded-executable UUID, process ID, monotonic run uptime, resident/physical-footprint bytes when available, active/window state, automatic-termination support and pending decision/file-work flags.

Read the UUID from the loaded Mach-O image, not the app bundle's on-disk identity, so replacing a development bundle cannot misidentify an older running process. Kernel resource queries are optional; unavailable values remain absent. Reuse one encoder on the main actor. The cancellable background-priority timer starts once and stops on normal termination; system scheduling, App Nap and sleep may defer it. Log retention belongs to macOS. There is no app-owned accumulating log file, photo path/name/EXIF/pixel collection or network transmission. Raw system reports may contain private data and stay outside Git.

Explicit Quit, normal last-window behavior, decision/file-operation flushes, automatic/sudden termination settings and sleep behavior are unchanged. No signal handler attempts to recover a corrupted process. Diagnostic gaps alone are not proof of a crash; use process liveness, OS reports and termination events together.

## Validation and remaining work

Tests verify one sampler, cancellation after stop, fixed JSON fields and a valid loaded-image UUID. Native logs are compared with the release executable UUID and normal Quit records. Disposable 10k-photo idle runs sample liveness/RSS; durations, active-state limits and results belong in [performance evidence](../PERFORMANCE.md) and the tracker.

The intermittent report remains open until a matching report, unexpected-exit sequence or reproducible case exists. Short synthetic soaks do not establish overnight, sleep/wake, physical-camera or memory-pressure stability. No claim of a confirmed crash fix.
