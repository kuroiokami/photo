# 0040: Restore the SwiftUI workspace on reopen

- Date: 2026-10-27
- Status: Implemented; acceptance scope recorded in the tracker

## Evidence and decision

The user clarified that Photo remains in the Dock but clicking it sometimes produces no window. This does not establish process termination. The app previously had no explicit workspace handler for AppKit's reopen request.

Give the existing SwiftUI WindowGroup a stable ID. Resolve and retain `openWindow` from an installed root View, then route `applicationShouldHandleReopen` through a main-actor coordinator. Restore a live workspace first: unhide, deminiaturize, recover wholly offscreen geometry and bring it forward. If no workspace remains, invoke the retained scene action. Fall back to AppKit's default behavior if no action/window is available.

Register weak window references only when the lightweight view bridge attaches to a window. Remove them on `willClose`; ordinary SwiftUI view updates cannot re-register a closing workspace. Do not replace SwiftUI's window delegate, manually create hosting windows, or keep closed scenes hidden. Coalesce pending scene creation with a bounded retry, armed before calling SwiftUI so synchronous registration cancels it safely.

Add an always-available **Window → Show Photo Window (⌘0)** command independent of focused-photo actions. Keep default new-window behavior and existing multi-window save/operation barriers. Add fixed local `reopenRequested`, `windowRestored` and `windowCreated` diagnostic events; the record schema and privacy boundaries stay unchanged. No image, sidecar, termination-policy or sleep-policy changes.

Apple documents [AppKit reopen requests](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldhandlereopen(_:hasvisiblewindows:)) and [SwiftUI scene opening](https://developer.apple.com/documentation/swiftui/openwindowaction).

## Validation and limits

Regressions cover closed/hidden workspaces, duplicate creation, missing openers, weak lifetime, multiple windows and offscreen geometry. Native isolated-app checks cover standard macOS reopen requests after the last window closes, minimized-window recovery, the menu command and shortcut. Exact build identities and observed event/count transitions belong in the tracker/evidence. Direct physical Dock-click/trackpad and long-session acceptance are separate; this is not a claimed crash fix or proof of the original incident's root cause.
