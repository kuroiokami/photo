import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI
import UniformTypeIdentifiers

private typealias LayoutStorage = SwiftUI.State<WorkspaceLayout>
private typealias WorkspaceStorage = SwiftUI.State<WorkspaceState>
private typealias ThumbnailLabelsStorage = SwiftUI.State<[ThumbnailInfoField]>
private typealias ComparisonStorage = SwiftUI.State<ComparisonSession>
private typealias WorkflowModelStorage = SwiftUI.State<WorkflowModel>
private typealias BoolStorage = SwiftUI.State<Bool>
private typealias ColumnStorage = SwiftUI.State<Int>
private typealias SizeStorage = SwiftUI.State<Double>
private typealias QuickPreviewStorage = SwiftUI.State<QuickPreviewState>
private typealias ImageSessionStorage = SwiftUI.State<UUID?>
private typealias PipelineStorage = SwiftUI.State<ImagePipeline>
private typealias DetailPipelineStorage = SwiftUI.State<DetailPipeline>
private typealias TileFramesStorage = SwiftUI.State<PhotoTileGeometry>
private typealias MarqueeStorage = SwiftUI.State<SelectionMarquee?>
private typealias FolderLibraryStorage = SwiftUI.State<FolderLibrary>
private typealias CropPhotoStorage = SwiftUI.State<PhotoItem?>
private typealias CropClipboardStorage = SwiftUI.State<PhotoCrop?>
private typealias GestureSizeStorage = SwiftUI.State<Double?>
private typealias TrashPlanStorage = SwiftUI.State<PhotoTrashPlan?>
private typealias MessageStorage = SwiftUI.State<String>
private typealias GridFocus = SwiftUI.FocusState<Bool>

private struct SelectionReveal: Equatable {
  let id: String?
  let index: Int?
}

private struct GridLayout: Equatable {
  let size: CGSize
  let thumbnailSize: Double
  let showsPreview: Bool
}

public struct WorkspaceView: View {
  @ThumbnailLabelsStorage private var thumbnailLabels = ThumbnailInfoField.restored(
    UserDefaults.standard.stringArray(forKey: "Photo.thumbnailLabels") ?? [])
  @ComparisonStorage private var comparison = ComparisonSession()
  @DetailPipelineStorage private var referenceDetails = DetailPipeline()
  @FolderLibraryStorage private var folderLibrary = FolderLibrary()
  @LayoutStorage private var layout = WorkspaceLayout()
  @QuickPreviewStorage private var quickPreview = QuickPreviewState()
  @BoolStorage private var showingFilters = false
  @BoolStorage private var showingOptions = false
  @WorkspaceStorage private var workspace: WorkspaceState
  @WorkflowModelStorage private var workflowModel: WorkflowModel
  @BoolStorage private var showPreview = true
  @BoolStorage private var choosingFolder = false
  @ColumnStorage private var gridColumns = 1
  @ColumnStorage private var thumbnailCacheGeneration = 0
  @SizeStorage private var thumbnailSize = 160
  @SizeStorage private var filmstripSize = 84
  @PipelineStorage private var thumbnails = ImagePipeline(
    byteLimit: ThumbnailCachePolicy.memoryByteLimit(), thumbnailDiskCache: .standard,
    maximumConcurrentLoads: 2)
  @PipelineStorage private var previews = ImagePipeline(
    byteLimit: 64 * 1024 * 1024, preparesNearby: true)
  @ImageSessionStorage private var readyImageSession: UUID?
  @DetailPipelineStorage private var detailPipeline = DetailPipeline()
  @GridFocus private var gridFocused: Bool
  @GridFocus private var previewFocused: Bool
  @BoolStorage private var showInspector = false
  @BoolStorage private var showingWorkflow = false
  @BoolStorage private var showingHelp = false
  @TileFramesStorage private var tileGeometry = PhotoTileGeometry()
  @CropPhotoStorage private var croppingPhoto: PhotoItem?
  @CropClipboardStorage private var copiedCrop: PhotoCrop?
  @GestureSizeStorage private var pinchSize: Double?
  @MarqueeStorage private var marquee: SelectionMarquee?
  @TrashPlanStorage private var trashPlan: PhotoTrashPlan?
  @BoolStorage private var preparingTrash = false
  @BoolStorage private var showingTrashError = false
  @BoolStorage private var pendingInspection = false
  @MessageStorage private var trashNotice = ""
  private var metadataReader: ImageMetadataReader { workflowModel.metadataReader }

  public init(workspace: WorkspaceState = WorkspaceState()) {
    _workspace = State(initialValue: workspace)
    _workflowModel = State(initialValue: WorkflowModel(workspace: workspace))
  }

  private var canvasMeasured: ((CGSize) -> Void)? = nil
  init(
    workspace: WorkspaceState, layout: WorkspaceLayout, canvasMeasured: @escaping (CGSize) -> Void
  ) {
    _workspace = State(initialValue: workspace)
    _workflowModel = State(initialValue: WorkflowModel(workspace: workspace))
    _layout = State(initialValue: layout)
    self.canvasMeasured = canvasMeasured
  }

