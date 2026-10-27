import AppKit
import SwiftUI

/// Restores workspace windows without replacing SwiftUI's window delegates.
@MainActor
public final class PhotoWindowRecovery: NSObject {
  public static let shared = PhotoWindowRecovery()
  public static let sceneID = "photo-workspace"
  private final class WindowReference {
    weak var window: NSWindow?
    init(_ window: NSWindow) { self.window = window }
  }
  private var windows: [WindowReference] = []
  private var createWindow: (@MainActor () -> Void)?
  private var creating = false
  private var retry: Task<Void, Never>?
  private let activate: @MainActor () -> Void
  private let present: @MainActor (NSWindow) -> Void
  private let record: @MainActor (PhotoLifecycle.Event) -> Void

  private override convenience init() {
    self.init(
      activate: {
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate()
      },
      present: { window in
        if window.isMiniaturized { window.deminiaturize(nil) }
        if let screen = window.screen ?? NSScreen.main,
          let frame = Self.recoveredFrame(
            window.frame, screens: NSScreen.screens.map(\.visibleFrame),
            preferred: screen.visibleFrame)
        {
          window.setFrame(frame, display: true)
        }
        window.makeKeyAndOrderFront(nil)
      }, record: { PhotoLifecycle.shared.record($0) })
  }
  init(
    activate: @escaping @MainActor () -> Void,
    present: @escaping @MainActor (NSWindow) -> Void,
    record: @escaping @MainActor (PhotoLifecycle.Event) -> Void = { _ in }
  ) {
    self.activate = activate
    self.present = present
    self.record = record
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(closed(_:)),
      name: NSWindow.willCloseNotification, object: nil)
  }
  deinit { NotificationCenter.default.removeObserver(self) }

  func installOpener(_ action: @escaping @MainActor () -> Void) { createWindow = action }
  func register(_ window: NSWindow) {
    windows.removeAll { $0.window == nil }
    if !windows.contains(where: { $0.window === window }) {
      windows.append(WindowReference(window))
    }
    creating = false
    retry?.cancel()
    retry = nil
  }
  @objc private func closed(_ note: Notification) {
    guard let window = note.object as? NSWindow,
      windows.contains(where: { $0.window === window })
    else { return }
    windows.removeAll { $0.window == nil || $0.window === window }
  }
  /// True means our registered SwiftUI workspace handled the request.
  @discardableResult public func showWorkspace() -> Bool {
    record(.reopenRequested)
    windows.removeAll { $0.window == nil }
    let available = windows.compactMap(\.window)
    if let window = available.first(where: { $0.isKeyWindow })
      ?? available.first(where: { $0.isMainWindow })
      ?? available.last
    {
      activate()
      present(window)
      record(.windowRestored)
      return true
    }
    guard let createWindow else { return false }
    guard !creating else { return true }
    creating = true
    // Arm before invoking SwiftUI: synchronous registration cancels this
    // retry, and an older timer cannot clear a newer creation request.
    retry?.cancel()
    retry = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
      self?.creating = false
      self?.retry = nil
    }
    activate()
    createWindow()
    record(.windowCreated)
    return true
  }
  static func recoveredFrame(_ frame: CGRect, screens: [CGRect], preferred: CGRect) -> CGRect? {
    guard !screens.isEmpty else { return nil }
    if screens.contains(where: {
      let intersection = frame.intersection($0)
      return !intersection.isNull && intersection.width >= 64 && intersection.height >= 64
    }) {
      return nil
    }
    let size = CGSize(
      width: min(max(640, frame.width), preferred.width),
      height: min(max(480, frame.height), preferred.height))
    return CGRect(
      x: preferred.midX - size.width / 2, y: preferred.midY - size.height / 2,
      width: size.width, height: size.height)
  }
}

/// The captured action targets the scene, so it can create a workspace after
/// the view that originally provided the action has closed.
public struct PhotoWorkspaceRoot: View {
  @Environment(\.openWindow) private var openWindow
  public init() {}
  public var body: some View {
    WorkspaceView()
      .background(WorkspaceWindowRegistration())
      .onAppear {
        let action = openWindow
        PhotoWindowRecovery.shared.installOpener { action(id: PhotoWindowRecovery.sceneID) }
      }
  }
}
private struct WorkspaceWindowRegistration: NSViewRepresentable {
  func makeNSView(context: Context) -> WorkspaceWindowProbe { WorkspaceWindowProbe() }
  // Registration belongs to attachment, not SwiftUI updates: a closing
  // workspace must not re-register its retired window during teardown.
  func updateNSView(_ nsView: WorkspaceWindowProbe, context: Context) {}
}
private final class WorkspaceWindowProbe: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let window { PhotoWindowRecovery.shared.register(window) }
  }
}

/// Window recovery remains available without a focused workspace or photo.
public struct PhotoWindowCommands: Commands {
  public init() {}
  public var body: some Commands {
    CommandGroup(after: .windowArrangement) {
      Button("Show Photo Window") { _ = PhotoWindowRecovery.shared.showWorkspace() }
        .keyboardShortcut("0", modifiers: .command)
    }
  }
}
