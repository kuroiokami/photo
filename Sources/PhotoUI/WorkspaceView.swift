import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI
import UniformTypeIdentifiers

private typealias WorkspaceStorage = SwiftUI.State<WorkspaceState>
private typealias WorkflowModelStorage = SwiftUI.State<WorkflowModel>
private typealias BoolStorage = SwiftUI.State<Bool>
private typealias ColumnStorage = SwiftUI.State<Int>
private typealias SizeStorage = SwiftUI.State<Double>
private typealias PipelineStorage = SwiftUI.State<ImagePipeline>
private typealias DetailPipelineStorage = SwiftUI.State<DetailPipeline>
private typealias TileFramesStorage = SwiftUI.State<[String: CGRect]>
private typealias MarqueeStorage = SwiftUI.State<SelectionMarquee?>
private typealias FolderLibraryStorage = SwiftUI.State<FolderLibrary>
private typealias GridFocus = SwiftUI.FocusState<Bool>

private struct GridLayout: Equatable {
  let size: CGSize
  let thumbnailSize: Double
  let showsPreview: Bool
}

public struct WorkspaceView: View {
  @FolderLibraryStorage private var folderLibrary = FolderLibrary()
  @WorkspaceStorage private var workspace: WorkspaceState
  @WorkflowModelStorage private var workflowModel: WorkflowModel
  @BoolStorage private var showPreview = true
  @BoolStorage private var choosingFolder = false
  @ColumnStorage private var gridColumns = 1
  @SizeStorage private var thumbnailSize = 160
  @PipelineStorage private var thumbnails = ImagePipeline(byteLimit: 24 * 1024 * 1024)
  @PipelineStorage private var previews = ImagePipeline(byteLimit: 64 * 1024 * 1024)
  @DetailPipelineStorage private var detailPipeline = DetailPipeline()
  @GridFocus private var gridFocused: Bool
  @BoolStorage private var showInspector = false
  @BoolStorage private var showingWorkflow = false
  @BoolStorage private var showingHelp = false
  @TileFramesStorage private var tileFrames: [String: CGRect] = [:]
  @MarqueeStorage private var marquee: SelectionMarquee?
  private let metadataReader = ImageMetadataReader()

  public init(workspace: WorkspaceState = WorkspaceState()) {
    _workspace = State(initialValue: workspace)
    _workflowModel = State(initialValue: WorkflowModel(workspace: workspace))
  }

