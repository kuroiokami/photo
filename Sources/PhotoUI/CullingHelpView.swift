import SwiftUI

struct CullingHelpView: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Quick Start & Shortcuts").font(.title2.bold())
      Text(
        "Open a folder with ⌘O. It stays in the sidebar until you remove its shortcut. Expand the arrow to see subfolders; click a name to display that folder’s photos."
      )
      Text(
        "Click a photo, ⌘-click to add or remove individual photos, or Shift-click to select a range. Shift-arrow extends the range. Drag a rectangle to select visible thumbnails; hold ⌘ or Shift to add to the selection."
      )
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
        row("P / X / U", "Pick / Reject / Clear flag for the whole selection")
        row("0–5", "Set stars independently of flags; Shift applies and advances")
        row("T · ⌘T", "Toggle picks · Select visible picks")
        row("⌘A · ⌘D · ⇧⌘O", "Select all · Deselect all · Invert selection")
        row("Arrows · Space · Escape", "Navigate · Toggle preview · Hide preview")
        row("⌘G · M", "Ingest · Bulk Rename")
        row("I / ⌘I / ⌘K", "IPTC & Keywords")
        row("⌘Z / ⇧⌘Z", "Undo / Redo culling decisions")
      }
      Text(
        "For one shared IPTC value, select the photos, open IPTC & Keywords, edit a field from the first selected photo, and click its Preview Field button. Review that field’s changes, then Apply Reviewed Fields. Other fields keep each photo’s existing values. Clear is explicit."
      )
      Text(
        "At 100%, click the zoom navigator to center a new area or drag its white frame. With the navigator focused, arrows pan and Shift moves one view at a time. Click a thumbnail to resume photo navigation."
      )
      Text(
        "Hover over controls for explanations. Reject never deletes photos. RAW+JPEG grouping targets both files of a unique pair. Auto-advance applies only to single-photo decisions. Rename before Lightroom import; use the Lightroom tab for the handoff checklist."
      ).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
    }.padding(24).frame(width: 720)
  }
  private func row(_ key: String, _ action: String) -> some View {
    GridRow {
      Text(key).font(.body.monospaced())
      Text(action)
    }
  }
}
