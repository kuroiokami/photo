import AppKit
import Foundation
import Testing

@testable import PhotoUI

@MainActor
struct PhotoWindowRecoveryTests {
  private func window() -> NSWindow {
    let window = NSWindow(
      contentRect: CGRect(x: 100, y: 100, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }
  @Test func hiddenWorkspaceIsReusedAndClosedWorkspaceCreatesOneScene() {
    var created = 0
    var presented: [NSWindow] = []
    let recovery = PhotoWindowRecovery(activate: {}, present: { presented.append($0) })
    recovery.installOpener { created += 1 }
    let original = window()
    recovery.register(original)
    #expect(recovery.showWorkspace())
    #expect(presented.last === original)
    #expect(created == 0)
    NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: original)
    #expect(recovery.showWorkspace())
    #expect(recovery.showWorkspace())
    #expect(created == 1)
    let replacement = window()
    recovery.register(replacement)
    #expect(recovery.showWorkspace())
    #expect(presented.last === replacement)
    #expect(created == 1)
  }
  @Test func noOpenerFallsBackAndReleasedWindowsDoNotStayAlive() {
    let recovery = PhotoWindowRecovery(activate: {}, present: { _ in })
    #expect(!recovery.showWorkspace())
    weak var weakWindow: NSWindow?
    autoreleasepool {
      let temporary = window()
      weakWindow = temporary
      recovery.register(temporary)
      temporary.close()
    }
    #expect(weakWindow == nil)
    #expect(!recovery.showWorkspace())
  }
  @Test func closingOneWorkspaceKeepsAnotherAvailable() {
    var created = 0
    var presented: NSWindow?
    let recovery = PhotoWindowRecovery(activate: {}, present: { presented = $0 })
    recovery.installOpener { created += 1 }
    let first = window()
    let second = window()
    recovery.register(first)
    recovery.register(second)
    #expect(recovery.showWorkspace())
    #expect(presented === second)
    NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: second)
    #expect(recovery.showWorkspace())
    #expect(presented === first)
    #expect(created == 0)
  }
  @Test func offscreenGeometryRecoversWithoutMovingVisibleWindows() {
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let second = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let visible = CGRect(x: -1800, y: 50, width: 1000, height: 700)
    #expect(
      PhotoWindowRecovery.recoveredFrame(visible, screens: [main, second], preferred: main) == nil)
    let recovered = PhotoWindowRecovery.recoveredFrame(
      CGRect(x: 20000, y: 0, width: 3000, height: 2000), screens: [main], preferred: main)
    #expect(recovered == main)
    #expect(PhotoWindowRecovery.recoveredFrame(visible, screens: [], preferred: main) == nil)
  }
}