  public var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
    } detail: {
      VStack(spacing: 0) {
        collectionHeader
        filterBar
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
        Button {
          showingWorkflow = true
        } label: {
          Label("Workflow…", systemImage: "arrow.triangle.branch")
        }
        .labelStyle(.titleOnly).disabled(choosingFolder).help(
          "Ingest, bulk rename, IPTC/keywords and Lightroom handoff.")
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
    .sheet(isPresented: $showingHelp) { CullingHelpView() }
    .task {
      if workspace.directory == nil, let saved = folderLibrary.selected {
        await workspace.openFolder(saved)
      }
      await folderLibrary.restoreExpanded()
    }
    .onChange(of: workspace.directory) {
      if let folder = workspace.directory { folderLibrary.rememberIfUncovered(folder) }
    }
    .sheet(isPresented: $showingWorkflow) { WorkflowView(model: workflowModel) }
    .focusedSceneValue(
      \.workspaceActions,
      WorkspaceActions(
        workspace: workspace,
        canDecide: !choosingFolder && !showingWorkflow && !showingHelp
          && (!workflowModel.busy || workflowModel.backgroundable), columns: gridColumns,
        togglePreview: { showPreview.toggle() }, hidePreview: { showPreview = false },
        openFolder: openFolder, reload: reload,
        workflow: showWorkflow, help: { showingHelp = true },
        canReload: workspace.directory != nil && !choosingFolder && !showingWorkflow && !showingHelp
      )
    )
    .task(id: workspace.sessionID) {
      // Retain one worker per lane across folders, while invalidating caches.
      let session = workspace.sessionID
      await thumbnails.startSession(session)
      await previews.startSession(session)
    }
    .task(id: "\(workspace.sessionID)-\(workspace.loadState)") {
      guard workspace.loadState == .ready else { return }
      let session = workspace.sessionID
      async let metadata: Void = workspace.indexMetadata(
        using: metadataReader, expectedSession: session)
      async let decisions: Void = workspace.loadDecisions(expectedSession: session)
      _ = await (metadata, decisions)
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
      Text("FOLDERS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
      FolderSidebar(
        library: folderLibrary, current: workspace.directory, open: browse,
        remove: { folder in
          folderLibrary.remove(folder)
          if folderLibrary.selected == nil { workspace.showSamples() }
        })
      Button("Open Folder…", action: openFolder).disabled(choosingFolder)
      Button("Workflow…") { showingWorkflow = true }
        .help("Ingest, bulk rename, IPTC/keywords and Lightroom handoff.")
      if workspace.directory != nil {
        Button("Show Sample Collection") {
          workspace.showSamples()
          gridFocused = true
        }
        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
      }
      Button("Quick Start & Shortcuts") { showingHelp = true }.font(.caption)
      VStack(alignment: .leading, spacing: 7) {
        Label("Originals stay untouched", systemImage: "lock.shield")
        Text("JPEG · PNG · Sony · Canon · Olympus RAW")
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
          "\(workspace.photos.count) of \(workspace.totalCount) photos"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Picker(
        "Sort",
        selection: Binding(
          get: { workspace.sort },
          set: { sort in
            Task { await workspace.setSort(sort) }
          })
      ) {
        ForEach(PhotoSort.allCases, id: \.self) {
          Text($0.rawValue).tag($0)
        }
      }.frame(width: 160)
      if workspace.indexing {
        Text("EXIF \(workspace.indexedCount)/\(workspace.photos.count)")
          .font(.caption).foregroundStyle(.secondary)
      }
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
        case .ready where workspace.photos.isEmpty && workspace.decisionsLoading:
          ProgressView("Reading culling decisions…")
        case .ready where workspace.photos.isEmpty && workspace.totalCount > 0:
          ContentUnavailableView {
            Label("No photos match these filters", systemImage: "line.3.horizontal.decrease.circle")
          } description: {
            Text("Clear the flag and star filters to see all photos in this folder.")
          } actions: {
            Button("Clear Filters") { workspace.setFilter(.all, minimumRating: 0) }
          }
        case .ready where workspace.photos.isEmpty:
          ContentUnavailableView {
            Label("No supported images", systemImage: "photo.on.rectangle")
          } description: {
            Text(
              "Choose a folder with JPEG, PNG, or Sony/Canon/Olympus RAW files. Expand a sidebar folder and click a subfolder to browse its photos. Hidden files are not included."
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
                    .background(
                      GeometryReader { tile in
                        Color.clear.preference(
                          key: PhotoTileFrames.self,
                          value: [photo.id: tile.frame(in: .named("ContactSheetViewport"))])
                      })
                }
              }
              .padding(16)
            }
            .coordinateSpace(name: "ContactSheetViewport")
            .onPreferenceChange(PhotoTileFrames.self) { tileFrames = $0 }
            .simultaneousGesture(
              DragGesture(minimumDistance: 5)
                .onChanged { value in
                  if marquee == nil {
                    let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                    marquee = SelectionMarquee(
                      start: value.startLocation, end: value.location,
                      base: modifiers.contains(.command) || modifiers.contains(.shift)
                        ? workspace.selectedIDs : [])
                  }
                  marquee?.end = value.location
                  guard let marquee else { return }
                  let viewport = CGRect(origin: .zero, size: geometry.size)
                  let hits = Set(
                    tileFrames.filter {
                      viewport.intersects($0.value) && marquee.rectangle.intersects($0.value)
                    }.keys)
                  workspace.selectGroup(marquee.base.union(hits))
                }.onEnded { _ in
                  marquee = nil
                  gridFocused = true
                }
            )
            .overlay(alignment: .topLeading) {
              if let marquee {
                Rectangle().fill(Color.accentColor.opacity(0.12))
                  .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                  .frame(width: marquee.rectangle.width, height: marquee.rectangle.height)
                  .offset(x: marquee.rectangle.minX, y: marquee.rectangle.minY)
                  .allowsHitTesting(false)
              }
            }.clipped()
            .onAppear {
              if let id = workspace.selectedID { proxy.scrollTo(id) }
            }
            .onChange(of: workspace.selectedID) {
              guard marquee == nil else { return }
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
          .onChange(of: workspace.sessionID) {
            tileFrames = [:]
            marquee = nil
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: columns, initial: true) { gridColumns = columns }
      .focusable().focused($gridFocused).focusEffectDisabled()
      .onKeyPress(.leftArrow, phases: .down) { press in
        workspace.moveSelection(by: -1, extending: press.modifiers.contains(.shift))
        return .handled
      }
      .onKeyPress(.rightArrow, phases: .down) { press in
        workspace.moveSelection(by: 1, extending: press.modifiers.contains(.shift))
        return .handled
      }
      .onKeyPress(.upArrow, phases: .down) { press in
        workspace.moveSelection(by: -columns, extending: press.modifiers.contains(.shift))
        return .handled
      }
      .onKeyPress(.downArrow, phases: .down) { press in
        workspace.moveSelection(by: columns, extending: press.modifiers.contains(.shift))
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
    let selected = workspace.selectedIDs.contains(photo.id)
    let decision = workspace.decisions[photo.id] ?? CullingDecision()
    return Button {
      let modifiers = NSApp.currentEvent?.modifierFlags ?? []
      workspace.selectMultiple(
        photo.id, extending: modifiers.contains(.command), range: modifiers.contains(.shift))
      gridFocused = true
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        PhotoImageView(
          photo: photo, pipeline: thumbnails, maximumPixelSize: 480, sessionID: workspace.sessionID
        )
        .frame(height: thumbnailSize * 0.7)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        HStack(spacing: 4) {
          Image(systemName: decision.flag.symbol).accessibilityLabel(decision.flag.title)
          Text(
            String(repeating: "★", count: decision.rating)
              + String(repeating: "☆", count: 5 - decision.rating)
          )
          .accessibilityLabel("\(decision.rating) stars")
        }.font(.caption2).foregroundStyle(.secondary)
        if workspace.groupPairs, workspace.pairedCount(photo) > 1 {
          Text("RAW + JPEG").font(.caption2).foregroundStyle(.secondary)
        }
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
    .buttonStyle(.plain).help(
      photo.filename
        + "\nClick to select; ⌘-click adds/removes; Shift-click selects a range. P/X/U flags the selection."
    )
    .contextMenu {
      ForEach([PhotoFlag.pick, .reject, .unflagged], id: \.self) { flag in
        Button(flag.title + " Selection") {
          if !workspace.selectedIDs.contains(photo.id) {
            workspace.selectMultiple(photo.id, extending: false, range: false)
          }
          workspace.applyDecision(flag: flag)
        }.disabled(
          !workspace.decisionsReady.contains(photo.id)
            || (selected && !workspace.decisionSelectionReady))
      }
      Divider()
      Button("Edit IPTC & Keywords…") {
        if !workspace.selectedIDs.contains(photo.id) {
          workspace.selectMultiple(photo.id, extending: false, range: false)
        }
        showWorkflow(2)
      }
    }
    .accessibilityLabel("Select \(photo.filename)")
    .accessibilityValue("\(decision.flag.title), \(decision.rating) stars")
    .accessibilityAddTraits(selected ? .isSelected : [])
    .simultaneousGesture(TapGesture(count: 2).onEnded { showPreview = true })
  }

  private var previewPane: some View {
    VStack(spacing: 0) {
      HStack {
        Text("PREVIEW").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        Spacer()
        Button {
          showInspector.toggle()
        } label: {
          Image(systemName: "info.circle")
        }
        .buttonStyle(.plain).accessibilityLabel("Show shooting information")
        .help("Show or hide camera, lens, capture time and image dimensions.")
        Button {
          showPreview = false
          gridFocused = true
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.plain).accessibilityLabel("Close preview").help(
          "Hide preview (Space or Escape).")
      }.padding(16)
      if let photo = workspace.selectedPhoto {
        DetailPreviewView(
          photo: photo, pipeline: previews, detailPipeline: detailPipeline,
          sessionID: workspace.sessionID
        )
        .id("\(workspace.sessionID)-\(photo.id)")
        .padding(.horizontal, 16)
        VStack(spacing: 8) {
          decisionControls(photo)
          if let metadata = workspace.metadata[photo.id] {
            Text(metadata.shootingSummary).font(.caption.monospacedDigit()).foregroundStyle(
              .secondary)
            if showInspector {
              VStack(alignment: .leading, spacing: 4) {
                Text(metadata.camera ?? "Camera unavailable")
                Text(metadata.lens ?? "Lens unavailable")
                Text(metadata.captureTimeText ?? "Capture time unavailable")
                Text(
                  metadata.focalLength.map { "\($0.formatted()) mm" } ?? "Focal length unavailable")
                Text("\(metadata.pixelWidth) × \(metadata.pixelHeight)")
              }.font(.caption).textSelection(.enabled)
            }
          }
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

  private var filterBar: some View {
    VStack(alignment: .leading, spacing: 8) {
      ViewThatFits(in: .horizontal) {
        HStack {
          filters
          selectionTools
          Spacer(minLength: 0)
          autoAdvance
        }
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            filters
            Spacer(minLength: 0)
          }
          HStack {
            selectionTools
            Spacer(minLength: 0)
            autoAdvance
          }
        }
      }
      HStack {
        ForEach([PhotoFlag.pick, .reject, .unflagged], id: \.self) { flag in
          Button {
            workspace.applyDecision(flag: flag)
          } label: {
            Label(
              flag == .unflagged ? "Clear Flags" : flag.title + " Selection",
              systemImage: flag.symbol)
          }.disabled(!workspace.decisionSelectionReady)
            .help(
              "Apply to all selected files, preserving stars. P picks, X rejects, U clears flags. Reject never deletes files."
            )
        }
        Button("Edit Selected IPTC…") { showWorkflow(2) }.disabled(workspace.selectedIDs.isEmpty)
          .help("Edit one field or review several checked fields across the selection.")
        Spacer(minLength: 0)
      }
    }.font(.caption).padding(.horizontal, 20).padding(.bottom, 10)
  }
  private var filters: some View {
    HStack {
      Picker(
        "Flags",
        selection: Binding(
          get: { workspace.flagFilter },
          set: {
            workspace.setFilter($0, minimumRating: workspace.minimumRating)
          })
      ) {
        ForEach(FlagFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.frame(width: 150).help("Filter photos by their pick/reject flag.")
      Picker(
        "Stars",
        selection: Binding(
          get: { workspace.minimumRating },
          set: {
            workspace.setFilter(workspace.flagFilter, minimumRating: $0)
          })
      ) {
        Text("All stars").tag(0)
        ForEach(1...5, id: \.self) { Text("\($0)★ or more").tag($0) }
      }.frame(width: 150).help("Show photos with at least this many stars.")
      Button("Clear Filters") { workspace.setFilter(.all, minimumRating: 0) }
        .disabled(workspace.flagFilter == .all && workspace.minimumRating == 0)
    }.fixedSize(horizontal: true, vertical: false)
  }
  private var selectionTools: some View {
    HStack {
      Toggle(
        "RAW+JPEG", isOn: Binding(get: { workspace.groupPairs }, set: { workspace.setGrouping($0) })
      )
      .toggleStyle(.checkbox).help(
        "Show each unique RAW+JPEG pair once. Decisions and metadata target both files.")
      Button("Select All") { workspace.selectAllVisible() }.disabled(workspace.photos.isEmpty)
        .help("Select every visible photo (⌘A). Filters limit this selection.")
      Text("\(workspace.selectedIDs.count) selected").monospacedDigit()
    }.fixedSize(horizontal: true, vertical: false)
  }
  private var autoAdvance: some View {
    Toggle(
      "Auto-advance",
      isOn: Binding(get: { workspace.autoAdvance }, set: { workspace.autoAdvance = $0 })
    )
    .toggleStyle(.checkbox).fixedSize()
    .help(
      "Advance after single-photo decisions. Shift also advances. Group decisions keep the selection."
    )
  }

  private func decisionControls(_ photo: PhotoItem) -> some View {
    let summary = workspace.selectionSummary
    return VStack(spacing: 8) {
      if summary.fileCount > 1 {
        Text(
          "Editing \(summary.fileCount) files" + (summary.flag == nil ? " · Mixed flags" : "")
            + (summary.rating == nil ? " · Mixed stars" : "")
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      HStack(spacing: 4) {
        ForEach([PhotoFlag.pick, .reject, .unflagged], id: \.self) { flag in
          Button {
            workspace.applyDecision(flag: flag)
            gridFocused = true
          } label: {
            Image(systemName: flag.symbol)
              .foregroundStyle(summary.flag == flag ? Color.accentColor : Color.secondary)
          }.frame(minWidth: 22, minHeight: 26)
            .help((flag == .unflagged ? "Clear flags" : flag.title) + " for all selected files.")
            .accessibilityLabel(flag == .unflagged ? "Clear flags" : flag.title)
        }
        Divider().frame(height: 16)
        ForEach(1...5, id: \.self) { rating in
          Button {
            workspace.applyDecision(rating: rating)
            gridFocused = true
          } label: {
            Image(systemName: rating <= (summary.rating ?? 0) ? "star.fill" : "star")
          }
          .accessibilityLabel("Set \(rating) stars")
          .frame(minWidth: 22, minHeight: 26)
          .help("Set \(rating) stars for all selected files (\(rating)). Flags are preserved.")
          .accessibilityValue(
            summary.rating == nil
              ? "Mixed ratings" : rating <= (summary.rating ?? 0) ? "Selected" : "Not selected")
        }
        Button("0") {
          workspace.applyDecision(rating: 0)
          gridFocused = true
        }.frame(minWidth: 22, minHeight: 26).help(
          "Clear stars for all selected files (0). Flags are preserved.")
      }.buttonStyle(.borderless).disabled(!workspace.decisionSelectionReady)
      if let status = workspace.saveStatus[photo.id], status != "Saved", photo.fileURL != nil {
        Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        HStack {
          if status.hasPrefix("XMP conflict") {
            Button("Use My Decisions") { workspace.retrySync(useLocal: true) }
            Button("Use External Decisions") { Task { await workspace.useExternalDecision() } }
          } else if status != "Saving…" {
            Button("Retry XMP Sync") { workspace.retrySync() }
          }
        }.font(.caption)
      }
    }
  }

  private var statusBar: some View {
    HStack {
      if workflowModel.busy {
        ProgressView().controlSize(.small)
        Button("Workflow…") { showingWorkflow = true }
        Text(workflowModel.status).lineLimit(1)
      }
      Label(
        workspace.selectedID.flatMap { workspace.saveStatus[$0] } ?? "Originals stay untouched",
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
    panel.allowedContentTypes = [.folder]
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
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
      folderLibrary.add(url)
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

  private func showWorkflow(_ tab: Int) {
    workflowModel.requestedTab = tab
    showingWorkflow = true
  }

  private func browse(_ folder: URL) {
    folderLibrary.select(folder)
    Task {
      await workspace.openFolder(folder)
      gridFocused = true
    }
  }

  private func reload() {
    guard let directory = workspace.directory else { return }
    Task {
      await workspace.openFolder(directory)
      if folderLibrary.expanded.contains(directory.path) { await folderLibrary.refresh(directory) }
      gridFocused = true
    }
  }
}
