import AppKit
import Testing

@testable import PhotoUI

@MainActor struct QuickPreviewTests {
  @Test func holdReleaseAndFocusLoss() {
    let state = QuickPreviewState()
    #expect(
      state.key(down: true, repeating: false, modifiers: [], allowed: true, editingText: false))
    #expect(state.visible)
    #expect(
      state.key(down: true, repeating: true, modifiers: [], allowed: true, editingText: false))
    // Release must clear a held key even if a sheet or text editor appeared meanwhile.
    #expect(
      state.key(
        down: false, repeating: false, modifiers: .command, allowed: false, editingText: true))
    #expect(!state.visible)
    state.pinned = true
    #expect(state.visible)
    state.dismiss()
    #expect(!state.visible)
    #expect(
      !state.key(down: true, repeating: true, modifiers: [], allowed: true, editingText: false))
    #expect(!state.visible)
  }
  @Test func typingShortcutsAndUnavailablePreview() {
    let state = QuickPreviewState()
    for modifiers: NSEvent.ModifierFlags in [.command, .control, .option] {
      #expect(
        !state.key(
          down: true, repeating: false, modifiers: modifiers, allowed: true, editingText: false))
    }
    #expect(
      !state.key(down: true, repeating: false, modifiers: [], allowed: true, editingText: true))
    #expect(
      !state.key(down: true, repeating: false, modifiers: [], allowed: false, editingText: false))
    #expect(!state.visible)
    #expect(
      state.key(
        down: true, repeating: false, modifiers: .capsLock, allowed: true, editingText: false))
    #expect(state.visible)
    state.dismiss()
  }
}

@MainActor private final class PreviewTestWindow: NSWindow {
  override var isKeyWindow: Bool { true }
}

extension QuickPreviewTests {
  @Test func windowLocalEventHandlerAndTextResponder() throws {
    _ = NSApplication.shared
    let window = PreviewTestWindow(
      contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = NSView()
    window.contentView = view
    let state = QuickPreviewState()
    let coordinator = QuickPreviewKeys.Coordinator(state)
    coordinator.view = view
    coordinator.allowed = true
    func key(_ down: Bool, modifiers: NSEvent.ModifierFlags = [], windowNumber: Int? = nil) throws
      -> NSEvent
    {
      try #require(
        NSEvent.keyEvent(
          with: down ? .keyDown : .keyUp, location: .zero,
          modifierFlags: modifiers, timestamp: 0, windowNumber: windowNumber ?? window.windowNumber,
          context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false,
          keyCode: 13))
    }
    #expect(!coordinator.consumes(try key(true, modifiers: .command)))
    #expect(!coordinator.consumes(try key(true, windowNumber: -1)))
    #expect(coordinator.consumes(try key(true)))
    #expect(state.visible)
    // Adding Command while W is held must still deliver normal Close Window.
    #expect(!coordinator.consumes(try key(true, modifiers: .command)))
    #expect(!state.visible)
    #expect(coordinator.consumes(try key(true)))
    #expect(coordinator.consumes(try key(false)))
    #expect(!state.visible)
    let editor = NSTextView(frame: view.bounds)
    view.addSubview(editor)
    #expect(window.makeFirstResponder(editor))
    #expect(!coordinator.consumes(try key(true)))
    #expect(!state.visible)
    state.pinned = true
    coordinator.stop()
    #expect(!state.visible)
  }
}
