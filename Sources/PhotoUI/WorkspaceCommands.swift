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
    CommandGroup(replacing: .undoRedo) {
      Button("Undo Decision") { actions?.workspace.undoDecision() }
        .keyboardShortcut("z", modifiers: .command).disabled(actions?.workspace.canUndo != true)
      Button("Redo Decision") { actions?.workspace.redoDecision() }
        .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(
          actions?.workspace.canRedo != true)
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
      }.disabled(actions?.canDecide != true || actions?.workspace.selectedPhoto == nil)
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
