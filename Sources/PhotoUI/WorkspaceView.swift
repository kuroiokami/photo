import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI

private typealias WorkspaceStorage = SwiftUI.State<WorkspaceState>
private typealias BoolStorage = SwiftUI.State<Bool>
private typealias SizeStorage = SwiftUI.State<Double>
private typealias PipelineStorage = SwiftUI.State<ImagePipeline>
private typealias GridFocus = SwiftUI.FocusState<Bool>

private struct GridLayout: Equatable {
  let size: CGSize
  let thumbnailSize: Double
  let showsPreview: Bool
}

public struct WorkspaceView: View {
  @WorkspaceStorage private var workspace: WorkspaceState
  @BoolStorage private var showPreview = true
  @BoolStorage private var choosingFolder = false
  @SizeStorage private var thumbnailSize = 160
  @PipelineStorage private var thumbnails = ImagePipeline(byteLimit: 24 * 1024 * 1024)
  @PipelineStorage private var previews = ImagePipeline(byteLimit: 64 * 1024 * 1024)
  @GridFocus private var gridFocused: Bool

  public init(workspace: WorkspaceState = WorkspaceState()) {
    _workspace = State(initialValue: workspace)
  }

  public var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
    } detail: {
      VStack(spacing: 0) {
        collectionHeader
        Divider()
        HSplitView {
          contactSheet.frame(
            minWidth: 320, idealWidth: 650, maxWidth: .infinity, maxHeight: .infinity)
          if showPreview {
            previewPane.frame(minWidth: 280, idealWidth: 410, maxWidth: .infinity)
          }
        }
        Divider()
        statusBar
      }
      .background(Color(nsColor: .underPageBackgroundColor))
    }
    .preferredColorScheme(.dark)
    .frame(minWidth: 900, minHeight: 600)
    .navigationTitle("Photo")
    .toolbar {
      ToolbarItemGroup {
        Button(action: openFolder) { Label("Open Folder", systemImage: "folder.badge.plus") }
          .disabled(choosingFolder).help("Open Folder (⌘O)")
        Button(action: reload) { Label("Reload", systemImage: "arrow.clockwise") }
          .disabled(workspace.directory == nil).help("Reload Folder (⌘R)")
        Divider()
        Button {
          showPreview.toggle()
        } label: {
          Label("Preview", systemImage: "sidebar.right")
        }
        .help("Show or hide preview (Space)")
      }
    }
    .focusedSceneValue(
      \.workspaceActions,
      WorkspaceActions(
        openFolder: openFolder, reload: reload, canReload: workspace.directory != nil)
    )
    .task(id: workspace.sessionID) {
      // Retain one worker per lane across folders, while invalidating caches.
      let session = workspace.sessionID
      await thumbnails.startSession(session)
      await previews.startSession(session)
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 4) {
        Label("PHOTO", systemImage: "square.grid.2x2.fill")
          .font(.headline).tracking(2)
        Text("A closer look.").font(.caption).foregroundStyle(.secondary)
      }
      .padding(.top, 12)
      Text("COLLECTION").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
      Label(
        workspace.title, systemImage: workspace.directory == nil ? "photo.stack" : "folder.fill"
      )
      .font(.callout.weight(.medium)).lineLimit(2)
      if let directory = workspace.directory {
        Text(directory.path).font(.caption).foregroundStyle(.secondary)
          .textSelection(.enabled).lineLimit(5)
      }
      Button("Open Folder…", action: openFolder).disabled(choosingFolder)
      if workspace.directory != nil {
        Button("Show Sample Collection") {
          workspace.showSamples()
          gridFocused = true
        }
        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .leading, spacing: 7) {
        Label("Originals stay untouched", systemImage: "lock.shield")
        Text("JPEG & PNG · This folder only")
        Text("← → Navigate   Space Preview")
      }
      .font(.caption).foregroundStyle(.secondary)
    }
    .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var collectionHeader: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text(workspace.title).font(.title3.weight(.semibold)).lineLimit(1)
        Text(
          "\(workspace.photos.count) photos · \(workspace.directory == nil ? "Bundled samples" : "Filename order")"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Image(systemName: "square.grid.3x3").foregroundStyle(.secondary)
      Slider(value: $thumbnailSize, in: 110...240, step: 10)
        .frame(width: 100).accessibilityLabel("Thumbnail size")
    }
    .padding(.horizontal, 20).padding(.vertical, 14)
  }

  private var contactSheet: some View {
    GeometryReader { geometry in
      let columns = max(1, Int((geometry.size.width - 32) / (thumbnailSize + 16)))
      Group {
        switch workspace.loadState {
        case .loading:
          VStack(spacing: 12) {
            ProgressView()
            Text("Reading folder…").foregroundStyle(.secondary)
          }
        case .failed(let message):
          ContentUnavailableView {
            Label("Folder unavailable", systemImage: "folder.badge.questionmark")
          } description: {
            Text(message)
          } actions: {
            Button("Reload Folder", action: reload)
            Button("Choose Another Folder…", action: openFolder)
          }
        case .ready where workspace.photos.isEmpty:
          ContentUnavailableView {
            Label("No JPEG or PNG images", systemImage: "photo.on.rectangle")
          } description: {
            Text(
              "Choose a folder with JPEG or PNG files. Subfolders and hidden files are not included."
            )
          } actions: {
            Button("Open Folder…", action: openFolder)
          }
        case .ready:
          ScrollViewReader { proxy in
            ScrollView {
              LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
                spacing: 16
              ) {
                ForEach(workspace.photos) { photo in
                  thumbnail(photo)
                    .id(photo.id)
                }
              }
              .padding(16)
            }
            .onAppear {
              if let id = workspace.selectedID { proxy.scrollTo(id) }
            }
            .onChange(of: workspace.selectedID) {
              if let id = workspace.selectedID { proxy.scrollTo(id) }
            }
            .task(
              id: GridLayout(
                size: geometry.size, thumbnailSize: thumbnailSize, showsPreview: showPreview)
            ) {
              // Lazy-grid positions settle after pane/density reflow. Coalesce
              // intermediate layouts, then reveal the current selection once.
              do {
                try await Task.sleep(for: .milliseconds(50))
                try Task.checkCancellation()
                if let id = workspace.selectedID { proxy.scrollTo(id, anchor: .center) }
              } catch {}
            }
          }
          .id(workspace.sessionID)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .focusable().focused($gridFocused).focusEffectDisabled()
      .onKeyPress(.leftArrow) {
        workspace.moveSelection(by: -1)
        return .handled
      }
      .onKeyPress(.rightArrow) {
        workspace.moveSelection(by: 1)
        return .handled
      }
      .onKeyPress(.upArrow) {
        workspace.moveSelection(by: -columns)
        return .handled
      }
      .onKeyPress(.downArrow) {
        workspace.moveSelection(by: columns)
        return .handled
      }
      .onKeyPress(.space) {
        showPreview.toggle()
        return .handled
      }
      .onKeyPress(.home) {
        workspace.moveSelection(by: Int.min)
        return .handled
      }
      .onKeyPress(.end) {
        workspace.moveSelection(by: Int.max)
        return .handled
      }
      .task(id: workspace.loadState) {
        gridFocused = false
        await Task.yield()
        guard !Task.isCancelled else { return }
        gridFocused = true
      }
      .onKeyPress(.escape) {
        showPreview = false
        return .handled
      }
    }
  }

  private func thumbnail(_ photo: PhotoItem) -> some View {
    let selected = workspace.selectedID == photo.id
    return Button {
      workspace.select(photo.id)
      gridFocused = true
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        PhotoImageView(
          photo: photo, pipeline: thumbnails, maximumPixelSize: 480, sessionID: workspace.sessionID
        )
        .frame(height: thumbnailSize * 0.7)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        Text(photo.filename).font(.caption).lineLimit(1).truncationMode(.middle)
          .foregroundStyle(selected ? Color.white : Color.secondary)
      }
      .padding(8)
      .background(
        selected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.025),
        in: RoundedRectangle(cornerRadius: 7)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7).strokeBorder(
          selected ? Color.accentColor : .clear, lineWidth: 2)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).help(photo.filename)
    .accessibilityLabel("Select \(photo.filename)")
    .accessibilityAddTraits(selected ? .isSelected : [])
    .simultaneousGesture(TapGesture(count: 2).onEnded { showPreview = true })
  }

  private var previewPane: some View {
    VStack(spacing: 0) {
      HStack {
        Text("PREVIEW").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        Spacer()
        Button {
          showPreview = false
          gridFocused = true
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.plain).accessibilityLabel("Close preview")
      }.padding(16)
      if let photo = workspace.selectedPhoto {
        PhotoImageView(
          photo: photo, pipeline: previews, maximumPixelSize: 2560, detailed: true,
          sessionID: workspace.sessionID
        )
        .id("\(workspace.sessionID)-\(photo.id)")
        .padding(.horizontal, 16)
        VStack(spacing: 8) {
          Text(photo.filename).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
          HStack {
            Button {
              workspace.moveSelection(by: -1)
              gridFocused = true
            } label: {
              Image(systemName: "chevron.left")
            }
            .disabled(workspace.selectedIndex == 0).accessibilityLabel("Previous photo")
            Text("\((workspace.selectedIndex ?? 0) + 1) of \(workspace.photos.count)")
              .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 80)
            Button {
              workspace.moveSelection(by: 1)
              gridFocused = true
            } label: {
              Image(systemName: "chevron.right")
            }
            .disabled(workspace.selectedIndex == workspace.photos.count - 1).accessibilityLabel(
              "Next photo")
          }.buttonStyle(.borderless)
        }.padding(16)
      } else {
        ContentUnavailableView("Select a photo", systemImage: "photo")
      }
    }
    .frame(maxHeight: .infinity)
    .background(Color.black.opacity(0.2))
  }

  private var statusBar: some View {
    HStack {
      Label(
        workspace.directory == nil ? "Sample collection" : "Read-only browsing",
        systemImage: "checkmark.shield")
      Spacer()
      Text(workspace.selectedPhoto?.filename ?? "No selection").lineLimit(1)
      Text("·  \(workspace.photos.count) photos")
    }
    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 9)
  }

  private func openFolder() {
    guard !choosingFolder else { return }
    choosingFolder = true
    let panel = NSOpenPanel()
    panel.title = "Open Photo Folder"
    panel.prompt = "Open Folder"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    let completion: (NSApplication.ModalResponse) -> Void = { response in
      choosingFolder = false
      guard response == .OK, let url = panel.url else {
        Task {
          gridFocused = false
          await Task.yield()
          gridFocused = true
        }
        return
      }
      Task {
        await workspace.openFolder(url)
        gridFocused = true
      }
    }
    if let window = NSApp.keyWindow {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else {
      panel.begin(completionHandler: completion)
    }
  }

  private func reload() {
    guard let directory = workspace.directory else { return }
    Task {
      await workspace.openFolder(directory)
      gridFocused = true
    }
  }
}
