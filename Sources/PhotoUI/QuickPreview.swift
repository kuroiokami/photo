import AppKit
import Observation
import PhotoCore
import PhotoImaging
import SwiftUI

@MainActor @Observable
final class QuickPreviewState {
  private(set) var held = false
  var pinned = false
  var visible: Bool { held || pinned }
  func dismiss() {
    held = false
    pinned = false
  }
  func key(
    down: Bool, repeating: Bool, modifiers: NSEvent.ModifierFlags,
    allowed: Bool, editingText: Bool
  ) -> Bool {
    if !down {
      guard held else { return false }
      held = false
      return true
    }
    guard allowed, !editingText,
      modifiers.intersection([.command, .control, .option]).isEmpty
    else {
      held = false
      return false
    }
    if held { return true }
    guard !repeating else { return false }
    held = true
    return true
  }
}

/// A window-local hold key works from native grid cells as well as SwiftUI.
/// It never intercepts typing, modified shortcuts, menus or another window.
struct QuickPreviewKeys: NSViewRepresentable {
  let state: QuickPreviewState
  let allowed: Bool
  func makeCoordinator() -> Coordinator { Coordinator(state) }
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.start()
    return view
  }
  func updateNSView(_ view: NSView, context: Context) { context.coordinator.allowed = allowed }
  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }
  @MainActor final class Coordinator {
    weak var view: NSView?
    var allowed = false
    let state: QuickPreviewState
    private var monitor: Any?
    private var inactive: NSObjectProtocol?
    init(_ state: QuickPreviewState) { self.state = state }
    func start() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) {
        [weak self] event in
        MainActor.assumeIsolated { self?.consumes(event) ?? false } ? nil : event
      }
      inactive = NotificationCenter.default.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: nil, queue: .main
      ) { [weak self] notification in
        let identity = (notification.object as? NSWindow).map { ObjectIdentifier($0) }
        MainActor.assumeIsolated {
          if let window = self?.view?.window, identity == ObjectIdentifier(window) {
            self?.state.dismiss()
          }
        }
      }
    }
    func consumes(_ event: NSEvent) -> Bool {
      guard let window = view?.window, event.window === window, window.isKeyWindow else {
        return false
      }
      if event.type == .keyDown, event.keyCode == 53, state.visible,
        event.modifierFlags.intersection([.command, .control, .option]).isEmpty
      {
        state.dismiss()
        return true
      }
      guard event.charactersIgnoringModifiers?.lowercased() == "w" else { return false }
      let editing = window.firstResponder is NSTextView || window.firstResponder is NSTextField
      return state.key(
        down: event.type == .keyDown, repeating: event.isARepeat,
        modifiers: event.modifierFlags,
        allowed: allowed && window.attachedSheet == nil && NSApp.mainMenu?.highlightedItem == nil,
        editingText: editing)
    }
    func stop() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      if let inactive { NotificationCenter.default.removeObserver(inactive) }
      monitor = nil
      inactive = nil
      state.dismiss()
    }
  }
}

struct QuickPreviewOverlay: View {
  let photo: PhotoItem
  let edit: PhotoEdit
  let pipeline: ImagePipeline
  let session: UUID
  let close: () -> Void
  let inspect: () -> Void
  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text("Quick Preview · " + photo.filename).lineLimit(1).truncationMode(.middle)
        Spacer()
        Button("Inspect at 100%", action: inspect).help(
          "Load genuine image detail (Z); RAW rendering starts only on request.")
        Button("Close", action: close).help("Release W or press Escape to return.")
      }.padding(.horizontal)
      PhotoImageView(
        photo: photo, pipeline: pipeline, maximumPixelSize: 2560,
        edit: edit, detailed: true, sessionID: session)
      Text("Hold W to peek; release to return. Z loads genuine 100% detail.")
        .font(.caption).foregroundStyle(.secondary)
    }.padding(.vertical, 10).frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: .underPageBackgroundColor))
      .accessibilityIdentifier("quick-preview")
  }
}