  public var body: some View {
    workspacePresentation
      .overlay {
        WorkspaceRegion {
          if quickPreview.visible, quickPreviewAllowed, let photo = workspace.selectedPhoto {
            QuickPreviewOverlay(
              photo: photo, edit: workspace.imageEdits[photo.id] ?? PhotoEdit(),
              pipeline: previews, session: workspace.sessionID, close: { quickPreview.dismiss() },
              inspect: toggleInspection)
          }
        }
      }
      .background(
        QuickPreviewKeys(state: quickPreview, allowed: quickPreviewAllowed)
          .frame(width: 0, height: 0).accessibilityHidden(true)
      )
      .onChange(of: quickPreviewAllowed) { if !quickPreviewAllowed { quickPreview.dismiss() } }
      .onChange(of: workspace.sessionID) { quickPreview.dismiss() }
      .focusedSceneValue(\.workspaceActions, sceneActions)
      .task(id: workspace.sessionID) {
        // Retain the bounded thumbnail pool and separate Fit lane across folders.
        let session = workspace.sessionID
        await thumbnails.startSession(session)
        await previews.startSession(session)
        guard !Task.isCancelled, workspace.sessionID == session else { return }
        readyImageSession = session
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

  private var quickPreviewAllowed: Bool {
    readyImageSession == workspace.sessionID && workspace.selectedPhoto != nil
      && !choosingFolder && !showingWorkflow && !showingHelp && croppingPhoto == nil
      && trashPlan == nil && !preparingTrash && !showingOptions && !showingFilters
  }

  private var workspaceShell: some View {
    NavigationSplitView(columnVisibility: $layout.sidebar) {
      sidebar
        .disabled(showingWorkflow || preparingTrash || trashPlan != nil)
        .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 320)
    } detail: {
      ZStack {
        browsingContent
          .opacity(showingWorkflow ? 0 : 1)
          .allowsHitTesting(!showingWorkflow)
          .accessibilityHidden(showingWorkflow)
        if showingWorkflow {
          WorkflowView(model: workflowModel) {
            showingWorkflow = false
            gridFocused = true
          }
          .background(Color(nsColor: .windowBackgroundColor))
        }
      }
    }
    .preferredColorScheme(.dark)
    .frame(minWidth: 900, minHeight: 600)
    .navigationTitle("Photo")
    .toolbar {
      ToolbarItemGroup {
        Button {
          showWorkflow(workflowModel.requestedTab)
        } label: {
          Label("Workflow…", systemImage: "arrow.triangle.branch")
        }
        .labelStyle(.titleOnly).disabled(choosingFolder || preparingTrash || trashPlan != nil).help(
          "Copy from a card, rename, add captions and keywords, and prepare delivery copies.")
        Button(action: openFolder) { Label("Open Folder", systemImage: "folder.badge.plus") }
          .disabled(choosingFolder || showingWorkflow || preparingTrash || trashPlan != nil).help(
            "Open Folder (⌘O)")
        Button(action: reload) { Label("Reload", systemImage: "arrow.clockwise") }
          .disabled(
            workspace.directory == nil || showingWorkflow || preparingTrash || trashPlan != nil
          ).help("Reload Folder (⌘R)")
        Divider()
        Button(action: toggleFocus) {
          Label(
            layout.focused ? "Exit Focus" : "Focus on Photo",
            systemImage: layout.focused
              ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }.disabled(workspace.selectedPhoto == nil || showingWorkflow)
          .help(
            "Give the photo the window: hide browsing controls, sidebar and filmstrip (⇧⌘F). Press Escape to return."
          )

      }
    }
  }

  private var workspaceLoadHandlers: some View {
    workspaceShell
      .sheet(item: $croppingPhoto) { photo in
        CropEditor(
          photo: photo, edit: workspace.imageEdits[photo.id] ?? PhotoEdit(), pipeline: previews,
          sessionID: workspace.sessionID
        ) { crop in workspace.setCrop(crop, for: photo) }
      }
      .sheet(isPresented: $showingHelp) { CullingHelpView() }
      .task {
        if workspace.directory == nil, let saved = folderLibrary.selected {
          await workflowModel.openFolder(saved)
        }
        await folderLibrary.restoreExpanded()
      }
      .onReceive(NotificationCenter.default.publisher(for: .photoSourceReviewChanged)) { _ in
        if !workspace.isSourceReview, let directory = workspace.directory {
          let session = workspace.sessionID
          Task {
            let needsReload =
              workspace.includesSubfolders
              ? true : (try? await workspace.persistence.sourceReview(for: directory)) != nil
            if needsReload, workspace.sessionID == session {
              await workflowModel.openFolder(directory)
            }
          }
        }
      }
      .onChange(of: workspace.directory) {
        trashNotice = ""
        if let folder = workspace.directory { folderLibrary.rememberIfUncovered(folder) }
      }
      .onChange(of: thumbnailLabels) {
        UserDefaults.standard.set(thumbnailLabels.map(\.rawValue), forKey: "Photo.thumbnailLabels")
      }
  }

  private var workspacePresentation: some View {
    workspaceLoadHandlers
      .onChange(of: workspace.sessionID) {
        comparison.close()
        croppingPhoto = nil
      }
      .onChange(of: workspace.selectedID) { comparison.resetViewports() }
      .onChange(of: layout.focused) {
        if showPreview && !layout.showsFilmstrip {
          previewFocused = true
        } else {
          gridFocused = true
        }
      }
      .onChange(of: layout.filmstrip) {
        if showPreview && !layout.showsFilmstrip {
          previewFocused = true
        } else {
          gridFocused = true
        }
      }
      .onChange(of: showPreview) {
        if !showPreview { layout.leaveFocus() }
        comparison.resetViewports()
        if pendingInspection && showPreview {
          pendingInspection = false
          comparison.toggleInspection()
        }
      }
      .sheet(item: $trashPlan) { plan in
        TrashConfirmationView(
          plan: plan, store: workspace.persistence, decisions: workspace.decisions
        ) { result in
          workspace.removeTrashedPhotos(result.moved)
          trashNotice =
            "Moved \(result.moved.filter { PhotoFormats.supports($0) }.count) photos to Trash."
            + (result.error.map { " Stopped: " + $0 } ?? " Restore with Finder → Trash → Put Back.")
        }
      }
      .alert("Cannot Move to Trash", isPresented: $showingTrashError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(trashNotice)
      }
  }

  private var sceneActions: WorkspaceActions {
    WorkspaceActions(
      workspace: workspace,
      canDecide: !choosingFolder && !showingWorkflow && !showingHelp && !showingOptions
        && !showingFilters && croppingPhoto == nil
        && trashPlan == nil && !preparingTrash
        && (!workflowModel.busy || workflowModel.backgroundable), columns: gridColumns,
      togglePreview: { showPreview.toggle() }, hidePreview: cancelBrowsing,
      openFolder: openFolder, reload: reload,
      clearThumbnails: {
        Task {
          await thumbnails.clearThumbnailCache()
          thumbnailCacheGeneration += 1
        }
      },
      workflow: { showWorkflow($0) }, help: { showingHelp = true },
      canReload: workspace.directory != nil && !choosingFolder && !showingWorkflow
        && !showingHelp && croppingPhoto == nil && trashPlan == nil && !preparingTrash,
      comparison: comparison, toggleComparison: toggleComparison, pinReference: pinCurrent,
      canCompare: workspace.photos.count > 1,
      crop: { croppingPhoto = workspace.selectedPhoto }, copyCrop: copyCrop, pasteCrop: pasteCrop,
      canPasteCrop: copiedCrop != nil,
      inspect: toggleInspection, trash: prepareTrash,
      canTrash: !workspace.isSourceReview && workspace.directory != nil
        && workspace.decisionSelectionReady
        && !workflowModel.busy,
      toggleFocus: toggleFocus, focused: layout.focused,
      toggleFilmstrip: { layout.filmstrip.toggle() }, filmstripVisible: layout.filmstrip,
      toggleQuickPreview: { if quickPreviewAllowed { quickPreview.pinned.toggle() } },
      quickPreviewVisible: quickPreview.visible
    )
  }

  private var browsingContent: some View {
    VStack(spacing: 0) {
      if !layout.focused {
        WorkspaceRegion { collectionHeader }
        WorkspaceRegion { cullingBar }
      }
      if workspace.isSourceReview { WorkspaceRegion { sourceReviewBanner } }
      Divider()
      if readyImageSession == workspace.sessionID {
        photoContent
      } else {
        ProgressView("Opening photos…").frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      WorkspaceRegion { statusBar }
    }.background(Color(nsColor: .underPageBackgroundColor))
      .onExitCommand(perform: cancelBrowsing)
  }

  // Mount image tasks only after both pipelines belong to the current folder.
  // Restored-folder requests can otherwise race the initial sample session.
  private var photoContent: some View {
    VStack(spacing: 0) {
      if showPreview && !workspace.photos.isEmpty {
        WorkspaceRegion { previewPane }.frame(maxWidth: .infinity, maxHeight: .infinity)
        if layout.showsFilmstrip { Divider() }
      }
      if !showPreview || workspace.photos.isEmpty || layout.showsFilmstrip {
        WorkspaceRegion { contactSheet }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .frame(
            height: showPreview && !workspace.photos.isEmpty
              ? WorkspaceLayout.filmstripHeight(
                edge: thumbnailEdge, labels: thumbnailLabels.count,
                folders: workspace.includesSubfolders) : nil)
      }
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("FOLDERS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Spacer()
        Button(action: openFolder) { Image(systemName: "folder.badge.plus") }
          .buttonStyle(.borderless).accessibilityLabel("Open Folder…").help(
            "Open a folder and keep it in the sidebar (⌘O).")
      }
      FolderSidebar(
        library: folderLibrary, current: workspace.directory, open: browse,
        remove: { folder in
          folderLibrary.remove(folder)
          if folderLibrary.selected == nil { workspace.showSamples() }
        })
      Divider()
      HStack {
        Button(folderLibrary.home == nil ? "Choose Photo Home…" : "Change Photo Home…") {
          chooseFolder(asHome: true)
        }
        .buttonStyle(.borderless).font(.caption).disabled(choosingFolder)
        .help(
          "Your usual starting folder. Expand arrows to browse; click a folder to see its photos. Nothing is moved."
        )
        Spacer(minLength: 0)
        Menu {
          Button("Open Folder…", action: openFolder)
          Button("Workflow…") { showWorkflow(workflowModel.requestedTab) }
          Button("Show Sample Collection") {
            workspace.showSamples()
            gridFocused = true
          }
          Button("Quick Start & Shortcuts") { showingHelp = true }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Folder and help options")
      }
    }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color(nsColor: .windowBackgroundColor))
  }

  private var collectionHeader: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text(workspace.title).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
        Text(
          "\(workspace.photos.count) of \(workspace.totalCount) photos"
            + (workspace.includesSubfolders ? " · subfolders" : "")
        )
        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }.frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
      if workspace.indexing {
        Text("EXIF \(workspace.indexedCount)/\(workspace.totalCount)").font(.caption2)
          .monospacedDigit().foregroundStyle(.secondary)
      }
      Picker("Browsing view", selection: $showPreview) {
        Text("Contact Sheet").tag(false)
        Text("Preview").tag(true)
      }.pickerStyle(.segmented).labelsHidden().frame(width: 184)
        .help("Large preview with bottom filmstrip, or full contact sheet (Space).")
      Picker(
        "Sort",
        selection: Binding(
          get: { workspace.sort }, set: { sort in Task { await workspace.setSort(sort) } })
      ) {
        ForEach(PhotoSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.labelsHidden().frame(width: 116).accessibilityLabel("Sort")
      Button {
        showingFilters.toggle()
      } label: {
        Label(
          filtersActive ? activeFilterLabel : "Filters",
          systemImage: "line.3.horizontal.decrease.circle")
      }.popover(isPresented: $showingFilters, arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Filter & select").font(.headline)
            Spacer()
            Button("Done", action: dismissPopovers).keyboardShortcut(.cancelAction)
          }
          filters
          selectionTools
          if filtersActive {
            Text("Filters hide photos; they do not change files.").font(.caption).foregroundStyle(
              .secondary)
          }
        }.padding(16).onExitCommand(perform: dismissPopovers)
      }.help(
        "Filter picks, rejects and stars; select or review a group. Active filters are named here; × clears them."
      )
      if filtersActive {
        Button {
          workspace.setFilter(.all, minimumRating: 0)
        } label: {
          Image(systemName: "xmark.circle")
        }
        .accessibilityLabel("Clear Filters").help("Show all flags and stars again.")
      }
      if workspace.reviewingSelection {
        Button("Show All Photos") { workspace.endReview() }.help(
          "Finish selected-only review and return to the folder.")
      }
      collectionOptions
    }.controlSize(.small).padding(.horizontal, 10).padding(.vertical, 5)
  }
  private var filtersActive: Bool { workspace.flagFilter != .all || workspace.minimumRating != 0 }
  private var activeFilterLabel: String {
    let flag = workspace.flagFilter == .all ? "All flags" : workspace.flagFilter.rawValue
    return flag + (workspace.minimumRating == 0 ? "" : " · ≥\(workspace.minimumRating)★")
  }
  private var collectionOptions: some View {
    Button {
      showingOptions.toggle()
    } label: {
      Image(systemName: "slider.horizontal.3")
    }
    .accessibilityLabel("Browsing options")
    .help("Include subfolders, group RAW+JPEG, choose EXIF labels and adjust thumbnail size.")
    .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Browsing options").font(.headline)
          Spacer()
          Button("Done", action: dismissPopovers).keyboardShortcut(.cancelAction)
        }
        Toggle(
          "Include Subfolders",
          isOn: Binding(
            get: { workspace.includesSubfolders },
            set: { value in
              guard let directory = workspace.directory else { return }
              Task { await workflowModel.openFolder(directory, includingSubfolders: value) }
            })
        ).disabled(
          workspace.directory == nil || (workflowModel.busy && !workflowModel.backgroundable))
        Toggle(
          "RAW+JPEG",
          isOn: Binding(get: { workspace.groupPairs }, set: { workspace.setGrouping($0) })
        )
        Divider()
        Text("Thumbnail information · up to two labels")
        ForEach(ThumbnailInfoField.allCases) { field in
          Toggle(
            field.title,
            isOn: Binding(
              get: { thumbnailLabels.contains(field) },
              set: { included in
                if included && thumbnailLabels.count < 2 {
                  thumbnailLabels.append(field)
                } else if !included {
                  thumbnailLabels.removeAll { $0 == field }
                }
              })
          ).disabled(!thumbnailLabels.contains(field) && thumbnailLabels.count >= 2)
        }
        Button("Hide Extra Labels") { thumbnailLabels = [] }
        Divider()
        Toggle("Show Filmstrip", isOn: $layout.filmstrip)
        Button("Focus on Photo", action: toggleFocus).disabled(workspace.selectedPhoto == nil)
        Text("Thumbnail size")
        Slider(
          value: Binding(
            get: { thumbnailEdge },
            set: { if showPreview { filmstripSize = $0 } else { thumbnailSize = $0 } }),
          in: showPreview ? 64...134 : 110...240, step: 10
        )
        .accessibilityLabel("Thumbnail size")
      }.padding(14).frame(width: 280)
    }
  }
  private var cullingBar: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        decisionButtons
        Divider().frame(height: 20)
        imageEditControls
        Spacer(minLength: 4)
        selectionSummary
        autoAdvance
      }
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          decisionButtons
          Spacer(minLength: 4)
          selectionSummary
        }
        HStack {
          imageEditControls
          Spacer(minLength: 4)
          autoAdvance
        }
      }
    }.controlSize(.small).padding(.horizontal, 10).padding(.bottom, 4)
  }
  private var selectionSummary: some View {
    let summary = workspace.selectionSummary
    return Text(
      "\(summary.fileCount) selected"
        + (summary.flag == nil || summary.rating == nil ? " · mixed" : "")
    )
    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    .help("Decisions and edits apply to selected physical files, including grouped RAW+JPEG pairs.")
  }
  private var browsingCommandsAvailable: Bool {
    !choosingFolder && !showingWorkflow && !showingHelp && !showingOptions && !showingFilters
      && croppingPhoto == nil && trashPlan == nil && !preparingTrash
      && (!workflowModel.busy || workflowModel.backgroundable)
  }
  private func toggleFocus() {
    showingOptions = false
    showingFilters = false
    layout.toggleFocus()
    if layout.focused { showPreview = true }
    gridFocused = true
  }
  private func dismissPopovers() {
    showingOptions = false
    showingFilters = false
    Task { @MainActor in
      await Task.yield()
      if showPreview && !layout.showsFilmstrip { previewFocused = true } else { gridFocused = true }
    }
  }
  private func cancelBrowsing() {
    if quickPreview.visible {
      quickPreview.dismiss()
      return
    }
    if showingOptions || showingFilters {
      dismissPopovers()
      return
    }
    guard !showingWorkflow, !showingHelp, croppingPhoto == nil, trashPlan == nil, !preparingTrash
    else { return }
    leavePreview()
  }
  private func leavePreview() {
    if layout.focused { layout.leaveFocus() } else { showPreview = false }
    gridFocused = true
  }

  private var thumbnailEdge: Double { showPreview ? filmstripSize : thumbnailSize }

  private func framedThumbnail(_ photo: PhotoItem) -> some View {
    thumbnail(photo)
      .id(photo.id)
      .background(
        GeometryReader { tile in
          Color.clear.preference(
            key: PhotoTileFrames.self,
            value: [photo.id: tile.frame(in: .named("ContactSheetViewport"))])
        })
  }

  private var contactSheet: some View {
    GeometryReader { geometry in
      let columns = showPreview ? 1 : max(1, Int((geometry.size.width - 32) / (thumbnailSize + 16)))
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
            if workspace.reviewingSelection {
              Button("Show All Photos") { workspace.endReview() }
            }
          }
        case .ready where workspace.photos.isEmpty:
          ContentUnavailableView {
            Label("No supported images", systemImage: "photo.on.rectangle")
          } description: {
            Text(
              "Choose a folder with JPEG, PNG, or Sony/Canon/Olympus RAW files. Open Browsing options and turn on Include Subfolders to see the whole shoot, or expand a sidebar folder and choose a subfolder. Hidden files are not included."
            )
          } actions: {
            Button("Open Folder…", action: openFolder)
          }
        case .ready:
          if !showPreview {
            NativeContactSheet(
              workspace: workspace, columns: columns, thumbnailEdge: thumbnailEdge,
              availableWidth: geometry.size.width, labels: thumbnailLabels,
              folderLabels: workspace.includesSubfolders,
              cacheGeneration: thumbnailCacheGeneration, hasCopiedCrop: copiedCrop != nil,
              selectionFocus: { gridFocused = $0 },
              content: { photo, height in AnyView(thumbnail(photo, fixedContentHeight: height)) },
              navigate: { workspace.moveSelection(by: $0, extending: $1) },
              preview: { showPreview = $0 },
              magnify: { thumbnailSize = min(240, max(110, thumbnailSize * (1 + $0))) })
          } else {
            ScrollViewReader { proxy in
              ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 6) {
                  ForEach(workspace.photos) { photo in
                    framedThumbnail(photo).frame(width: thumbnailEdge + 16)
                  }
                }.padding(6)
              }
              .simultaneousGesture(
                MagnifyGesture(minimumScaleDelta: 0.02).onChanged { value in
                  if pinchSize == nil { pinchSize = thumbnailEdge }
                  let size = (pinchSize ?? thumbnailEdge) * value.magnification
                  if showPreview {
                    filmstripSize = min(134, max(64, size))
                  } else {
                    thumbnailSize = min(240, max(110, size))
                  }
                }.onEnded { _ in pinchSize = nil }
              )
              .coordinateSpace(name: "ContactSheetViewport")
              .onPreferenceChange(PhotoTileFrames.self) { tileGeometry.replace(with: $0) }
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
                    let hits = tileGeometry.hits(in: marquee.rectangle, viewportSize: geometry.size)
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
                if let id = workspace.selectedID { proxy.scrollTo(id, anchor: .center) }
              }
              .onChange(
                of: SelectionReveal(id: workspace.selectedID, index: workspace.selectedIndex)
              ) {
                guard marquee == nil else { return }
                if let id = workspace.selectedID { proxy.scrollTo(id, anchor: .center) }
              }
              .task(
                id: GridLayout(
                  size: geometry.size, thumbnailSize: thumbnailEdge, showsPreview: showPreview)
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
              tileGeometry.clear()
              marquee = nil
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: columns, initial: true) { gridColumns = columns }
      .onChange(of: showPreview) {
        tileGeometry.clear()
        marquee = nil
        gridFocused = true
      }
      .focusable().focused($gridFocused).focusEffectDisabled()
      .onKeyPress(.leftArrow, phases: .down) { press in
        guard !showingOptions, !showingFilters else { return .ignored }
        workspace.moveSelection(by: -1, extending: press.modifiers.contains(.shift))
        return .handled
      }
      .onKeyPress(.rightArrow, phases: .down) { press in
        guard !showingOptions, !showingFilters else { return .ignored }
        workspace.moveSelection(by: 1, extending: press.modifiers.contains(.shift))
        return .handled
      }
      .onKeyPress(.upArrow, phases: .down) { press in
        guard !showingOptions, !showingFilters else { return .ignored }
        workspace.moveSelection(by: -columns, extending: press.modifiers.contains(.shift))
        return .handled
      }
      .onKeyPress(.downArrow, phases: .down) { press in
        guard !showingOptions, !showingFilters else { return .ignored }
        workspace.moveSelection(by: columns, extending: press.modifiers.contains(.shift))
        return .handled
      }
      .onKeyPress(.space) {
        guard !showingOptions, !showingFilters else { return .ignored }
        showPreview.toggle()
        return .handled
      }
      .onKeyPress(.home) {
        guard !showingOptions, !showingFilters else { return .ignored }
        workspace.moveSelection(by: Int.min)
        return .handled
      }
      .onKeyPress(.end) {
        guard !showingOptions, !showingFilters else { return .ignored }
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
        cancelBrowsing()
        return .handled
      }
    }
  }

  @ViewBuilder private func thumbnail(_ photo: PhotoItem, fixedContentHeight: Double? = nil)
    -> some View
  {
    if let state = workspace.thumbnailState(for: photo.id) {
      WorkspaceThumbnail(
        photo: photo, state: state, selection: workspace.selectionPresentation,
        thumbnails: thumbnails, sessionID: workspace.sessionID,
        cacheGeneration: thumbnailCacheGeneration, thumbnailEdge: thumbnailEdge,
        thumbnailLabels: thumbnailLabels, groupPairs: workspace.groupPairs,
        folderLabel: workspace.includesSubfolders ? workspace.folderLabel(for: photo.id) : nil,
        hasCopiedCrop: copiedCrop != nil, compact: showPreview,
        fixedContentHeight: fixedContentHeight,
        select: { selectThumbnail(photo) },
        action: { thumbnailAction($0, photo: photo) },
        openPreview: { showPreview = true },
        metadata: {
          prepareThumbnail(photo)
          showWorkflow(2)
        },
        apply: { rating, flag in
          workspace.applyThumbnailDecision(to: photo.id, rating: rating, flag: flag)
          gridFocused = true
        },
        edit: { action in
          prepareThumbnail(photo)
          workspace.editSelection(action)
        },
        copyCrop: { copiedCrop = state.edit.crop },
        pasteCrop: {
          prepareThumbnail(photo)
          pasteCrop()
        }
      ).equatable()
    }
  }
  private func thumbnailAction(_ action: ThumbnailAction, photo: PhotoItem) {
    if action == .preview {
      workspace.selectGroup([photo.id], focus: photo.id)
      showPreview = true
    } else {
      guard thumbnailReady(photo) else { return }
      prepareThumbnail(photo)
      switch action {
      case .rotateLeft: workspace.editSelection(.counterclockwise)
      case .rotateRight: workspace.editSelection(.clockwise)
      case .mirrorHorizontal: workspace.editSelection(.horizontal)
      case .mirrorVertical: workspace.editSelection(.vertical)
      case .crop: croppingPhoto = photo
      case .metadata:
        showWorkflow(2)
        return
      case .preview: break
      }
    }
    gridFocused = true
  }
  private func selectThumbnail(_ photo: PhotoItem) {
    let modifiers = NSApp.currentEvent?.modifierFlags ?? []
    workspace.selectMultiple(
      photo.id, extending: modifiers.contains(.command), range: modifiers.contains(.shift))
    gridFocused = true
  }
  private func prepareThumbnail(_ photo: PhotoItem) {
    if !workspace.selectedIDs.contains(photo.id) {
      workspace.selectMultiple(photo.id, extending: false, range: false)
    }
  }
  private func thumbnailReady(_ photo: PhotoItem) -> Bool {
    workspace.decisionsReady.contains(photo.id)
      && (!workspace.selectedIDs.contains(photo.id) || workspace.decisionSelectionReady)
  }
  private func copyCrop() {
    copiedCrop = workspace.selectedPhoto.flatMap { workspace.imageEdits[$0.id]?.crop }
  }
  private func pasteCrop() { if let copiedCrop { workspace.pasteCrop(copiedCrop) } }

  private var imageEditControls: some View {
    HStack(spacing: 6) {
      Button {
        workspace.editSelection(.counterclockwise)
        gridFocused = true
      } label: {
        Image(systemName: "rotate.left").frame(width: 24, height: 24).contentShape(Rectangle())
      }
      .accessibilityLabel("Rotate Left").help(
        "Rotate selected photos left 90° ([). Photo-only edit; originals stay unchanged.")
      Button {
        workspace.editSelection(.clockwise)
        gridFocused = true
      } label: {
        Image(systemName: "rotate.right").frame(width: 24, height: 24).contentShape(Rectangle())
      }
      .accessibilityLabel("Rotate Right").help(
        "Rotate selected photos right 90° (]). Photo-only edit; originals stay unchanged.")
      Menu {
        Button("Flip Left / Right") { workspace.editSelection(.horizontal) }
        Button("Flip Top / Bottom") { workspace.editSelection(.vertical) }
      } label: {
        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
      }
      .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Mirror").help(
        "Mirror selected photos. Photo-only edit.")
      Button {
        croppingPhoto = workspace.selectedPhoto
      } label: {
        Label("Crop", systemImage: "crop")
      }
      .help("Crop the current photo (⇧⌘C). Photo-only edit; copy/paste crops from the Image menu.")
      Button {
        showWorkflow(2)
      } label: {
        Label("IPTC", systemImage: "info.circle")
      }
      .disabled(workspace.isSourceReview).help(
        "Edit selected captions, copyright and keywords; choose only fields you want to apply.")
    }.labelStyle(.titleAndIcon).buttonStyle(.borderless).disabled(!workspace.decisionSelectionReady)
  }

  private var previewPane: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text(workspace.selectedPhoto?.filename ?? "PREVIEW")
          .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 0)
        Button(comparison.enabled ? "Single Image" : "Compare") { toggleComparison() }
          .disabled(!comparison.enabled && workspace.photos.count < 2)
          .help(
            "Pin a reference and browse another photo beside it (C). Decisions follow the filmstrip selection."
          )
        Button {
          workspace.moveSelection(by: -1)
          gridFocused = true
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(workspace.selectedIndex == nil || workspace.selectedIndex == 0)
        .accessibilityLabel("Previous photo")
        Text(
          workspace.selectedIndex.map { "\($0 + 1) of \(workspace.photos.count)" } ?? "No selection"
        )
        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        Button {
          workspace.moveSelection(by: 1)
          gridFocused = true
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(
          workspace.selectedIndex == nil || workspace.selectedIndex == workspace.photos.count - 1
        )
        .accessibilityLabel("Next photo")
        if !layout.focused {
          Toggle(isOn: $showInspector) { Image(systemName: "info.circle") }
            .toggleStyle(.button).accessibilityLabel("Shooting information")
            .help("Show camera, lens, capture time and dimensions beside the preview.")
          Button {
            layout.filmstrip.toggle()
            gridFocused = true
          } label: {
            Image(systemName: "rectangle.bottomthird.inset.filled")
          }.accessibilityLabel(layout.filmstrip ? "Hide Filmstrip" : "Show Filmstrip")
            .help(
              layout.filmstrip
                ? "Hide the filmstrip to give the photo more height (⌥⌘T)."
                : "Show the bottom filmstrip (⌥⌘T).")
        }
        if layout.focused {
          Button("Exit Focus", action: cancelBrowsing)
            .keyboardShortcut(.cancelAction).help("Restore panels (Escape or ⇧⌘F).")
            .disabled(!browsingCommandsAvailable)
        } else {
          Button(action: cancelBrowsing) { Image(systemName: "square.grid.3x3") }
            .keyboardShortcut(.cancelAction).accessibilityLabel("Show contact sheet")
            .help("Return to the contact sheet (Escape or Space).")
            .disabled(!browsingCommandsAvailable)
        }
      }.buttonStyle(.borderless).padding(.horizontal, 8).padding(.vertical, 3)
      if let photo = workspace.selectedPhoto {
        if comparison.enabled { comparisonControls }
        HStack(alignment: .top, spacing: 12) {
          if let reference = comparison.reference {
            VStack(alignment: .leading, spacing: 5) {
              Text("REFERENCE · " + reference.filename).font(.caption.weight(.semibold))
                .lineLimit(1).truncationMode(.middle)
              DetailPreviewView(
                photo: reference, pipeline: previews, detailPipeline: referenceDetails,
                sessionID: workspace.sessionID, comparison: comparison, pane: .reference,
                edit: workspace.imageEdits[reference.id] ?? PhotoEdit()
              )
              .id("reference-\(workspace.sessionID)-\(reference.id)")
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
          }
          VStack(alignment: .leading, spacing: 5) {
            if comparison.enabled {
              Text("ACTIVE · " + photo.filename).font(.caption.weight(.semibold))
                .lineLimit(1).truncationMode(.middle)
            }
            DetailPreviewView(
              photo: photo, pipeline: previews, detailPipeline: detailPipeline,
              sessionID: workspace.sessionID, comparison: comparison, pane: .active,
              edit: workspace.imageEdits[photo.id] ?? PhotoEdit(), nearbyFiles: nearbyFitFiles,
              didMeasure: canvasMeasured
            )
            .id("active-\(workspace.sessionID)-\(photo.id)")
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
          if showInspector && !layout.focused {
            WorkspaceRegion { inspector(photo) }
          }
        }.padding(.horizontal, 4)
        HStack {
          WorkspaceRegion { shootingSummary(photo) }
          Spacer(minLength: 0)
          WorkspaceRegion { decisionRecovery(photo) }
        }.padding(.horizontal, 8).padding(.vertical, 2)

      } else {
        ContentUnavailableView("Select a photo", systemImage: "photo")
      }
    }.background(Color.black.opacity(0.2))
      .focusable().focused($previewFocused).focusEffectDisabled()
      .onAppear { if !layout.showsFilmstrip { previewFocused = true } }
      .onKeyPress(.escape) {
        cancelBrowsing()
        return .handled
      }
  }

  private func inspector(_ photo: PhotoItem) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text("SHOOTING INFORMATION").font(.caption.weight(.semibold))
        if let metadata = workspace.thumbnailState(for: photo.id)?.metadata {
          Text(metadata.camera ?? "Camera unavailable")
          Text(metadata.lens ?? "Lens unavailable")
          Text(metadata.captureTimeText ?? "Capture time unavailable")
          Text(metadata.shootingSummary)
          Text(
            metadata.focalLength.map { "\($0.formatted()) mm" }
              ?? "Focal length unavailable")
          Text("\(metadata.pixelWidth) × \(metadata.pixelHeight)")
        } else if workspace.indexing && photo.fileURL != nil {
          ProgressView("Reading shooting information…")
        } else {
          Text("No shooting information available.").foregroundStyle(.secondary)
        }
      }.font(.caption).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
    }.frame(width: 200).frame(maxHeight: .infinity)
      .background(Color.white.opacity(0.025))
  }

  private var nearbyFitFiles: [URL] {
    guard !comparison.enabled, !workflowModel.busy, !WorkflowOperationBarrier.shared.hasPending,
      !showingWorkflow, croppingPhoto == nil, !preparingTrash, trashPlan == nil,
      !workspace.isSourceReview, let index = workspace.selectedIndex
    else { return [] }
    return [index + 1, index - 1].compactMap { position in
      guard workspace.photos.indices.contains(position) else { return nil }
      let photo = workspace.photos[position]
      return photo.fileURL ?? SampleResources.url(for: photo)
    }
  }

  private var comparisonControls: some View {
    HStack(spacing: 12) {
      Toggle(
        "Link Zoom/Pan",
        isOn: Binding(get: { comparison.linked }, set: { comparison.setLinked($0) })
      )
      .toggleStyle(.checkbox)
      .help(
        "Link Fit/100% and normalized image centers (L). Full detail is explicit; two panes allow up to 512 MiB retained decoded images plus decoder/GPU memory."
      )
      Button("Pin Current") { pinCurrent() }
        .help(
          "Use the active photo as the fixed reference (G), then navigate to compare another frame."
        )
      Button("Swap") {
        guard let reference = comparison.reference, let active = workspace.selectedPhoto else {
          return
        }
        comparison.pin(active)
        workspace.select(reference.id)
        gridFocused = true
      }.disabled(!workspace.photos.contains { $0.id == comparison.reference?.id })
        .help(
          "Swap reference and active. The reference must be visible in the current review/filter set."
        )
      Spacer(minLength: 0)
      Text("Decisions follow thumbnail selection").font(.caption).foregroundStyle(.secondary)
        .lineLimit(1)
    }.controlSize(.small).padding(.horizontal, 12)
  }

  private func pinCurrent() {
    guard let photo = workspace.selectedPhoto else { return }
    comparison.pin(photo)
    showPreview = true
    gridFocused = true
  }
  private func toggleComparison() {
    if comparison.enabled {
      comparison.close()
      return
    }
    guard let current = workspace.selectedPhoto, workspace.photos.count > 1 else { return }
    let chosen = workspace.photos.filter { workspace.selectedIDs.contains($0.id) }
    let reference = chosen.first ?? current
    let candidate =
      chosen.first { $0.id != reference.id }
      ?? workspace.photos.dropFirst(
        (workspace.photos.firstIndex { $0.id == reference.id } ?? 0) + 1
      ).first
      ?? workspace.photos.first { $0.id != reference.id }
    guard let candidate else { return }
    comparison.pin(reference)
    workspace.select(candidate.id)
    showPreview = true
    gridFocused = true
  }

  private func shootingSummary(_ photo: PhotoItem) -> some View {
    Text(
      workspace.thumbnailState(for: photo.id)?.metadata?.shootingSummary
        ?? (workspace.indexing && photo.fileURL != nil
          ? "Reading shooting information…" : "No shooting information")
    )
    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
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
      Button("Select All") {
        workspace.selectAllVisible()
        dismissPopovers()
      }.disabled(workspace.photos.isEmpty)
        .help("Select every visible photo (⌘A). Filters limit this selection.")
      Text("\(workspace.selectedIDs.count) selected").monospacedDigit()
      Menu {
        Button("Select Rejects") {
          workspace.selectRejects()
          dismissPopovers()
        }
        Button("Move Selected to Trash…") {
          dismissPopovers()
          prepareTrash()
        }
        .disabled(
          workspace.directory == nil || workspace.isSourceReview
            || !workspace.decisionSelectionReady || workflowModel.busy)
      } label: {
        Label("Remove", systemImage: "trash")
      }
      .help(
        workspace.isSourceReview
          ? "This card/source is protected. Copy keepers; leave rejects on the card."
          : "Select Rejects, then Move Selected to Trash (⌘Delete). A confirmation lists the exact files."
      )
      Button(workspace.reviewingSelection ? "Show All Photos" : "Review Only Selected") {
        if workspace.reviewingSelection {
          workspace.endReview()
        } else {
          workspace.reviewSelection()
          showPreview = true
        }
        dismissPopovers()
      }.disabled(!workspace.reviewingSelection && workspace.selectedIDs.count < 2)
        .help(
          "Select two or more photos first. Review Only Selected hides the others so you can judge each photo individually. Show All Photos returns to the folder."
        )
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

  private var decisionButtons: some View {
    let summary = workspace.selectionSummary
    return HStack(spacing: 2) {
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
  }
  @ViewBuilder private func decisionRecovery(_ photo: PhotoItem) -> some View {
    let status = workspace.saveStatus[photo.id] ?? ""
    if !status.isEmpty && status != "Saved" && status != "Saving…" && status != "Saving review…"
      && !status.hasPrefix("Review saved on this Mac") && photo.fileURL != nil
    {
      HStack {
        if workspace.isSourceReview {
          if !status.hasPrefix("Review saved on this Mac") && status != "Saving review…" {
            Button("Retry Review Save") { workspace.retrySync() }
          }
        } else if status.hasPrefix("XMP conflict") {
          Button("Use My Decisions") { workspace.retrySync(useLocal: true) }
          Button("Use External Decisions") { Task { await workspace.useExternalDecision() } }
        } else if status != "Saving…" {
          Button("Retry XMP Sync") { workspace.retrySync() }
        }
      }.font(.caption)
    }
  }

  private var statusBar: some View {
    HStack {
      if workflowModel.busy {
        ProgressView().controlSize(.small)
        Button("Workflow…") { showWorkflow(workflowModel.requestedTab) }
        Text(workflowModel.status).lineLimit(1)
      }
      Label(
        workspace.selectedID.flatMap { workspace.saveStatus[$0] } ?? "Originals stay untouched",
        systemImage: "checkmark.shield"
      ).lineLimit(1)
      if !workspace.editStatus.isEmpty {
        Text(workspace.editStatus).lineLimit(1).help(
          "Photo-local rotation, mirror and crop saving status.")
      }
      if !trashNotice.isEmpty { Text(trashNotice).lineLimit(1).help(trashNotice) }
      Spacer()
      Text(workspace.selectedPhoto?.filename ?? "No selection").lineLimit(1)
      Text("·  \(workspace.photos.count) photos")
    }
    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 4)
  }

  private func toggleInspection() {
    quickPreview.dismiss()
    if !showPreview {
      pendingInspection = true
      showPreview = true
    } else {
      comparison.toggleInspection()
    }
  }

  private func prepareTrash() {
    guard !preparingTrash, !workspace.isSourceReview, !workflowModel.busy,
      let folder = workspace.directory, workspace.decisionSelectionReady
    else { return }
    let session = workspace.sessionID
    preparingTrash = true
    Task {
      defer { preparingTrash = false }
      // Let a preceding native menu selection finish before freezing the list.
      await Task.yield()
      guard session == workspace.sessionID else { return }
      let targets = workspace.operationPhotos
      let identities = workspace.selectedFileIdentities
      guard identities.count == targets.count else {
        trashNotice =
          "Some selected photos could not be identified. Reload this folder before moving files to Trash."
        showingTrashError = true
        return
      }
      await DecisionSaveQueue.shared.flush()
      guard session == workspace.sessionID else { return }
      do {
        let plan = try await PhotoTrash(store: workspace.persistence).prepare(
          images: identities, folder: folder, includingSubfolders: workspace.includesSubfolders)
        guard session == workspace.sessionID else { return }
        trashPlan = plan
      } catch {
        trashNotice = error.localizedDescription
        showingTrashError = true
      }
    }
  }

  private func openFolder() { chooseFolder(asHome: false) }

  private func chooseFolder(asHome: Bool) {
    guard
      !choosingFolder && !showingWorkflow && !showingHelp && croppingPhoto == nil
        && trashPlan == nil && !preparingTrash
    else {
      return
    }
    choosingFolder = true
    NSApp.activate()
    let panel = NSOpenPanel()
    panel.title = asHome ? "Choose Photo Home" : "Open Photo Folder"
    panel.prompt = asHome ? "Use as Photo Home" : "Open Folder"
    panel.message =
      asHome
      ? "Choose the folder where you usually keep shoots. This adds a starting place in the sidebar; it does not move photos."
      : "Choose a folder to browse its photos and subfolders."
    panel.directoryURL = folderLibrary.home
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
      if asHome { folderLibrary.setHome(url) } else { folderLibrary.add(url) }
      Task {
        if asHome && !folderLibrary.expanded.contains(url.path) { await folderLibrary.toggle(url) }
        await workflowModel.openFolder(url)
        gridFocused = true
      }
    }
    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else {
      panel.begin(completionHandler: completion)
    }
  }

  private var sourceReviewBanner: some View {
    HStack(spacing: 8) {
      Label("Source protected", systemImage: "lock.shield").font(.caption.weight(.semibold))
        .help(
          "Decisions save on this Mac. The card/source stays unchanged; copy reviewed keepers when ready."
        )
      Text("\(workspace.sourceReviewedIDs.count) of \(workspace.totalCount) reviewed").font(
        .caption
      ).monospacedDigit().foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Button("Copy Reviewed Photos…") { showWorkflow(0, reviewedCopy: true) }
        .help(
          "Prepare an explicit copy list and two verified destinations. The source stays unchanged."
        )
    }.controlSize(.small).padding(.horizontal, 10).padding(.vertical, 4).background(
      Color.accentColor.opacity(0.10))
  }

  private func showWorkflow(_ tab: Int, reviewedCopy: Bool = false) {
    gridFocused = false
    workflowModel.opensReviewedCopySetup = reviewedCopy
    workflowModel.requestedTab = tab
    showingWorkflow = true
  }

  private func browse(_ folder: URL) {
    folderLibrary.select(folder)
    Task {
      await workflowModel.openFolder(folder)
      gridFocused = true
    }
  }

  private func reload() {
    guard let directory = workspace.directory else { return }
    Task {
      await metadataReader.clear()
      await workflowModel.openFolder(directory)
      if folderLibrary.expanded.contains(directory.path) { await folderLibrary.refresh(directory) }
      gridFocused = true
    }
  }
}
