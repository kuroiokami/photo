import PhotoCore
import SwiftUI

struct WorkspaceActions {
  let workspace: WorkspaceState
  let canDecide: Bool
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
