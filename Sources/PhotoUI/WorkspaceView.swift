import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI
import UniformTypeIdentifiers

private typealias WorkspaceStorage = SwiftUI.State<WorkspaceState>
private typealias ThumbnailLabelsStorage = SwiftUI.State<[ThumbnailInfoField]>
private typealias ComparisonStorage = SwiftUI.State<ComparisonSession>
private typealias WorkflowModelStorage = SwiftUI.State<WorkflowModel>
private typealias BoolStorage = SwiftUI.State<Bool>
private typealias ColumnStorage = SwiftUI.State<Int>
private typealias SizeStorage = SwiftUI.State<Double>
private typealias PipelineStorage = SwiftUI.State<ImagePipeline>
private typealias DetailPipelineStorage = SwiftUI.State<DetailPipeline>
private typealias TileFramesStorage = SwiftUI.State<[String: CGRect]>
private typealias MarqueeStorage = SwiftUI.State<SelectionMarquee?>
private typealias FolderLibraryStorage = SwiftUI.State<FolderLibrary>
private typealias CropPhotoStorage = SwiftUI.State<PhotoItem?>
private typealias CropClipboardStorage = SwiftUI.State<PhotoCrop?>
private typealias GestureSizeStorage = SwiftUI.State<Double?>
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
  @WorkspaceStorage private var workspace: WorkspaceState
  @WorkflowModelStorage private var workflowModel: WorkflowModel
  @BoolStorage private var showPreview = true
  @BoolStorage private var choosingFolder = false
  @ColumnStorage private var gridColumns = 1
  @SizeStorage private var thumbnailSize = 160
  @SizeStorage private var filmstripSize = 120
  @PipelineStorage private var thumbnails = ImagePipeline(byteLimit: 24 * 1024 * 1024)
  @PipelineStorage private var previews = ImagePipeline(byteLimit: 64 * 1024 * 1024)
  @DetailPipelineStorage private var detailPipeline = DetailPipeline()
  @GridFocus private var gridFocused: Bool
  @BoolStorage private var showInspector = false
  @BoolStorage private var showingWorkflow = false
  @BoolStorage private var showingHelp = false
  @TileFramesStorage private var tileFrames: [String: CGRect] = [:]
  @CropPhotoStorage private var croppingPhoto: PhotoItem?
  @CropClipboardStorage private var copiedCrop: PhotoCrop?
  @GestureSizeStorage private var pinchSize: Double?
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
        VStack(spacing: 0) {
          if showPreview && !workspace.photos.isEmpty {
            previewPane.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
          }
          contactSheet
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(
              height: showPreview && !workspace.photos.isEmpty
                ? thumbnailEdge * 0.7 + (workspace.groupPairs ? 120 : 100)
                  + Double(thumbnailLabels.count * 20) : nil)
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
          Label(
            showPreview ? "Contact Sheet" : "Preview",
            systemImage: showPreview ? "square.grid.3x3" : "rectangle.bottomthird.inset.filled")
        }
        .help("Switch between large preview with bottom filmstrip and contact sheet (Space).")
      }
    }
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
    .onChange(of: workspace.directory) {
      if let folder = workspace.directory { folderLibrary.rememberIfUncovered(folder) }
    }
    .onChange(of: thumbnailLabels) {
      UserDefaults.standard.set(thumbnailLabels.map(\.rawValue), forKey: "Photo.thumbnailLabels")
    }
    .onChange(of: workspace.sessionID) {
      comparison.close()
      croppingPhoto = nil
    }
    .onChange(of: workspace.selectedID) { comparison.resetViewports() }
    .onChange(of: showPreview) { comparison.resetViewports() }
    .sheet(isPresented: $showingWorkflow) { WorkflowView(model: workflowModel) }
    .focusedSceneValue(
      \.workspaceActions,
      WorkspaceActions(
        workspace: workspace,
        canDecide: !choosingFolder && !showingWorkflow && !showingHelp && croppingPhoto == nil
          && (!workflowModel.busy || workflowModel.backgroundable), columns: gridColumns,
        togglePreview: { showPreview.toggle() }, hidePreview: { showPreview = false },
        openFolder: openFolder, reload: reload,
        workflow: showWorkflow, help: { showingHelp = true },
        canReload: workspace.directory != nil && !choosingFolder && !showingWorkflow
          && !showingHelp && croppingPhoto == nil,
        comparison: comparison, toggleComparison: toggleComparison, pinReference: pinCurrent,
        canCompare: workspace.photos.count > 1,
        crop: { croppingPhoto = workspace.selectedPhoto }, copyCrop: copyCrop, pasteCrop: pasteCrop,
        canPasteCrop: copiedCrop != nil
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
        if workspace.reviewingSelection {
          Text("SELECTED-ONLY REVIEW").font(.caption2).foregroundStyle(Color.accentColor)
        }
        Text(
          "\(workspace.photos.count) of \(workspace.totalCount) photos"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Picker("Browsing view", selection: $showPreview) {
        Text("Contact Sheet").tag(false)
        Text("Preview").tag(true)
      }.pickerStyle(.segmented).labelsHidden().frame(width: 205)
        .help(
          "Preview above a horizontal filmstrip, or a full contact sheet. Space switches views.")
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
        Text("EXIF \(workspace.indexedCount)/\(workspace.totalCount)")
          .font(.caption).foregroundStyle(.secondary)
      }
      Menu {
        Text("Choose up to two extra labels")
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
          )
          .disabled(!thumbnailLabels.contains(field) && thumbnailLabels.count >= 2)
        }
        Divider()
        Button("Hide Extra Labels") { thumbnailLabels = [] }
      } label: {
        Text("Labels")
      }
      .menuStyle(.borderlessButton).fixedSize()
      .accessibilityLabel("Thumbnail information labels")
      .help(
        "Choose up to two EXIF labels beneath filenames. Uses indexed metadata; does not decode images."
      )
      Image(systemName: showPreview ? "rectangle.split.3x1" : "square.grid.3x3").foregroundStyle(
        .secondary)
      Slider(
        value: Binding(
          get: { thumbnailEdge },
          set: { value in
            if showPreview { filmstripSize = value } else { thumbnailSize = value }
          }), in: showPreview ? 90...170 : 110...240, step: 10
      )
      .frame(width: 100).accessibilityLabel("Thumbnail size")
    }
    .padding(.horizontal, 16).padding(.vertical, 8)
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
              Button("End Selected Review") { workspace.endReview() }
            }
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
            ScrollView(showPreview ? .horizontal : .vertical) {
              if showPreview {
                LazyHStack(alignment: .top, spacing: 12) {
                  ForEach(workspace.photos) { photo in
                    framedThumbnail(photo).frame(width: thumbnailEdge + 16)
                  }
                }.padding(12)
              } else {
                LazyVGrid(
                  columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
                  spacing: 16
                ) {
                  ForEach(workspace.photos) { photo in framedThumbnail(photo) }
                }.padding(16)
              }
            }
            .simultaneousGesture(
              MagnifyGesture(minimumScaleDelta: 0.02).onChanged { value in
                if pinchSize == nil { pinchSize = thumbnailEdge }
                let size = (pinchSize ?? thumbnailEdge) * value.magnification
                if showPreview {
                  filmstripSize = min(170, max(90, size))
                } else {
                  thumbnailSize = min(240, max(110, size))
                }
              }.onEnded { _ in pinchSize = nil }
            )
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
              if let id = workspace.selectedID { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: SelectionReveal(id: workspace.selectedID, index: workspace.selectedIndex))
            {
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
            tileFrames = [:]
            marquee = nil
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: columns, initial: true) { gridColumns = columns }
      .onChange(of: showPreview) {
        tileFrames = [:]
        marquee = nil
        gridFocused = true
      }
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
    let information = thumbnailLabels.map { $0.label(workspace.metadata[photo.id]) }
    let spokenValue = (["\(decision.flag.title), \(decision.rating) stars"] + information).joined(
      separator: ", ")
    return VStack(alignment: .leading, spacing: 6) {
      Button {
        selectThumbnail(photo)
      } label: {
        PhotoImageView(
          photo: photo, pipeline: thumbnails, maximumPixelSize: 480,
          edit: workspace.imageEdits[photo.id] ?? PhotoEdit(), sessionID: workspace.sessionID
        )
        .frame(height: thumbnailEdge * 0.7).clipShape(RoundedRectangle(cornerRadius: 4))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Select \(photo.filename)").accessibilityValue(spokenValue)
      .accessibilityAddTraits(selected ? .isSelected : [])
      .simultaneousGesture(TapGesture(count: 2).onEnded { showPreview = true })
      thumbnailDecisions(photo, selected: selected)
      Button {
        selectThumbnail(photo)
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          if workspace.groupPairs, workspace.pairedCount(photo) > 1 {
            Text("RAW + JPEG").font(.caption2)
          }
          Text(photo.filename).font(.caption).lineLimit(1).truncationMode(.middle)
          thumbnailInformation(photo)
        }.foregroundStyle(selected ? Color.white : Color.secondary).frame(
          maxWidth: .infinity, alignment: .leading
        ).contentShape(Rectangle())
      }.buttonStyle(.plain)
      if workspace.imageEdits[photo.id]?.isEdited == true {
        Text(workspace.imageEdits[photo.id]?.crop != nil ? "Cropped · Photo edit" : "Photo edit")
          .font(.caption2).foregroundStyle(.secondary)
      }
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
    .contextMenu {
      ForEach([PhotoFlag.pick, .reject, .unflagged], id: \.self) { flag in
        Button(flag.title + " Selection") {
          workspace.applyThumbnailDecision(to: photo.id, flag: flag)
        }.disabled(!thumbnailReady(photo))
      }
      Menu("Stars") {
        ForEach(0...5, id: \.self) { rating in
          Button(rating == 0 ? "Clear Stars" : "\(rating) Stars") {
            workspace.applyThumbnailDecision(to: photo.id, rating: rating)
          }
        }
      }.disabled(!thumbnailReady(photo))
      Divider()
      ForEach([PhotoEditAction.counterclockwise, .clockwise, .horizontal, .vertical], id: \.self) {
        action in
        Button(action.rawValue + " Selection") {
          prepareThumbnail(photo)
          workspace.editSelection(action)
        }.disabled(!thumbnailReady(photo))
      }
      Button("Crop…") {
        prepareThumbnail(photo)
        croppingPhoto = photo
      }.disabled(!thumbnailReady(photo))
      Button("Copy Crop") { copiedCrop = workspace.imageEdits[photo.id]?.crop }.disabled(
        workspace.imageEdits[photo.id]?.crop == nil)
      Button("Paste Crop to Selection") {
        prepareThumbnail(photo)
        pasteCrop()
      }.disabled(copiedCrop == nil || !thumbnailReady(photo))
      Button("Clear Crop from Selection") {
        prepareThumbnail(photo)
        workspace.editSelection(.clearCrop)
      }.disabled(!thumbnailReady(photo))
      Button("Reset Image Edits for Selection") {
        prepareThumbnail(photo)
        workspace.editSelection(.reset)
      }.disabled(!thumbnailReady(photo))
      Divider()
      Button("Edit IPTC & Keywords…") {
        prepareThumbnail(photo)
        showWorkflow(2)
      }
    }
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
  private func thumbnailDecisions(_ photo: PhotoItem, selected: Bool) -> some View {
    let decision = workspace.decisions[photo.id] ?? CullingDecision()
    return HStack(spacing: 0) {
      Menu {
        ForEach([PhotoFlag.pick, .reject, .unflagged], id: \.self) { flag in
          Button(flag.title) {
            workspace.applyThumbnailDecision(to: photo.id, flag: flag)
            gridFocused = true
          }
        }
      } label: {
        Image(systemName: decision.flag.symbol).frame(width: 18, height: 24)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .accessibilityLabel("Flag \(photo.filename)").accessibilityValue(decision.flag.title).help(
        "Flag this photo, or the selected group when this photo is selected. Reject never deletes files."
      )
      ForEach(1...5, id: \.self) { rating in
        Button {
          let current = selected ? workspace.selectionSummary.rating : decision.rating
          workspace.applyThumbnailDecision(to: photo.id, rating: current == rating ? 0 : rating)
          gridFocused = true
        } label: {
          Image(systemName: rating <= decision.rating ? "star.fill" : "star").font(
            .system(size: 11)
          ).frame(maxWidth: .infinity).frame(height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(rating) stars for \(photo.filename)")
          .help(
            "Set \(rating) stars for this photo or selected group. Click the current rating again to clear; flags stay independent."
          )
      }
    }.foregroundStyle(.secondary).disabled(!thumbnailReady(photo))
  }
  private func copyCrop() {
    copiedCrop = workspace.selectedPhoto.flatMap { workspace.imageEdits[$0.id]?.crop }
  }
  private func pasteCrop() { if let copiedCrop { workspace.pasteCrop(copiedCrop) } }

  private func thumbnailInformation(_ photo: PhotoItem) -> some View {
    ForEach(thumbnailLabels) { field in
      let value = field.label(workspace.metadata[photo.id])
      Text(value).font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        .help(field.title + ": " + value)
    }
  }

  private var previewPane: some View {
    VStack(spacing: 6) {
      HStack(spacing: 12) {
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
        Toggle(isOn: $showInspector) { Image(systemName: "info.circle") }
          .toggleStyle(.button).accessibilityLabel("Shooting information")
          .help("Show camera, lens, capture time and dimensions beside the preview.")
        Button {
          showPreview = false
          gridFocused = true
        } label: {
          Image(systemName: "square.grid.3x3")
        }
        .accessibilityLabel("Show contact sheet")
        .help("Show the full contact sheet (Space or Escape).")
      }.buttonStyle(.borderless).padding(.horizontal, 12).padding(.top, 8)
      if let photo = workspace.selectedPhoto {
        HStack {
          Button {
            workspace.editSelection(.counterclockwise)
          } label: {
            Label("Rotate Left", systemImage: "rotate.left")
          }
          Button {
            workspace.editSelection(.clockwise)
          } label: {
            Label("Rotate Right", systemImage: "rotate.right")
          }
          Menu("Mirror") {
            Button("Horizontally") { workspace.editSelection(.horizontal) }
            Button("Vertically") { workspace.editSelection(.vertical) }
          }
          Button("Crop…") { croppingPhoto = workspace.selectedPhoto }
          Spacer()
          Text(workspace.editStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.buttonStyle(.borderless).font(.caption).padding(.horizontal, 12).disabled(
          !workspace.decisionSelectionReady)
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
              edit: workspace.imageEdits[photo.id] ?? PhotoEdit()
            )
            .id("active-\(workspace.sessionID)-\(photo.id)")
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
          if showInspector {
            ScrollView {
              VStack(alignment: .leading, spacing: 8) {
                Text("SHOOTING INFORMATION").font(.caption.weight(.semibold))
                if let metadata = workspace.metadata[photo.id] {
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
            }.frame(width: 220).frame(maxHeight: .infinity)
              .background(Color.white.opacity(0.025))
          }
        }.padding(.horizontal, 12)
        ViewThatFits(in: .horizontal) {
          HStack {
            decisionControls(photo)
            Spacer(minLength: 8)
            shootingSummary(photo)
          }
          decisionControls(photo)
        }.padding(.horizontal, 12).padding(.bottom, 6)
      } else {
        ContentUnavailableView("Select a photo", systemImage: "photo")
      }
    }.background(Color.black.opacity(0.2))
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
      workspace.metadata[photo.id]?.shootingSummary
        ?? (workspace.indexing && photo.fileURL != nil
          ? "Reading shooting information…" : "No shooting information")
    )
    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
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
      Button(workspace.reviewingSelection ? "End Review" : "Review Selection") {
        if workspace.reviewingSelection {
          workspace.endReview()
        } else {
          workspace.reviewSelection()
          showPreview = true
        }
        gridFocused = true
      }.disabled(!workspace.reviewingSelection && workspace.selectedIDs.isEmpty)
        .help(
          "Freeze the selected photos as a review set. Navigation does not change membership; End Review returns to the folder."
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
        systemImage: "checkmark.shield"
      ).lineLimit(1)
      if !workspace.editStatus.isEmpty {
        Text(workspace.editStatus).lineLimit(1).help(
          "Photo-local rotation, mirror and crop saving status.")
      }
      Spacer()
      Text(workspace.selectedPhoto?.filename ?? "No selection").lineLimit(1)
      Text("·  \(workspace.photos.count) photos")
    }
    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 9)
  }

  private func openFolder() {
    guard !choosingFolder && !showingWorkflow && !showingHelp && croppingPhoto == nil else {
      return
    }
    choosingFolder = true
    NSApp.activate()
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

  private func showWorkflow(_ tab: Int) {
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
      await workflowModel.openFolder(directory)
      if folderLibrary.expanded.contains(directory.path) { await folderLibrary.refresh(directory) }
      gridFocused = true
    }
  }
}
