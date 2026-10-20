import AppKit
import PhotoCore
import SwiftUI

struct WorkspaceActions {
  let workspace: WorkspaceState
  let canDecide: Bool
  let columns: Int
  let togglePreview: @MainActor () -> Void
  let hidePreview: @MainActor () -> Void
  let openFolder: @MainActor () -> Void
  let reload: @MainActor () -> Void
  let workflow: @MainActor (Int) -> Void
  let help: @MainActor () -> Void
  let canReload: Bool
}

private struct WorkspaceActionsKey: FocusedValueKey {
  typealias Value = WorkspaceActions
}

extension FocusedValues {
  var workspaceActions: WorkspaceActions? {
    get { self[WorkspaceActionsKey.self] }
    set { self[WorkspaceActionsKey.self] = newValue }
  }
}

public struct WorkspaceCommands: Commands {
  @FocusedValue(\.workspaceActions) private var actions
  public init() {}

  public var body: some Commands {
    if actions?.canDecide == true {
      CommandGroup(replacing: .undoRedo) {
        Button("Undo Decision") { actions?.workspace.undoDecision() }
          .keyboardShortcut("z", modifiers: .command).disabled(actions?.workspace.canUndo != true)
        Button("Redo Decision") { actions?.workspace.redoDecision() }
          .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(
            actions?.workspace.canRedo != true)
      }
    }
    if actions?.canDecide == true {
      CommandGroup(replacing: .pasteboard) {
        Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
          .keyboardShortcut("c", modifiers: .command)
        Button("Select All Photos") { actions?.workspace.selectAllVisible() }
          .keyboardShortcut("a", modifiers: .command)
      }
    }
    CommandMenu("Navigate") {
      Group {
        Button("Previous Photo") { actions?.workspace.moveSelection(by: -1) }
          .keyboardShortcut(.leftArrow, modifiers: [])
        Button("Next Photo") { actions?.workspace.moveSelection(by: 1) }
          .keyboardShortcut(.rightArrow, modifiers: [])
        Button("Previous Row") { actions?.workspace.moveSelection(by: -(actions?.columns ?? 1)) }
          .keyboardShortcut(.upArrow, modifiers: [])
        Button("Next Row") { actions?.workspace.moveSelection(by: actions?.columns ?? 1) }
          .keyboardShortcut(.downArrow, modifiers: [])
        Button("Extend Selection Left") {
          actions?.workspace.moveSelection(by: -1, extending: true)
        }.keyboardShortcut(.leftArrow, modifiers: .shift)
        Button("Extend Selection Right") {
          actions?.workspace.moveSelection(by: 1, extending: true)
        }.keyboardShortcut(.rightArrow, modifiers: .shift)
        Button("Extend Selection Up") {
          actions?.workspace.moveSelection(by: -(actions?.columns ?? 1), extending: true)
        }.keyboardShortcut(.upArrow, modifiers: .shift)
        Button("Extend Selection Down") {
          actions?.workspace.moveSelection(by: actions?.columns ?? 1, extending: true)
        }.keyboardShortcut(.downArrow, modifiers: .shift)
        Button("First Photo") { actions?.workspace.moveSelection(by: Int.min) }
          .keyboardShortcut(.home, modifiers: [])
        Button("Last Photo") { actions?.workspace.moveSelection(by: Int.max) }
          .keyboardShortcut(.end, modifiers: [])
        Button("Toggle Preview") { actions?.togglePreview() }
          .keyboardShortcut(.space, modifiers: [])
        Button("Hide Preview") { actions?.hidePreview() }
          .keyboardShortcut(.escape, modifiers: [])
      }.disabled(actions?.canDecide != true)
    }
    CommandMenu("Decisions") {
      if actions?.canDecide == true {
        Button("Deselect All Photos") { actions?.workspace.deselectAll() }.keyboardShortcut(
          "d", modifiers: .command)
        Button("Invert Selection") { actions?.workspace.invertSelection() }.keyboardShortcut(
          "o", modifiers: [.command, .shift])
        Button("Select Picks") { actions?.workspace.selectPicks() }.keyboardShortcut(
          "t", modifiers: .command)
        Button("Toggle Picks") { actions?.workspace.togglePicks() }.keyboardShortcut(
          "t", modifiers: []
        )
        .disabled(actions?.workspace.decisionSelectionReady != true)
      }
      Divider()
      Group {
        ForEach([PhotoFlag.pick, .reject, .unflagged], id: \.self) { flag in
          Button(flag.title) { actions?.workspace.applyDecision(flag: flag) }
            .keyboardShortcut(
              KeyEquivalent(flag == .pick ? "p" : flag == .reject ? "x" : "u"), modifiers: [])
          Button("\(flag.title) and Advance") {
            actions?.workspace.applyDecision(flag: flag, advance: true)
          }
          .keyboardShortcut(
            KeyEquivalent(flag == .pick ? "p" : flag == .reject ? "x" : "u"), modifiers: .shift)
        }
        Divider()
        ForEach(0...5, id: \.self) { rating in
          Button("Set \(rating) Stars") { actions?.workspace.applyDecision(rating: rating) }
            .keyboardShortcut(KeyEquivalent(Character(String(rating))), modifiers: [])
          Button("Set \(rating) Stars and Advance") {
            actions?.workspace.applyDecision(rating: rating, advance: true)
          }
          .keyboardShortcut(KeyEquivalent(Character(String(rating))), modifiers: .shift)
        }
      }.disabled(actions?.canDecide != true || actions?.workspace.decisionSelectionReady != true)
    }

    CommandMenu("Workflow") {
      if actions?.canDecide == true {
        Button("Ingest…") { actions?.workflow(0) }.keyboardShortcut("g", modifiers: .command)
        Button("Bulk Rename…") { actions?.workflow(1) }.keyboardShortcut("m", modifiers: [])
        Button("IPTC & Keywords…") { actions?.workflow(2) }.keyboardShortcut(
          "i", modifiers: .command)
        Button("Metadata Info…") { actions?.workflow(2) }.keyboardShortcut("i", modifiers: [])
        Button("Keywords…") { actions?.workflow(2) }.keyboardShortcut("k", modifiers: .command)
      }
    }
    CommandGroup(after: .help) {
      Button("Photo Quick Start & Shortcuts") { actions?.help() }.disabled(
        actions?.canDecide != true)
    }
    CommandGroup(after: .newItem) {
      Button("Open Folder…") { actions?.openFolder() }
        .keyboardShortcut("o", modifiers: .command)
        .disabled(actions == nil)
      Button("Reload Folder") { actions?.reload() }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(actions?.canReload != true)
    }
  }
}
