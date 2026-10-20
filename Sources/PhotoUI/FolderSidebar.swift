import PhotoCore
import SwiftUI

struct FolderSidebar: View {
  let library: FolderLibrary
  let current: URL?
  let open: (URL) -> Void
  let remove: (URL) -> Void
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 3) {
        Text(
          "Photo Home is your starting folder. Expand arrows to browse; click a folder to see its photos."
        )
        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 5)
        if library.roots.isEmpty {
          Text("Open a folder to keep it here. Expand its arrow to browse subfolders.")
            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
        }
        ForEach(library.rows) { row in
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
              Button {
                Task { await library.toggle(row.directory) }
              } label: {
                Image(
                  systemName: library.expanded.contains(row.directory.path)
                    ? "chevron.down" : "chevron.right"
                )
                .font(.caption2).frame(width: 20, height: 28)
              }.buttonStyle(.plain)
                .accessibilityLabel(
                  (library.expanded.contains(row.directory.path) ? "Collapse" : "Expand")
                    + " subfolders of " + row.directory.lastPathComponent
                )
                .help(
                  "Expand or collapse immediate subfolders. Photos load only when you select a folder."
                )
              Button {
                open(row.directory)
              } label: {
                Label(
                  row.directory.lastPathComponent,
                  systemImage: library.home?.path == row.directory.path ? "house" : "folder"
                )
                .lineLimit(1).truncationMode(.middle).frame(
                  maxWidth: .infinity, alignment: .leading)
              }.buttonStyle(.plain)
                .accessibilityLabel(
                  (library.home?.path == row.directory.path ? "Photo Home: " : "")
                    + row.directory.lastPathComponent
                )
                .help(row.directory.path + "\nClick to display this folder's photos.")
              if library.loading.contains(row.directory.path) {
                ProgressView().controlSize(.mini).accessibilityLabel("Loading subfolders")
              }
              if row.isRoot {
                Button {
                  remove(row.root)
                } label: {
                  Image(systemName: "xmark").font(.caption2).frame(width: 22, height: 28)
                }
                .buttonStyle(.plain).accessibilityLabel(
                  "Remove \(row.root.lastPathComponent) from sidebar"
                )
                .help("Remove this shortcut from the sidebar. Files and folders stay on disk.")
              }
            }
            .padding(.leading, CGFloat(min(row.depth, 12)) * 12).padding(.horizontal, 5)
            .background(
              current?.path == row.directory.path ? Color.accentColor.opacity(0.22) : .clear,
              in: RoundedRectangle(cornerRadius: 5))
            if let error = library.errors[row.directory.path] {
              Text(error).font(.caption2).foregroundStyle(.secondary).padding(.leading, 20)
                .lineLimit(3)
            }
          }
          .contextMenu {
            Button("Open Folder") { open(row.directory) }
            Button("Use as Photo Home") { library.setHome(row.directory) }
              .help("Make this your starting folder. Nothing is moved or copied.")
            Button("Refresh Subfolders") { Task { await library.refresh(row.directory) } }
            if row.isRoot { Button("Remove from Sidebar") { remove(row.root) } }
          }
        }
      }
    }.frame(maxHeight: .infinity)
  }
}
