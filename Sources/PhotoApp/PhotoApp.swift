import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

@main
@MainActor
struct PhotoApplication {
  static func main() {
    NSApplication.shared.setActivationPolicy(.regular)
    PhotoScene.main()
  }
}

private final class PhotoDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard DecisionSaveQueue.shared.hasPending || WorkflowOperationBarrier.shared.hasPending else {
      return .terminateNow
    }
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
