import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

@main
@MainActor
struct PhotoApplication {
  static func main() {
    NSApplication.shared.setActivationPolicy(.regular)
    PhotoLifecycle.shared.record(.launch)
    PhotoScene.main()
  }
}

private final class PhotoDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) { PhotoLifecycle.shared.start() }
  func applicationDidBecomeActive(_ notification: Notification) {
    PhotoLifecycle.shared.record(.active)
  }
  func applicationDidResignActive(_ notification: Notification) {
    PhotoLifecycle.shared.record(.background)
  }
  func applicationWillTerminate(_ notification: Notification) {
    PhotoLifecycle.shared.record(.willTerminate)
    PhotoLifecycle.shared.stop()
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    PhotoLifecycle.shared.record(.quitRequested)
    guard DecisionSaveQueue.shared.hasPending || WorkflowOperationBarrier.shared.hasPending else {
      return .terminateNow
    }
    PhotoLifecycle.shared.record(.waitingForSaves)
    Task {
      await WorkflowOperationBarrier.shared.flush()
      await DecisionSaveQueue.shared.flush()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}

private struct PhotoScene: App {
  @NSApplicationDelegateAdaptor(PhotoDelegate.self) private var delegate

  var body: some Scene {
    WindowGroup("Photo") {
      WorkspaceView()
    }
    .defaultSize(width: 1280, height: 820)
    .commands { WorkspaceCommands() }
  }
}
