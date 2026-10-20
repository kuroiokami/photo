import SwiftUI

private typealias WalkthroughStorage<Value> = SwiftUI.State<Value>

/// Shared by the contextual invitation and the manually opened guide.
enum WorkflowGuidance {
  static let dismissalKey = "Photo.workflow.hideIntroduction"
}

struct WorkflowWalkthrough: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage(WorkflowGuidance.dismissalKey) private var hideIntroduction = false
  @WalkthroughStorage private var step = 0

  private let titles = [
    "Choose the right starting point", "Copy safely and start choosing", "Cull in two passes",
    "Caption the keepers", "Finish for your assignment",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Copy, cull and deliver").font(.title2.bold())
        Spacer()
        Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("Step \(step + 1) of \(titles.count) · \(titles[step])").font(.headline)
        .accessibilityAddTraits(.isHeader)
      ProgressView(value: Double(step + 1), total: Double(titles.count))
        .accessibilityLabel("Walkthrough progress")
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          switch step {
          case 0:
            section(
              "Need copied photos today?",
              "Use Ingest to copy the complete shoot and choose keepers as verified photos arrive. Or use Review Before Copying to choose a smaller set first, then copy that reviewed list to both destinations."
            )
            section(
              "Photos already on your computer?",
              "Open their folder directly. Choose Photo Home in the sidebar as your usual starting place; it does not move or import anything."
            )
            section(
              "Want to review a source without changing it?",
              "Review Before Copying keeps stars, flags and crops on this Mac while the source stays unchanged. Use Copy Reviewed Photos… in the source banner to prepare and copy your choices, carrying decisions and Photo-local edits to both copies. The source stays protected afterward."
            )
          case 1:
            section(
              "Example: a card from today’s match",
              "Choose Copy from, your Photo folder, a Backup folder and a Shoot name. Use separate drives for independent copies. For a reviewed source, choose All Photos, Picks Only, Everything Except Rejects or Current Selection, then Prepare Copy List. Check unreviewed counts and added RAW/JPEG companions before Copy Reviewed Photos."
            )
            section(
              "Keep moving",
              "Choose Continue Browsing while copying runs. Ordinary ingest opens verified arrivals; reviewed copying keeps the source open until you choose Review Copied Photos. The copy list stays fixed if you keep culling. Resume Saved Copy continues that exact list after interruption and preserves later destination work."
            )
            section(
              "Before clearing the card",
              "Wait for both copies to verify and review metadata to be ready; resolve any pending metadata status before delivery. Keep the card until you have checked your copies. Later ratings and captions do not automatically update the backup. For a later source selection, prepare a new list and fresh shoot folder."
            )
          case 2:
            section(
              "Pass 1: the moment",
              "Stay in Fit for fast embedded RAW previews. Press P for a keeper, X for a reject and U to clear the flag. Reject never deletes a photo. Hold Shift to decide and advance, or enable Auto-advance for single-photo decisions."
            )
            section(
              "Pass 2: the strongest frames",
              "Filter to picks, compare similar frames and inspect 100% only when focus matters. Use 0–5 stars to rank the shortlist independently of flags. Full RAW detail takes longer than the embedded preview."
            )
            section(
              "Example: a wedding burst",
              "Select a burst and use Review Selection to keep that group together while choosing individual frames. End Review returns to the folder. Select multiple thumbnails to apply a shared flag or star rating."
            )
          case 3:
            section(
              "Shared facts once, individual captions where needed",
              "Select the keepers and open IPTC & Keywords. Edit a shared field such as Copyright, preview that field’s changes, then apply the reviewed fields. Each photo keeps its other metadata. Caption individual people and moments separately."
            )
            section(
              "Names and saving",
              "Use Bulk Rename before delivering or importing into an editor. Preview the names before applying. Check saving and XMP status; resolve failures or conflicts before relying on another app to read the decisions."
            )
            section(
              "Image edits have a different boundary",
              "Rotate, mirror and crop are saved in Photo only. They do not yet change delivery pixels or transfer to Lightroom. Finish publication image edits in an editor."
            )
          default:
            section(
              "Deadline / wire: send the essential frames first",
              "Review essential frames → copy Current Selection, or copy the full shoot while culling → check shortlist focus → add accurate captions, credit and rights → prepare delivery copies in Deliver / Edit. Finish any required image processing and agency submission outside Photo; Lightroom is optional."
            )
            section(
              "Wedding / large shoot: narrow in stages",
              "Verify the complete shoot and backup → flag a first pass → compare bursts → rank the survivors → apply shared metadata and rename → prepare the shortlist for Lightroom or another editor. Do not wait for full RAW rendering on every frame."
            )
            section(
              "Return whenever you need",
              "Open Help → Photo Quick Start & Shortcuts → Workflow Walkthrough. Hover over individual controls for shorter explanations. This guide explains the tools; it does not run operations or change photos."
            )
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      Divider()
      Toggle("Don’t show the ingest introduction again", isOn: $hideIntroduction)
        .help("Remembered between launches. You can always open the walkthrough from Help.")
      HStack {
        Text("You can reopen this guide from Help.").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Back") { step -= 1 }.disabled(step == 0)
        Button(step == titles.count - 1 ? "Done" : "Next") {
          if step == titles.count - 1 { dismiss() } else { step += 1 }
        }.keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 700, height: 590)
  }

  private func section(_ title: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.headline).accessibilityAddTraits(.isHeader)
      Text(text).fixedSize(horizontal: false, vertical: true)
    }
  }
}
