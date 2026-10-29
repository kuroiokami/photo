import SwiftUI

private typealias HelpStorage<Value> = SwiftUI.State<Value>

struct CullingHelpView: View {
  @HelpStorage private var showingWalkthrough = false
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Quick Start & Shortcuts").font(.title2.bold())
      Button("Workflow Walkthrough") { showingWalkthrough = true }
        .help("Step-by-step ingest and culling examples for deadlines and large shoots.")
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(
            "Open a folder with ⌘O. Open Browsing options and turn on Include Subfolders to review a whole shoot together, or expand a sidebar arrow and choose one subfolder. Opened folders stay in the sidebar until you remove their shortcuts."
          )
          Text(
            "To cull before copying: open Workflow → Ingest, choose your Card or folder, leave Choose keepers before copying selected, and click Start Culling. Mark keepers with P in the main window. Then use Copy Reviewed Photos in the source banner, choose destinations and a copy scope, review the setup, and copy both destinations."
          )
          Text(
            "Click a photo, ⌘-click to add or remove individual photos, or Shift-click to select a range. Shift-arrow extends the range. Drag a rectangle to select visible thumbnails; hold ⌘ or Shift to add to the selection."
          )
          Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
            row("P / X / U", "Pick / Reject / Clear flag for the whole selection")
            row("0–5", "Set stars independently of flags; Shift applies and advances")
            row("T · ⌘T", "Toggle picks · Select visible picks")
            row("⌘A · ⌘D · ⇧⌘O", "Select all · Deselect all · Invert selection")
            row("Arrows · B / N", "Navigate; B / N always change photos, including while zoomed")
            row("Z · [ / ]", "Fit / 100% · Rotate left / right")
            row("Space · Escape", "Toggle preview · Exit Focus / show contact sheet")
            row("⇧⌘F · ⌥⌘T", "Focus on Photo · Hide/show filmstrip")
            row("⇧⌘X · ⌘Delete", "Select visible rejects · Review and move selection to Trash")
            row("C · G · L · O", "Compare · Pin current · Link zoom/pan · Single image")
            row("⌘G · M", "Ingest · Bulk Rename")
            row("I / ⌘I / ⌘K", "IPTC & Keywords")
            row("⇧⌘C", "Crop the focused photo; Image menu rotates/mirrors")
            row("⌘Z / ⇧⌘Z", "Undo / Redo decisions and image edits")
          }
          Text(
            "For one shared IPTC value, select the photos, open IPTC & Keywords, edit a field from the first selected photo, and click its Preview Field button. Review that field’s changes, then Apply Reviewed Fields. Other fields keep each photo’s existing values. Clear is explicit."
          )
          Text(
            "Give the photo more room with Focus on Photo (⇧⌘F). Escape restores panels. Hide the filmstrip with ⌥⌘T. Filters holds filtering and selection; Browsing options holds subfolders, pairing, EXIF labels and thumbnail size. Stars, flags, rotate/mirror, crop and IPTC stay directly accessible in the culling bar."
          )
          Text(
            "Pinch over the preview to magnify; two-finger scrolling pans. Click thumbnail stars or its flag menu to decide directly. Rotate/mirror/crop is saved in Photo only and does not transfer to Lightroom yet. At 100%, click the zoom navigator to center a new area or drag its white frame. With the navigator focused, arrows pan and Shift moves one view at a time. Click a thumbnail to resume photo navigation."
          )
          Text(
            "Hover over controls for explanations. X only marks rejects. To remove them from a working folder, choose Show All Photos and Clear Filters, then Filters → Remove → Select Rejects and ⌘Delete. Check the list and choose Move to Trash; restore with Finder → Trash → Put Back. Pre-copy sources stay protected; copy only keepers instead. RAW+JPEG grouping targets both files of a unique pair. Auto-advance applies only to single-photo decisions. Choose Photo Home for your usual photo folder. Rename before delivery or editor import; use Deliver / Edit to prepare copies."
          ).foregroundStyle(.secondary)
          Text(
            "Select two or more photos and choose Review Only Selected to hide other photos while judging that group individually. Show All Photos restores the folder. Labels adds up to two remembered EXIF rows. Verified Photo ingest arrivals appear automatically. IPTC & Keywords has separate, persistent Undo/Redo for the latest 20 metadata batches."
          )
        }
      }
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
    }.padding(24).frame(width: 720, height: 620)
      .sheet(isPresented: $showingWalkthrough) { WorkflowWalkthrough() }
  }
  private func row(_ key: String, _ action: String) -> some View {
    GridRow {
      Text(key).font(.body.monospaced())
      Text(action)
    }
  }
}
