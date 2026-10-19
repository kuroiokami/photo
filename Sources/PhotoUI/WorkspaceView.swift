import PhotoCore
import SwiftUI

// Resolve the property wrapper explicitly: newer SDKs also export a State macro.
private typealias WorkspaceStorage = SwiftUI.State<WorkspaceState>

public struct WorkspaceView: View {
  @WorkspaceStorage private var workspace: WorkspaceState

  public init(workspace: WorkspaceState = WorkspaceState()) {
    _workspace = State(initialValue: workspace)
  }

  public var body: some View {
    NavigationSplitView {
      List {
        Label("Sample collection", systemImage: "photo.on.rectangle.angled")
        Text("\(workspace.photos.count) synthetic images").font(.caption).foregroundStyle(
          .secondary)
      }
      .navigationTitle("Photo")
      .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    } detail: {
      VStack(spacing: 0) {
        preview
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(24)
        Divider()
        ScrollView(.horizontal) {
          HStack(spacing: 12) {
            ForEach(workspace.photos) { photo in
              Button {
                workspace.select(photo.id)
              } label: {
                VStack(spacing: 8) {
                  sampleImage(photo)
                    .scaledToFit()
                    .frame(width: 140, height: 90)
                  Text(photo.filename).font(.caption)
                }
                .padding(8)
                .background(
                  workspace.selectedID == photo.id
                    ? Color.accentColor.opacity(0.18) : Color.clear,
                  in: RoundedRectangle(cornerRadius: 8)
                )
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Select \(photo.filename)")
              .accessibilityAddTraits(workspace.selectedID == photo.id ? .isSelected : [])
            }
          }
          .padding(16)
        }
        Divider()
        HStack {
          Text("Sample workspace • Original files are never modified")
          Spacer()
          Text("\(workspace.photos.count) photos")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
      }
      .navigationTitle(workspace.selectedPhoto?.filename ?? "Photo")
      .toolbar {
        Button("Previous", systemImage: "chevron.left") { workspace.moveSelection(by: -1) }
          .keyboardShortcut(.leftArrow, modifiers: [])
          .disabled(workspace.selectedPhoto == nil)
        Button("Next", systemImage: "chevron.right") { workspace.moveSelection(by: 1) }
          .keyboardShortcut(.rightArrow, modifiers: [])
          .disabled(workspace.selectedPhoto == nil)
      }
    }
    .frame(minWidth: 800, minHeight: 560)
  }

  @ViewBuilder
  private var preview: some View {
    if let photo = workspace.selectedPhoto {
      sampleImage(photo).scaledToFit().accessibilityLabel("Preview of \(photo.filename)")
    } else {
      ContentUnavailableView("No photo selected", systemImage: "photo")
    }
  }

  private func sampleImage(_ photo: PhotoItem) -> Image {
    if let image = SampleResources.image(for: photo) {
      return Image(nsImage: image).resizable()
    }
    return Image(systemName: "photo").resizable()
  }
}
