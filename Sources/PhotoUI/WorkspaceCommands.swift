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
  let clearThumbnails: @MainActor () -> Void
  let workflow: @MainActor (Int) -> Void
  let help: @MainActor () -> Void
  let canReload: Bool
  let comparison: ComparisonSession
  let toggleComparison: @MainActor () -> Void
  let pinReference: @MainActor () -> Void
  let canCompare: Bool
  let crop: @MainActor () -> Void
  let copyCrop: @MainActor () -> Void
  let pasteCrop: @MainActor () -> Void
  let canPasteCrop: Bool
  let inspect: @MainActor () -> Void
  let trash: @MainActor () -> Void
  let canTrash: Bool
  var toggleFocus: @MainActor () -> Void = {}
  var focused = false
  var toggleFilmstrip: @MainActor () -> Void = {}
  var filmstripVisible = true
  var toggleQuickPreview: @MainActor () -> Void = {}
  var quickPreviewVisible = false

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
  @FocusedValue(\.detailPan) private var detailPan
  public init() {}

  public var body: some Commands {
    if actions?.canDecide == true {
      CommandGroup(replacing: .undoRedo) {
        Button("Undo " + (actions?.workspace.undoTitle ?? "Change")) {
          actions?.workspace.undoDecision()
        }
        .keyboardShortcut("z", modifiers: .command).disabled(actions?.workspace.canUndo != true)
        Button("Redo " + (actions?.workspace.redoTitle ?? "Change")) {
          actions?.workspace.redoDecision()
        }
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
        Button(detailPan == nil ? "Previous Photo" : "Pan Left") {
          if let detailPan {
            detailPan.pan(-0.25, 0)
          } else {
            actions?.workspace.moveSelection(by: -1)
          }
        }
        .keyboardShortcut(.leftArrow, modifiers: [])
        Button(detailPan == nil ? "Next Photo" : "Pan Right") {
          if let detailPan {
            detailPan.pan(0.25, 0)
          } else {
            actions?.workspace.moveSelection(by: 1)
          }
        }
        .keyboardShortcut(.rightArrow, modifiers: [])
        Button(detailPan == nil ? "Previous Row" : "Pan Up") {
          if let detailPan {
            detailPan.pan(0, -0.25)
          } else {
            actions?.workspace.moveSelection(by: -(actions?.columns ?? 1))
          }
        }
        .keyboardShortcut(.upArrow, modifiers: [])
        Button(detailPan == nil ? "Next Row" : "Pan Down") {
          if let detailPan {
            detailPan.pan(0, 0.25)
          } else {
            actions?.workspace.moveSelection(by: actions?.columns ?? 1)
          }
        }
        .keyboardShortcut(.downArrow, modifiers: [])
        Button(detailPan == nil ? "Extend Selection Left" : "Pan Left One View") {
          if let detailPan {
            detailPan.pan(-1, 0)
          } else {
            actions?.workspace.moveSelection(by: -1, extending: true)
          }
        }.keyboardShortcut(.leftArrow, modifiers: .shift)
        Button(detailPan == nil ? "Extend Selection Right" : "Pan Right One View") {
          if let detailPan {
            detailPan.pan(1, 0)
          } else {
            actions?.workspace.moveSelection(by: 1, extending: true)
          }
        }.keyboardShortcut(.rightArrow, modifiers: .shift)
        Button(detailPan == nil ? "Extend Selection Up" : "Pan Up One View") {
          if let detailPan {
            detailPan.pan(0, -1)
          } else {
            actions?.workspace.moveSelection(by: -(actions?.columns ?? 1), extending: true)
          }
        }.keyboardShortcut(.upArrow, modifiers: .shift)
        Button(detailPan == nil ? "Extend Selection Down" : "Pan Down One View") {
          if let detailPan {
            detailPan.pan(0, 1)
          } else {
            actions?.workspace.moveSelection(by: actions?.columns ?? 1, extending: true)
          }
        }.keyboardShortcut(.downArrow, modifiers: .shift)
        Button(detailPan == nil ? "First Photo" : "Top Left") {
          if let detailPan {
            detailPan.jump(.zero)
          } else {
            actions?.workspace.moveSelection(by: Int.min)
          }
        }
        .keyboardShortcut(.home, modifiers: [])
        Button(detailPan == nil ? "Last Photo" : "Bottom Right") {
          if let detailPan {
            detailPan.jump(CGPoint(x: 1, y: 1))
          } else {
            actions?.workspace.moveSelection(by: Int.max)
          }
        }
        .keyboardShortcut(.end, modifiers: [])
        Button("Previous Photo While Zoomed") { actions?.workspace.moveSelection(by: -1) }
          .keyboardShortcut("b", modifiers: [])
        Button("Next Photo While Zoomed") { actions?.workspace.moveSelection(by: 1) }
          .keyboardShortcut("n", modifiers: [])
        Button("Fit / 100%") { actions?.inspect() }.keyboardShortcut("z", modifiers: [])
        Button("Toggle Preview") { actions?.togglePreview() }
          .keyboardShortcut(.space, modifiers: [])
        Button("Hide Preview") { actions?.hidePreview() }
          .keyboardShortcut(.escape, modifiers: [])
      }.disabled(actions?.canDecide != true)
    }
    CommandMenu("Image") {
      Group {
        Button("Rotate Left") { actions?.workspace.editSelection(.counterclockwise) }
          .keyboardShortcut("[", modifiers: [])
        Button("Rotate Right") { actions?.workspace.editSelection(.clockwise) }
          .keyboardShortcut("]", modifiers: [])
        ForEach([PhotoEditAction.horizontal, .vertical], id: \.self) { action in
          Button(action.rawValue) { actions?.workspace.editSelection(action) }
        }
        Divider()
        Button("Crop…") { actions?.crop() }.keyboardShortcut("c", modifiers: [.command, .shift])
        Button("Copy Crop") { actions?.copyCrop() }.disabled(
          actions?.workspace.selectedID.map { actions?.workspace.imageEdits[$0]?.crop != nil }
            != true)
        Button("Paste Crop to Selection") { actions?.pasteCrop() }.disabled(
          actions?.canPasteCrop != true)
        Button("Clear Crop") { actions?.workspace.editSelection(.clearCrop) }
        Button("Reset Image Edits") { actions?.workspace.editSelection(.reset) }
        Button("Retry Image Edit Save") { actions?.workspace.retryImageEditSave() }
      }.disabled(actions?.canDecide != true || actions?.workspace.decisionSelectionReady != true)
    }
    CommandMenu("Review") {
      if actions?.canDecide == true {
        Button(actions?.comparison.enabled == true ? "Single Image" : "Compare Photos") {
          actions?.toggleComparison()
        }
        .keyboardShortcut("c", modifiers: [])
        .disabled(actions?.comparison.enabled != true && actions?.canCompare != true)
        Button("Pin Current as Reference") { actions?.pinReference() }
          .keyboardShortcut("g", modifiers: []).disabled(actions?.workspace.selectedPhoto == nil)
        Toggle(
          "Link Zoom and Pan",
          isOn: Binding(
            get: { actions?.comparison.linked ?? true }, set: { actions?.comparison.setLinked($0) })
        )
        .keyboardShortcut("l", modifiers: []).disabled(actions?.comparison.enabled != true)
        Button("Single Image") { actions?.comparison.close() }
          .keyboardShortcut("o", modifiers: []).disabled(actions?.comparison.enabled != true)
        Divider()
        Button(
          actions?.workspace.reviewingSelection == true
            ? "Show All Photos" : "Review Only Selected"
        ) {
          guard let workspace = actions?.workspace else { return }
          if workspace.reviewingSelection {
            workspace.endReview()
          } else {
            workspace.reviewSelection()
          }
        }.disabled(
          actions?.workspace.reviewingSelection != true
            && (actions?.workspace.selectedIDs.count ?? 0) < 2)
      }
    }
    CommandMenu("Decisions") {
      if actions?.canDecide == true {
        Button("Deselect All Photos") { actions?.workspace.deselectAll() }.keyboardShortcut(
          "d", modifiers: .command)
        Button("Invert Selection") { actions?.workspace.invertSelection() }.keyboardShortcut(
          "o", modifiers: [.command, .shift])
        Button("Select Picks") { actions?.workspace.selectPicks() }.keyboardShortcut(
          "t", modifiers: .command)
        Button("Select Rejects") { actions?.workspace.selectRejects() }
          .keyboardShortcut("x", modifiers: [.command, .shift])
        Button("Move Selected to Trash…") { actions?.trash() }
          .keyboardShortcut(.delete, modifiers: .command).disabled(actions?.canTrash != true)
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
    CommandGroup(after: .toolbar) {
      Button(
        actions?.quickPreviewVisible == true ? "Close Quick Preview" : "Quick Preview (hold W)"
      ) {
        actions?.toggleQuickPreview()
      }.disabled(actions?.canDecide != true || actions?.workspace.selectedPhoto == nil)
      Button(actions?.focused == true ? "Exit Focus on Photo" : "Focus on Photo") {
        actions?.toggleFocus()
      }
      .keyboardShortcut("f", modifiers: [.command, .shift]).disabled(actions?.canDecide != true)
      Button(actions?.filmstripVisible == true ? "Hide Filmstrip" : "Show Filmstrip") {
        actions?.toggleFilmstrip()
      }
      .keyboardShortcut("t", modifiers: [.command, .option]).disabled(actions?.canDecide != true)
      Divider()
      Button("Clear Thumbnail Cache") { actions?.clearThumbnails() }
        .disabled(actions?.canDecide != true)
    }
    CommandGroup(after: .newItem) {
      Button("Open Folder…") { actions?.openFolder() }
        .keyboardShortcut("o", modifiers: .command)
        .disabled(actions?.canDecide != true)
      Button("Reload Folder") { actions?.reload() }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(actions?.canReload != true)
    }
  }
}
