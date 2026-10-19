import AppKit
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

private struct PhotoScene: App {
  var body: some Scene {
    WindowGroup("Photo") {
      WorkspaceView()
    }
    .defaultSize(width: 1100, height: 760)
  }
}
