import PhotoCore
import SwiftUI

private typealias TrashStorage<Value> = SwiftUI.State<Value>

struct TrashConfirmationView: View {
  let plan: PhotoTrashPlan
  let store: DecisionStore
  let decisions: [String: CullingDecision]
  let completed: (PhotoTrashResult) -> Void
  @Environment(\.dismiss) private var dismiss
  @TrashStorage private var working = false
  @TrashStorage private var result: PhotoTrashResult?
  private var picks: Int {
    plan.images.filter { decisions[PhotoItem(fileURL: $0).id]?.flag == .pick }.count
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(
        plan.images.count == 1
          ? "Move this photo to Trash?" : "Move \(plan.images.count) photos to Trash?"
      ).font(.title2.bold())
      Text(
        "Only the listed files in this folder are affected. Copies in other folders and on backup drives stay where they are."
      )
      if picks > 0 {
        Label(
          "This selection includes \(picks) picked photos. Cancel if you only meant to remove rejects.",
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.orange)
      }
      Text(
        "\(plan.companions.count) matching XMP/ACR sidecars will also move. \(plan.retainedSharedCompanions) shared sidecars stay to protect other photos."
      )
      .font(.callout).foregroundStyle(.secondary)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 5) {
          ForEach(plan.images + plan.companions, id: \.self) { url in
            Text(url.lastPathComponent).textSelection(.enabled)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(maxHeight: .infinity)
      if let result {
        Text(
          "Moved \(result.moved.count) files to Trash."
            + (result.error.map { " Stopped: " + $0 } ?? "")
        )
        .textSelection(.enabled)
      }
      Text(
        "Restore files in Finder → Trash → Put Back. Photo’s Undo does not restore trashed files. If macOS cannot move a file to Trash, Photo stops; it never permanently deletes it."
      )
      .font(.caption).foregroundStyle(.secondary)
      HStack {
        if working {
          ProgressView().controlSize(.small)
          Text("Moving files to Trash…")
        }
        Spacer()
        Button(result == nil ? "Cancel" : "Done") { dismiss() }
          .keyboardShortcut(.cancelAction).disabled(working)
        if result == nil {
          Button("Move to Trash", role: .destructive) {
            guard !working, result == nil else { return }
            working = true
            let worker = Task {
              await DecisionSaveQueue.shared.flush()
              let report = await PhotoTrash(store: store).execute(plan)
              completed(report)
              result = report
              working = false
            }
            WorkflowOperationBarrier.shared.track(worker)
          }.keyboardShortcut(.defaultAction).disabled(working)
        }
      }
    }.padding(24).frame(width: 620, height: 530)
      .interactiveDismissDisabled(working)
  }
}
