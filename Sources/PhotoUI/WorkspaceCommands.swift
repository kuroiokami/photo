import SwiftUI

struct WorkspaceActions {
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
