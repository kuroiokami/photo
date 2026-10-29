import Foundation
import Observation

public enum FolderLoadState: Hashable, Sendable {
  case ready
  case loading
  case failed(String)
}

@MainActor
@Observable
public final class WorkspaceState {
  public private(set) var photos: [PhotoItem] {
    didSet {
      if selectedIDs.isEmpty { refreshSelectionPresentation() }
    }
  }
  public private(set) var selectedIDs: Set<String> = [] {
    didSet {
      if selectedIDs != oldValue {
        for id in oldValue where !selectedIDs.contains(id) { thumbnailStates[id]?.selected = false }
        for id in selectedIDs where !oldValue.contains(id) { thumbnailStates[id]?.selected = true }
        refreshSelectionPresentation()
      }
      publishSelectedPending()
    }
  }
  public private(set) var groupPairs = false {
    didSet { refreshSelectionPresentation() }
  }
  public private(set) var sourceReview: SourceReviewSession?
  public var isSourceReview: Bool { sourceReview != nil }
  public var selectedFileIdentities: [URL: String] {
    Dictionary(
      uniqueKeysWithValues: operationPhotos.compactMap { photo in
        guard let url = photo.fileURL, let identity = fileIdentities[photo.id] else { return nil }
        return (url, identity)
      })
  }
  public private(set) var sourceReviewedIDs: Set<String> = []
  private var sourceFields: [String: SourceDecisionFields] = [:]
  public private(set) var reviewIDs: Set<String>?
  public var reviewingSelection: Bool { reviewIDs != nil }
  /// Freeze membership independently of subsequent navigation/selection.
  public func reviewSelection() {
    let ids = Set(operationPhotos.map(\.id))
    guard !ids.isEmpty else { return }
    let focus = selectedID
    reviewIDs = ids
    rebuildVisible(preferred: focus)
    select(selectedID)
  }
  public func endReview() {
    let focus = selectedID
    reviewIDs = nil
    rebuildVisible(preferred: focus)
  }
  private var selectionAnchorID: String?
  @ObservationIgnored private var familyMembers: [String: [PhotoItem]] = [:] {
    didSet { refreshSelectionPresentation() }
  }
  @ObservationIgnored private var allByID: [String: PhotoItem] = [:] {
    didSet {
      thumbnailStates = allByID.mapValues { photo in
        let value = thumbnailStates[photo.id] ?? PhotoThumbnailState()
        if value.selected != selectedIDs.contains(photo.id) {
          value.selected = selectedIDs.contains(photo.id)
        }
        let count = familyMembers[photo.id]?.count ?? 1
        if value.pairedCount != count { value.pairedCount = count }
        return value
      }
      refreshSelectionPresentation()
    }
  }
  @ObservationIgnored private var thumbnailStates: [String: PhotoThumbnailState] = [:]
  @ObservationIgnored public let selectionPresentation = WorkspaceSelectionState()
  public func thumbnailState(for id: String) -> PhotoThumbnailState? { thumbnailStates[id] }

  @ObservationIgnored private var selectionMembershipEvaluations = 0
  private func refreshSelectionPresentation() {
    selectionMembershipEvaluations += 1
    selectionPresentation.replace(operationPhotos, decisions: decisions, ready: decisionsReady)
  }
  private func publishThumbnailDecision(_ id: String) {
    let decision = decisions[id] ?? CullingDecision()
    let ready = decisionsReady.contains(id)
    if let value = thumbnailStates[id] {
      if value.decision != decision { value.decision = decision }
      if value.ready != ready { value.ready = ready }
    }
    selectionPresentation.update(id, decision: decision, ready: ready)
  }
  private func publishThumbnailEdit(_ id: String) {
    let edit = imageEdits[id] ?? PhotoEdit()
    if let value = thumbnailStates[id], value.edit != edit { value.edit = edit }
  }
  public var filePhotos: [PhotoItem] { allPhotos }
  public var persistence: DecisionStore { decisionStore }
  public var operationPhotos: [PhotoItem] {
    let chosen = selectedIDs.isEmpty ? Set([selectedID].compactMap { $0 }) : selectedIDs
    if !groupPairs { return chosen.compactMap { allByID[$0] } }
    let expanded = Set(
      chosen.flatMap { id in groupPairs ? familyMembers[id]?.map(\.id) ?? [id] : [id] })
    return expanded.compactMap { allByID[$0] }
  }
  public func filesRepresented(by representatives: [PhotoItem]) -> [PhotoItem] {
    let expanded = Set(
      representatives.flatMap { photo in
        groupPairs ? familyMembers[photo.id]?.map(\.id) ?? [photo.id] : [photo.id]
      })
    return expanded.compactMap { allByID[$0] }
  }
  public func pairedCount(_ photo: PhotoItem) -> Int { familyMembers[photo.id]?.count ?? 1 }
  public func setGrouping(_ value: Bool) {
    groupPairs = value
    let primary = selectedID.flatMap { familyMembers[$0]?.first?.id }
    rebuildVisible(preferred: value ? primary ?? selectedID : selectedID)
  }
  public var firstSelectedPhoto: PhotoItem? {
    photos.first { selectedIDs.contains($0.id) } ?? selectedPhoto
  }
  public var selectionSummary: DecisionSelectionSummary { selectionPresentation.summary }
  // Retained diagnostic API: readiness is now maintained without selection scans.
  public var selectionReadinessEvaluations: Int { selectionMembershipEvaluations }
  public var decisionSelectionReady: Bool { selectionPresentation.ready }
  public func selectAllVisible() {
    selectedIDs = Set(photos.map(\.id))
    if selectedIndex == nil, !photos.isEmpty { selectedIndex = 0 }
    selectionAnchorID = selectedID
  }
  public func deselectAll() {
    selectedIDs = []
    selectedIndex = nil
    selectionAnchorID = nil
  }
  public func selectGroup(_ ids: Set<String>, focus: String? = nil) {
    selectedIDs = ids.filter { indicesByID[$0] != nil }
    let preferred = focus ?? selectedID
    selectedIndex =
      preferred.flatMap { selectedIDs.contains($0) ? indicesByID[$0] : nil }
      ?? photos.firstIndex { selectedIDs.contains($0.id) }
    selectionAnchorID = selectedID
  }
  public func invertSelection() { selectGroup(Set(photos.map(\.id)).subtracting(selectedIDs)) }
  public func selectRejects() {
    selectGroup(Set(photos.filter { decisions[$0.id]?.flag == .reject }.map(\.id)))
  }

  /// Remove only files actually moved; retain the browsing/cache session.
  public func removeTrashedPhotos(_ urls: [URL]) {
    // A URL's standardized spelling can change after the file disappears
    // (notably /var versus /private/var). Match the existing immutable item IDs.
    let paths = Set(urls.map { PhotoPath.canonical($0).path })
    let removed = Set(
      allPhotos.compactMap { photo -> String? in
        guard let url = photo.fileURL, paths.contains(PhotoPath.canonical(url).path) else {
          return nil
        }
        return photo.id
      })
    guard !removed.isEmpty else { return }
    let order = photos.map(\.id)
    let position = selectedIndex ?? 0
    let fallback = Array(order.dropFirst(position)) + Array(order.prefix(position).reversed())
    let preferred = selectedID.flatMap { removed.contains($0) ? nil : $0 }
    allPhotos.removeAll { removed.contains($0.id) }
    for id in removed { folderLabels.removeValue(forKey: id) }
    collectionRevision += 1
    metadataAttempted.subtract(removed)
    indexedCount = metadataAttempted.count
    buildFamilies(allPhotos)
    selectedIDs.subtract(removed)
    reviewIDs = reviewIDs.map { $0.subtracting(removed) }
    for id in removed {
      decisions.removeValue(forKey: id)
      decisionsReady.remove(id)
      metadata.removeValue(forKey: id)
      imageEdits.removeValue(forKey: id)
      saveStatus.removeValue(forKey: id)
      fileIdentities.removeValue(forKey: id)
      sourceFields.removeValue(forKey: id)
      sourceReviewedIDs.remove(id)
    }
    // File restoration belongs to Finder's Put Back; do not replay old writes
    // against paths that may now be missing or reused.
    undoStack = []
    redoStack = []
    rebuildVisible(preferred: preferred, fallback: fallback)
  }

  public func selectPicks() {
    selectGroup(Set(photos.filter { decisions[$0.id]?.flag == .pick }.map(\.id)))
  }
  public func togglePicks() {
    let targets = operationPhotos
    let allPicked = !targets.isEmpty && targets.allSatisfy { decisions[$0.id]?.flag == .pick }
    applyDecision(flag: allPicked ? .unflagged : .pick)
  }
  public func selectMultiple(_ id: String, extending: Bool, range: Bool) {
    guard let index = indicesByID[id] else { return }
    if range, let anchor = selectionAnchorID.flatMap({ indicesByID[$0] }) ?? selectedIndex {
      let ids = Set(photos[min(anchor, index)...max(anchor, index)].map(\.id))
      selectedIDs = extending ? selectedIDs.union(ids) : ids
    } else if extending {
      if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
      selectionAnchorID = id
    } else {
      selectedIDs = [id]
      selectionAnchorID = id
    }
    selectedIndex =
      selectedIDs.contains(id) ? index : photos.firstIndex { selectedIDs.contains($0.id) }
  }
  public private(set) var decisions: [String: CullingDecision] = [:]
  public private(set) var saveStatus: [String: String] = [:]
  public private(set) var decisionsLoading = false
  @ObservationIgnored private var reloadSelection: String?
  public private(set) var decisionsReady: Set<String> = []
  public var autoAdvance = UserDefaults.standard.bool(forKey: "Photo.autoAdvance") {
    didSet { UserDefaults.standard.set(autoAdvance, forKey: "Photo.autoAdvance") }
  }
  public private(set) var flagFilter: FlagFilter = .all
  public private(set) var minimumRating = 0
  public var totalCount: Int { allPhotos.count }
  @ObservationIgnored private let decisionStore: DecisionStore
  private var undoStack: [WorkspaceChange] = []
  private var redoStack: [WorkspaceChange] = []
  @ObservationIgnored private var fileIdentities: [String: String] = [:]
  @ObservationIgnored private var decisionVersions: [String: Int] = [:]
  public private(set) var imageEdits: [String: PhotoEdit] = [:]
  public private(set) var editStatus = ""
  @ObservationIgnored private var editVersion = 0
  public var undoTitle: String { undoStack.last?.title ?? "Change" }
  public var redoTitle: String { redoStack.last?.title ?? "Change" }
  public var canUndo: Bool { !undoStack.isEmpty }
  public var canRedo: Bool { !redoStack.isEmpty }
  @ObservationIgnored public private(set) var publicationMetrics = WorkspacePublicationMetrics()
  public private(set) var metadata: [String: PhotoMetadata] = [:]
  @ObservationIgnored private var decisionRevision = 0
  @ObservationIgnored private var metadataAttempted: Set<String> = []
  @ObservationIgnored private var pendingMetadata: [String: PhotoMetadata] = [:]
  @ObservationIgnored private var pendingMetadataReads = 0
  @ObservationIgnored private var metadataBudget = PublicationBudget()
  @ObservationIgnored private var decisionBudget = PublicationBudget()
  @ObservationIgnored private var metadataPublishedAt = ContinuousClock.now
  private struct LoadedDecision {
    let entry: DecisionEntry
    let edit: PhotoEdit
  }
  @ObservationIgnored private var pendingDecisions: [String: LoadedDecision] = [:]
  public private(set) var indexedCount = 0
  public private(set) var indexing = false
  @ObservationIgnored private var metadataJobs: Set<UUID> = []
  public private(set) var collectionRevision = 0
  public private(set) var sort: PhotoSort = .filename
  @ObservationIgnored private var allPhotos: [PhotoItem] = []
  public private(set) var selectedIndex: Int? {
    didSet {
      // Focus/order cannot change represented membership for explicit IDs.
      if selectedIDs.isEmpty { refreshSelectionPresentation() }
      publishSelectedPending()
    }
  }

  private func publishSelectedPending() {
    guard let selectedID else { return }
    if pendingMetadata[selectedID] != nil { publishMetadata(ids: [selectedID]) }
    let ids = pendingDecisions.keys.filter { id in
      id == selectedID || selectedIDs.contains(id)
        || (groupPairs
          && (familyMembers[id]?.contains {
            $0.id == selectedID || selectedIDs.contains($0.id)
          } ?? false))
    }
    if !ids.isEmpty { publishDecisions(ids: ids) }
  }
  @ObservationIgnored private var indicesByID: [PhotoItem.ID: Int]
  public private(set) var includesSubfolders = false
  @ObservationIgnored private var folderLabels: [String: String] = [:]
  public func folderLabel(for id: String) -> String? { folderLabels[id] }
  public private(set) var directory: URL?
  public private(set) var loadState: FolderLoadState = .ready
  public private(set) var sessionID = UUID()
  @ObservationIgnored private let fileAccess: any PhotoFileAccess
  @ObservationIgnored private var folderTask: Task<LoadedPhotos, Error>?

  public var selectedPhoto: PhotoItem? {
    guard let selectedIndex, photos.indices.contains(selectedIndex) else { return nil }
    return photos[selectedIndex]
  }
  public var selectedID: PhotoItem.ID? { selectedPhoto?.id }
  public var title: String { directory?.lastPathComponent ?? "Sample collection" }

  public init(
    photos: [PhotoItem] = SampleLibrary.photos,
    fileAccess: any PhotoFileAccess = LocalPhotoFileAccess(),
    decisionStore: DecisionStore = .shared
  ) {
    self.photos = photos
    allPhotos = photos
    self.fileAccess = fileAccess
    self.decisionStore = decisionStore
    indicesByID = Self.makeIndex(photos)
    selectedIndex = photos.isEmpty ? nil : 0
    selectedIDs = Set([selectedID].compactMap { $0 })
    refreshFilenameRanks()
    buildFamilies(photos)
  }

  public func openFolder(
    _ directory: URL, verifiedImages: [URL]? = nil, verificationRoot: URL? = nil,
    includingSubfolders: Bool? = nil
  ) async {
    let trace = PhotoTrace.begin("OpenFolder")
    defer { PhotoTrace.end(trace) }
    let previousID = self.directory == directory ? selectedID : nil
    if let includingSubfolders { includesSubfolders = includingSubfolders }
    let recursive = includesSubfolders
    let protection = decisionStore.sourceProtection
    folderTask?.cancel()
    resetDecisions()
    decisionsLoading = true
    reloadSelection = previousID
    sessionID = UUID()
    let session = sessionID
    self.directory = directory
    publicationMetrics = WorkspacePublicationMetrics()
    metadataBudget = PublicationBudget()
    decisionBudget = PublicationBudget()
    selectedIndex = nil
    photos = []
    allPhotos = []
    folderLabels = [:]
    metadata = [:]
    metadataAttempted = []
    pendingMetadata = [:]
    pendingMetadataReads = 0
    indexedCount = 0
    indexing = false
    indicesByID = [:]
    loadState = .loading
    let fileAccess = fileAccess
    let verificationPath = verificationRoot.map { PhotoPath.canonical($0).pathComponents }
    let verified = verifiedImages.map {
      Set($0.map(PhotoPath.canonical))
    }
    // Build models and the lookup table away from the main actor as well as IO.
    let task = Task.detached(priority: .userInitiated) {
      let trace = PhotoTrace.begin("FolderInventory")
      defer { PhotoTrace.end(trace) }
      var urls = try await fileAccess.photos(in: directory, includingSubfolders: recursive)
      if let verified {
        urls = urls.map(PhotoPath.canonical).filter { url in
          if let verificationPath, !url.pathComponents.starts(with: verificationPath) {
            return true
          }
          return verified.contains(url)
        }
      }
      try Task.checkCancellation()
      let folders: Set<URL> = recursive ? Set(urls.map { $0.deletingLastPathComponent() }) : []
      let context =
        recursive ? try protection.validateCombinedBrowse(root: directory, folders: folders) : nil
      let root = PhotoPath.canonical(directory).pathComponents
      let labels = Dictionary(
        uniqueKeysWithValues: folders.compactMap { folder -> (URL, String)? in
          let path = PhotoPath.canonical(folder).pathComponents
          guard path.starts(with: root), path.count > root.count else { return nil }
          return (folder, path.dropFirst(root.count).joined(separator: "/"))
        })
      let photos = urls.map(PhotoItem.init(fileURL:))
      let indices = Self.makeIndex(photos)
      try Task.checkCancellation()
      return LoadedPhotos(
        photos: photos, context: context,
        folderLabels: recursive
          ? Dictionary(
            uniqueKeysWithValues: photos.compactMap { photo in
              photo.fileURL.flatMap { labels[$0.deletingLastPathComponent()] }.map {
                (photo.id, $0)
              }
            }) : [:], indices: indices, filenameRanks: PhotoSort.filenameRanks(for: photos),
        families: Self.makeFamilies(photos),
        byID: Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
    }
    folderTask = task
    do {
      let loaded = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      guard sessionID == session else { return }
      try Task.checkCancellation()
      folderLabels = loaded.folderLabels
      if recursive { sourceReview = loaded.context }
      allPhotos = loaded.photos
      filenameRanks = loaded.filenameRanks
      filenameRankLocale = Locale.current.identifier
      familyMembers = loaded.families
      allByID = loaded.byID
      photos = flagFilter == .all && minimumRating == 0 ? loaded.photos : []
      indicesByID = photos.isEmpty ? [:] : loaded.indices
      selectedIndex = previousID.flatMap { indicesByID[$0] } ?? (photos.isEmpty ? nil : 0)
      selectedIDs = Set([selectedID].compactMap { $0 })
      if groupPairs { rebuildVisible(preferred: selectedID) }
      loadState = .ready
      // Publish photos first: a busy metadata/save actor must not hold up the
      // selected preview. Decision entries carry protected context before they
      // become actionable, even if this context lookup is still awaiting IO.
      let context = try await decisionStore.sourceReview(for: directory)
      guard sessionID == session else { return }
      sourceReview = context ?? sourceReview
      folderTask = nil
    } catch {
      task.cancel()
      guard sessionID == session else { return }
      decisionsLoading = false
      loadState = .failed(
        error is CancellationError
          ? "Folder loading was cancelled. Reload to try again." : error.localizedDescription)
      folderTask = nil
    }
  }

  private func failCombinedBrowse(_ error: any Error) {
    folderTask?.cancel()
    folderTask = nil
    loadState = .failed(error.localizedDescription)
    sessionID = UUID()
    resetDecisions()
    selectedIndex = nil
    selectedIDs = []
    allPhotos = []
    photos = []
    allByID = [:]
    indicesByID = [:]
    folderLabels = [:]
    filenameRanks = [:]
    metadata = [:]
    metadataAttempted = []
    indexedCount = 0
    indexing = false
  }

  public func showSamples() {
    folderTask?.cancel()
    folderTask = nil
    resetDecisions()
    decisionsLoading = true
    sessionID = UUID()
    directory = nil
    folderLabels = [:]
    publicationMetrics = WorkspacePublicationMetrics()
    metadataBudget = PublicationBudget()
    decisionBudget = PublicationBudget()
    selectedIndex = nil
    allPhotos = SampleLibrary.photos
    refreshFilenameRanks()
    buildFamilies(allPhotos)
    photos = flagFilter == .all && minimumRating == 0 ? allPhotos : []
    metadata = [:]
    metadataAttempted = []
    pendingMetadata = [:]
    pendingMetadataReads = 0
    indexedCount = 0
    indexing = false
    indicesByID = Self.makeIndex(photos)
    selectedIndex = photos.isEmpty ? nil : 0
    selectedIDs = Set([selectedID].compactMap { $0 })
    loadState = .ready
  }

  public func select(_ id: PhotoItem.ID?) {
    guard let id else {
      deselectAll()
      return
    }
    guard let index = indicesByID[id] else { return }
    selectedIndex = index
    selectedIDs = [id]
    selectionAnchorID = id
  }

  public func moveSelection(by offset: Int, extending: Bool = false) {
    guard !photos.isEmpty else { return }
    let current = selectedIndex ?? 0
    let movement = min(max(offset, -current), photos.count - 1 - current)
    if extending {
      if selectionAnchorID == nil { selectionAnchorID = selectedID }
      selectMultiple(photos[current + movement].id, extending: false, range: true)
    } else {
      selectedIndex = current + movement
      selectedIDs = Set([selectedID].compactMap { $0 })
      selectionAnchorID = selectedID
    }
  }

  public func indexMetadata(using reader: any PhotoMetadataReading, expectedSession: UUID? = nil)
    async
  {
    guard expectedSession == nil || expectedSession == sessionID, loadState == .ready else {
      return
    }
    await indexPhotos(allPhotos, using: reader, session: sessionID)
  }

  private func indexPhotos(
    _ snapshot: [PhotoItem], using reader: any PhotoMetadataReading, session: UUID
  ) async {
    let trace = PhotoTrace.begin("MetadataIndex")
    defer { PhotoTrace.end(trace) }
    metadata.reserveCapacity(allPhotos.count)
    let job = UUID()
    metadataJobs.insert(job)
    indexing = true
    defer {
      if sessionID == session { publishMetadata() }
      metadataJobs.remove(job)
      indexing = !metadataJobs.isEmpty
    }
    for photo in snapshot {
      guard !Task.isCancelled, sessionID == session else { return }
      if let selectedPhoto { await readMetadata(selectedPhoto, using: reader) }
      guard !Task.isCancelled, sessionID == session else { return }
      await readMetadata(photo, using: reader, immediate: false)
      guard !Task.isCancelled, sessionID == session else { return }
      if pendingMetadata.count >= metadataBudget.limit || pendingMetadataReads >= 64
        || metadataPublishedAt.duration(to: .now) >= .milliseconds(50)
      {
        publishMetadata()
      }
      await Task.yield()
    }
    while !pendingMetadata.isEmpty {
      guard sessionID == session, !Task.isCancelled else { return }
      publishMetadata()
      await Task.yield()
    }
    guard sessionID == session else { return }
    metadataJobs.remove(job)
    indexing = !metadataJobs.isEmpty
    publishMetadata()
    await setSort(sort)
  }

  /// Merge only the explicitly verified arrivals; preserve the current session,
  /// selection, review set, decision history and image-cache identities.
  @discardableResult
  public func publishVerified(_ urls: [URL], in folder: URL, using reader: any PhotoMetadataReading)
    async -> Task<Void, Never>?
  {
    guard loadState == .ready,
      directory.map(PhotoPath.canonical) == PhotoPath.canonical(folder)
    else { return nil }
    let session = sessionID
    let parent = PhotoPath.canonical(folder)
    var known = Set(allPhotos.map(\.id))
    var added = urls.compactMap { url -> PhotoItem? in
      let url = PhotoPath.canonical(url)
      let container = PhotoPath.canonical(url.deletingLastPathComponent())
      guard
        includesSubfolders
          ? container.pathComponents.starts(with: parent.pathComponents) : container == parent,
        PhotoFormats.supports(url)
      else {
        return nil
      }
      let photo = PhotoItem(fileURL: url)
      return known.insert(photo.id).inserted ? photo : nil
    }
    guard !added.isEmpty else { return nil }
    if includesSubfolders {
      do {
        let protection = decisionStore.sourceProtection
        let folders = Set(added.compactMap { $0.fileURL?.deletingLastPathComponent() })
        let context = try await Task.detached(priority: .utility) {
          try protection.validateCombinedBrowse(root: folder, folders: folders)
        }.value
        guard sessionID == session else { return nil }
        guard context?.id == sourceReview?.id else { throw SourceReviewError.mixedBrowse }
        added.removeAll { allByID[$0.id] != nil }
        guard !added.isEmpty else { return nil }
      } catch {
        if sessionID == session { failCombinedBrowse(error) }
        return nil
      }
      let root = PhotoPath.canonical(folder).pathComponents
      for photo in added {
        guard let url = photo.fileURL else { continue }
        let path = PhotoPath.canonical(url.deletingLastPathComponent()).pathComponents
        if path.count > root.count {
          folderLabels[photo.id] = path.dropFirst(root.count).joined(separator: "/")
        }
      }
    }
    let focused = selectedID
    allPhotos += added
    refreshFilenameRanks()
    collectionRevision += 1
    if sort == .filename || sort == .rating {
      allPhotos = sort.ordered(
        allPhotos, metadata: metadata, ratings: decisions.mapValues(\.rating),
        filenameRanks: filenameRanks)
    }
    buildFamilies(allPhotos)
    rebuildVisible(preferred: focused)
    return Task { [weak self] in
      guard let self else { return }
      await DecisionSaveQueue.shared.flush()
      for photo in added {
        guard self.sessionID == session, !Task.isCancelled else { return }
        await self.loadDecision(photo, session: session)
      }
      guard self.sessionID == session else { return }
      self.rebuildVisible(preferred: self.selectedID)
      await self.indexPhotos(added, using: reader, session: session)
    }
  }

  public func readMetadata(_ photo: PhotoItem, using reader: any PhotoMetadataReading) async {
    await readMetadata(photo, using: reader, immediate: true)
  }

  private func readMetadata(
    _ photo: PhotoItem, using reader: any PhotoMetadataReading, immediate: Bool
  ) async {
    guard allByID[photo.id] != nil, let url = photo.fileURL else { return }
    if pendingMetadata[photo.id] != nil, immediate {
      publishMetadata(ids: [photo.id])
      return
    }
    guard !metadataAttempted.contains(photo.id) else { return }
    metadataAttempted.insert(photo.id)
    let session = sessionID
    let value = try? await reader.metadata(for: url)
    guard session == sessionID else { return }
    guard !Task.isCancelled, allByID[photo.id] != nil else {
      metadataAttempted.remove(photo.id)
      return
    }
    pendingMetadataReads += 1
    if let value { pendingMetadata[photo.id] = value }
    if immediate || selectedID == photo.id { publishMetadata(ids: [photo.id]) }
  }

  private func publishMetadata(ids: [String]? = nil) {
    var updates: [String: PhotoMetadata] = [:]
    let started = ContinuousClock.now
    for id in ids ?? Array(pendingMetadata.keys.prefix(metadataBudget.limit)) {
      if let value = pendingMetadata.removeValue(forKey: id), allByID[id] != nil {
        updates[id] = value
      }
    }
    let progress = metadataAttempted.count
    guard !updates.isEmpty || indexedCount != progress else { return }
    let trace = PhotoTrace.begin("PublishMetadata")
    defer { PhotoTrace.end(trace) }
    if !updates.isEmpty {
      metadata.merge(updates) { _, new in new }
      for (id, metadata) in updates {
        if let value = thumbnailStates[id], value.metadata != metadata { value.metadata = metadata }
      }
    }
    indexedCount = progress
    publicationMetrics.metadata += 1
    let elapsed = started.duration(to: .now)
    let milliseconds =
      Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    publicationMetrics.metadataWork.record(items: updates.count, milliseconds: milliseconds)
    if ids == nil { metadataBudget.record(milliseconds: milliseconds) }
    PhotoTrace.event("MetadataPublished", in: trace)
    if ids == nil {
      pendingMetadataReads = 0
      metadataPublishedAt = .now
    }
  }

  public func setSort(_ sort: PhotoSort) async {
    self.sort = sort
    guard loadState == .ready else { return }
    guard sort == .filename || sort == .rating || !indexing else { return }
    let session = sessionID
    let snapshot = allPhotos
    let collection = collectionRevision
    if filenameRankLocale != Locale.current.identifier { refreshFilenameRanks() }
    let filenameRanks = filenameRanks
    let metadata = metadata
    let ratings = decisions.mapValues(\.rating)
    let revision = decisionRevision
    let ordered = await Task.detached(priority: .userInitiated) {
      sort.ordered(snapshot, metadata: metadata, ratings: ratings, filenameRanks: filenameRanks)
    }.value
    guard session == sessionID, self.sort == sort, !Task.isCancelled else { return }
    if collection != collectionRevision {
      await setSort(sort)
      return
    }
    if sort == .rating, revision != decisionRevision {
      await setSort(sort)
      return
    }
    let selected = selectedID
    allPhotos = ordered
    photos = visiblePhotos(ordered)
    indicesByID = Self.makeIndex(photos)
    selectedIndex = selected.flatMap { indicesByID[$0] } ?? (photos.isEmpty ? nil : 0)
  }

  private enum WorkspaceChange {
    case decision(DecisionChange)
    case edit([EditItemChange], String)
    var title: String {
      switch self {
      case .decision: "Decision"
      case .edit: "Image Edit"
      }
    }
  }
  private struct EditItemChange {
    let photo: PhotoItem
    let before: PhotoEdit
    let after: PhotoEdit
  }
  private struct DecisionItemChange {
    let photo: PhotoItem
    let before: CullingDecision
    let after: CullingDecision
    let beforeFields: SourceDecisionFields
    let afterFields: SourceDecisionFields
    let beforeReviewed: Bool
    let afterReviewed: Bool
  }
  private struct DecisionChange {
    let items: [DecisionItemChange]
    let focus: String
  }
  @ObservationIgnored private var filenameRanks: [String: Int] = [:]
  @ObservationIgnored private var filenameRankLocale = Locale.current.identifier
  private func refreshFilenameRanks() {
    filenameRanks = PhotoSort.filenameRanks(for: allPhotos)
    filenameRankLocale = Locale.current.identifier
  }
  private func buildFamilies(_ photos: [PhotoItem]) {
    familyMembers = Self.makeFamilies(photos)
    allByID = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  }
  private nonisolated static func makeFamilies(_ photos: [PhotoItem]) -> [String: [PhotoItem]] {
    let urls = photos.compactMap(\.fileURL)
    let byURL = Dictionary(
      photos.compactMap { photo in photo.fileURL.map { ($0, photo) } },
      uniquingKeysWith: { first, _ in first })
    var families: [String: [PhotoItem]] = [:]
    for group in (try? PhotoFamily.groups(urls, contents: urls)) ?? [] {
      let members = group.images.compactMap { byURL[$0] }
      for member in members { families[member.id] = members }
    }
    return families
  }

  private func resetDecisions() {
    thumbnailStates = [:]
    pendingDecisions = [:]
    pendingMetadata = [:]
    pendingMetadataReads = 0
    sourceReview = nil
    sourceReviewedIDs = []
    sourceFields = [:]
    reviewIDs = nil
    imageEdits = [:]
    editStatus = ""
    editVersion += 1
    decisions = [:]
    selectedIDs = []
    selectionAnchorID = nil
    familyMembers = [:]
    saveStatus = [:]
    decisionsReady = []
    pendingDecisions = [:]
    decisionsLoading = false
    reloadSelection = nil
    decisionVersions = [:]
    fileIdentities = [:]
    undoStack = []
    redoStack = []
    metadataJobs = []
    collectionRevision += 1
  }

  public func loadDecisions(expectedSession: UUID? = nil) async {
    guard expectedSession == nil || expectedSession == sessionID else { return }
    guard loadState == .ready else { return }
    let trace = PhotoTrace.begin("DecisionIndex")
    defer { PhotoTrace.end(trace) }
    decisionsLoading = true
    let session = sessionID
    let snapshot = allPhotos
    // Avoid synchronized geometric growth/rehashing of these per-file tables
    // inside a small publication. Account for this allocation in index timing.
    imageEdits.reserveCapacity(snapshot.count)
    decisions.reserveCapacity(snapshot.count)
    saveStatus.reserveCapacity(snapshot.count)
    decisionsReady.reserveCapacity(snapshot.count)
    fileIdentities.reserveCapacity(snapshot.count)
    sourceFields.reserveCapacity(snapshot.count)
    await DecisionSaveQueue.shared.flush()
    for start in stride(from: 0, to: snapshot.count, by: 16) {
      guard session == sessionID, !Task.isCancelled else { return }
      if let selectedPhoto {
        let priority =
          groupPairs ? familyMembers[selectedPhoto.id] ?? [selectedPhoto] : [selectedPhoto]
        for member in priority {
          guard session == sessionID, !Task.isCancelled else { return }
          await loadDecision(member, session: session)
        }
      }
      guard session == sessionID, !Task.isCancelled else { return }
      await loadDecisionBatch(
        Array(snapshot[start..<min(start + 16, snapshot.count)]), session: session)
      while session == sessionID, !pendingDecisions.isEmpty {
        guard !Task.isCancelled else { return }
        publishDecisions()
        await Task.yield()
      }
    }
    guard session == sessionID, !Task.isCancelled else { return }
    if sort == .rating {
      allPhotos = sort.ordered(
        allPhotos, metadata: metadata, ratings: decisions.mapValues(\.rating),
        filenameRanks: filenameRanks)
    }
    decisionsLoading = false
    rebuildVisible(preferred: selectedID ?? reloadSelection)
    reloadSelection = nil
  }

  private func loadDecisionBatch(_ batch: [PhotoItem], session: UUID) async {
    let targets = batch.filter {
      allByID[$0.id] != nil && !decisionsReady.contains($0.id) && pendingDecisions[$0.id] == nil
    }
    // Samples have no filesystem identity and need no database transaction.
    for photo in targets where photo.fileURL == nil {
      await loadDecision(photo, session: session, immediate: false)
    }
    let files = targets.filter { $0.fileURL != nil }
    guard !files.isEmpty else { return }
    let results: [Result<(DecisionEntry, PhotoEdit), any Error>]
    do { results = try await decisionStore.loadImageStates(for: files.compactMap(\.fileURL)) } catch
    { results = files.map { _ in .failure(error) } }
    guard session == sessionID, !Task.isCancelled else { return }
    for (photo, result) in zip(files, results) {
      guard allByID[photo.id] != nil, !decisionsReady.contains(photo.id) else { continue }
      switch result {
      case .success(let loaded):
        pendingDecisions[photo.id] = LoadedDecision(entry: loaded.0, edit: loaded.1)
      case .failure(let error):
        pendingDecisions[photo.id] = LoadedDecision(
          entry: DecisionEntry(decision: CullingDecision(), status: error.localizedDescription),
          edit: PhotoEdit())
      }
    }
    if let selectedID, pendingDecisions[selectedID] != nil { publishDecisions(ids: [selectedID]) }
  }

  private func loadDecision(_ photo: PhotoItem, session: UUID, immediate: Bool = true) async {
    guard allByID[photo.id] != nil, !decisionsReady.contains(photo.id) else { return }
    if pendingDecisions[photo.id] != nil {
      if immediate { publishDecisions(ids: [photo.id]) }
      return
    }
    let entry: DecisionEntry
    var edit = PhotoEdit()
    do {
      if let url = photo.fileURL {
        (entry, edit) = try await decisionStore.loadImageState(for: url)
      } else {
        entry = DecisionEntry(decision: CullingDecision(), status: "Sample · not saved")
      }
    } catch {
      entry = DecisionEntry(decision: CullingDecision(), status: error.localizedDescription)
    }
    guard session == sessionID, !Task.isCancelled, allByID[photo.id] != nil,
      !decisionsReady.contains(photo.id)
    else {
      return
    }
    pendingDecisions[photo.id] = LoadedDecision(entry: entry, edit: edit)
    if immediate || selectedID == photo.id { publishDecisions(ids: [photo.id]) }
  }

  private func publishDecisions(ids: [String]? = nil) {
    var loaded: [String: LoadedDecision] = [:]
    let started = ContinuousClock.now
    for id in ids ?? Array(pendingDecisions.keys.prefix(decisionBudget.limit)) {
      if let value = pendingDecisions.removeValue(forKey: id), allByID[id] != nil,
        !decisionsReady.contains(id)
      {
        loaded[id] = value
      }
    }
    guard !loaded.isEmpty else { return }
    let trace = PhotoTrace.begin("PublishDecisions")
    defer { PhotoTrace.end(trace) }
    for (id, value) in loaded { fileIdentities[id] = value.entry.identity }
    if includesSubfolders,
      loaded.values.contains(where: { $0.entry.sourceReview?.id != sourceReview?.id })
    {
      failCombinedBrowse(SourceReviewError.mixedBrowse)
      return
    }
    if let review = loaded.values.compactMap({ $0.entry.sourceReview }).first,
      sourceReview != review
    {
      sourceReview = review
    }
    imageEdits.merge(loaded.mapValues(\.edit)) { _, new in new }
    decisionRevision += 1
    decisions.merge(loaded.mapValues { $0.entry.decision }) { _, new in new }
    sourceFields.merge(loaded.mapValues { $0.entry.reviewFields }) { _, new in new }
    sourceReviewedIDs.formUnion(loaded.filter { $0.value.entry.reviewed }.keys)
    saveStatus.merge(loaded.mapValues { $0.entry.status }) { _, new in new }
    decisionsReady.formUnion(loaded.keys)
    for id in loaded.keys {
      publishThumbnailDecision(id)
      publishThumbnailEdit(id)
    }
    publicationMetrics.decisions += 1
    let elapsed = started.duration(to: .now)
    let milliseconds =
      Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    publicationMetrics.decisionWork.record(items: loaded.count, milliseconds: milliseconds)
    if ids == nil { decisionBudget.record(milliseconds: milliseconds) }
    PhotoTrace.event("DecisionsPublished", in: trace)
    if let selectedID, loaded[selectedID] != nil {
      PhotoTrace.event("SelectedDecisionReady", in: trace)
    }
  }

  private func matches(_ photo: PhotoItem) -> Bool {
    let decision = decisions[photo.id] ?? CullingDecision()
    let representative = !groupPairs || (familyMembers[photo.id]?.first?.id ?? photo.id) == photo.id
    let inReview =
      reviewIDs.map { ids in
        ids.contains(photo.id)
          || (groupPairs && (familyMembers[photo.id]?.contains { ids.contains($0.id) } ?? false))
      } ?? true
    let knownDecision =
      (flagFilter == .all && minimumRating == 0) || decisionsReady.contains(photo.id)
    return representative && inReview && knownDecision && flagFilter.includes(decision.flag)
      && decision.rating >= minimumRating
  }

  private func visiblePhotos(_ candidates: [PhotoItem]) -> [PhotoItem] {
    if decisionsLoading && (flagFilter != .all || minimumRating > 0) { return [] }
    return candidates.filter { matches($0) }
  }

  private func rebuildVisible(preferred: String?, fallback: [String] = []) {
    photos =
      decisionsLoading && (flagFilter != .all || minimumRating > 0)
      ? [] : allPhotos.filter { matches($0) }
    indicesByID = Self.makeIndex(photos)
    selectedIndex =
      preferred.flatMap { indicesByID[$0] }
      ?? fallback.lazy.compactMap { self.indicesByID[$0] }.first
      ?? (photos.isEmpty ? nil : 0)
    selectedIDs.formIntersection(Set(photos.map(\.id)))
    if selectedIDs.isEmpty { selectedIDs = Set([selectedID].compactMap { $0 }) }
  }

  public func setFilter(_ filter: FlagFilter, minimumRating: Int) {
    flagFilter = filter
    self.minimumRating = min(5, max(0, minimumRating))
    rebuildVisible(preferred: selectedID)
  }

  public func applyDecision(
    rating: Int? = nil, flag: PhotoFlag? = nil, advance: Bool = false, allowAutoAdvance: Bool = true
  ) {
    let trace = PhotoTrace.begin("ApplyDecision")
    defer { PhotoTrace.end(trace) }
    guard let photo = selectedPhoto else { return }
    let targets = operationPhotos.isEmpty ? [photo] : operationPhotos
    guard targets.allSatisfy({ decisionsReady.contains($0.id) }) else { return }
    let index = selectedIndex ?? 0
    let next = index + 1 < photos.count ? photos[index + 1].id : nil
    let previous = index > 0 ? photos[index - 1].id : nil
    let changes = targets.compactMap { target -> DecisionItemChange? in
      let before = decisions[target.id] ?? CullingDecision()
      let after = CullingDecision(rating: rating ?? before.rating, flag: flag ?? before.flag)
      let reviewed = sourceReviewedIDs.contains(target.id)
      let beforeFields = sourceFields[target.id] ?? []
      var afterFields = beforeFields
      if isSourceReview {
        if rating != nil { afterFields.insert(.rating) }
        if flag != nil { afterFields.insert(.flag) }
      }
      return before == after && (!isSourceReview || (reviewed && beforeFields == afterFields))
        ? nil
        : DecisionItemChange(
          photo: target, before: before, after: after,
          beforeFields: beforeFields, afterFields: afterFields,
          beforeReviewed: reviewed, afterReviewed: isSourceReview)
    }
    if !changes.isEmpty {
      undoStack.append(.decision(DecisionChange(items: changes, focus: photo.id)))
      redoStack = []
      decisionRevision += 1
      for change in changes {
        decisions[change.photo.id] = change.after
        publishThumbnailDecision(change.photo.id)
        if change.afterReviewed { sourceReviewedIDs.insert(change.photo.id) }
        sourceFields[change.photo.id] = change.afterFields
      }
      persistDecisions(changes.map { ($0.photo, $0.after, $0.afterReviewed) })
      if sort == .rating {
        if changes.count == 1 {
          repositionRating(photo)
        } else {
          allPhotos = sort.ordered(
            allPhotos, metadata: metadata, ratings: decisions.mapValues(\.rating),
            filenameRanks: filenameRanks)
        }
      }
    }
    if selectedIDs.count > 1 {
      rebuildVisible(preferred: photo.id)
      return
    }
    let remains = matches(photo)
    let shouldAdvance = advance || (allowAutoAdvance && autoAdvance)
    if remains, sort != .rating {
      if shouldAdvance { moveSelection(by: 1) }
      return
    }
    rebuildVisible(
      preferred: remains && !shouldAdvance ? photo.id : nil,
      fallback: [next, remains ? photo.id : previous].compactMap { $0 })
  }

  /// Direct tile controls retain a selected batch and suppress automatic advance.
  public func applyThumbnailDecision(to id: String, rating: Int? = nil, flag: PhotoFlag? = nil) {
    guard decisionsReady.contains(id) else { return }
    if !selectedIDs.contains(id) { selectMultiple(id, extending: false, range: false) }
    applyDecision(rating: rating, flag: flag, allowAutoAdvance: false)
  }
  public func editSelection(_ action: PhotoEditAction) {
    changeEdits(operationPhotos) { $0.applying(action) }
  }
  public func setCrop(_ crop: PhotoCrop?, for photo: PhotoItem) {
    changeEdits(filesRepresented(by: [photo])) { value in
      var result = value
      result.crop = crop
      return result
    }
  }
  public func pasteCrop(_ crop: PhotoCrop) {
    changeEdits(operationPhotos) { value in
      var result = value
      result.crop = crop
      return result
    }
  }
  private func changeEdits(_ targets: [PhotoItem], transform: (PhotoEdit) -> PhotoEdit) {
    guard !targets.isEmpty, targets.allSatisfy({ decisionsReady.contains($0.id) }) else { return }
    let changes = targets.compactMap { photo -> EditItemChange? in
      let before = imageEdits[photo.id] ?? PhotoEdit()
      let after = transform(before)
      return before == after ? nil : EditItemChange(photo: photo, before: before, after: after)
    }
    guard !changes.isEmpty else { return }
    for item in changes {
      imageEdits[item.photo.id] = item.after
      publishThumbnailEdit(item.photo.id)
    }
    undoStack.append(.edit(changes, selectedID ?? changes[0].photo.id))
    redoStack = []
    persistEdits(changes.map(\.photo))
  }
  public func retryImageEditSave() { persistEdits(operationPhotos) }
  private func persistEdits(_ photos: [PhotoItem]) {
    editVersion += 1
    let version = editVersion
    let session = sessionID
    let writes = photos.compactMap { photo -> ImageEditWrite? in
      guard let image = photo.fileURL, let identity = fileIdentities[photo.id] else { return nil }
      return ImageEditWrite(
        image: image, identity: identity, edit: imageEdits[photo.id] ?? PhotoEdit())
    }
    guard !writes.isEmpty else {
      editStatus = "Sample edits · not saved"
      return
    }
    editStatus = "Saving image edits…"
    let store = decisionStore
    let review = sourceReview
    DecisionSaveQueue.shared.enqueue { [weak self] in
      let status: String
      do {
        if let review {
          try await store.saveSourceEdits(writes, session: review)
        } else {
          try await store.saveImageEdits(writes)
        }
        status = review == nil ? "Image edits saved in Photo" : "Review edits saved on this Mac"
      } catch { status = error.localizedDescription }
      guard let self, self.sessionID == session, self.editVersion == version else { return }
      self.editStatus = status
    }
  }

  private func repositionRating(_ photo: PhotoItem) {
    guard sort == .rating, let old = allPhotos.firstIndex(where: { $0.id == photo.id }) else {
      return
    }
    allPhotos.remove(at: old)
    var low = 0
    var high = allPhotos.count
    let rating = decisions[photo.id]?.rating ?? 0
    while low < high {
      let middle = (low + high) / 2
      let other = allPhotos[middle]
      let otherRating = decisions[other.id]?.rating ?? 0
      let before =
        rating == otherRating
        ? (filenameRanks[photo.id, default: Int.max] < filenameRanks[other.id, default: Int.max])
        : rating > otherRating
      if before { high = middle } else { low = middle + 1 }
    }
    allPhotos.insert(photo, at: low)
  }

  public func undoDecision() {
    guard let change = undoStack.popLast() else { return }
    redoStack.append(change)
    restore(change, undo: true)
  }
  public func redoDecision() {
    guard let change = redoStack.popLast() else { return }
    undoStack.append(change)
    restore(change, undo: false)
  }
  private func restore(_ change: WorkspaceChange, undo: Bool) {
    switch change {
    case .decision(let decision): restoreDecision(decision, undo: undo)
    case .edit(let items, let focus):
      for item in items {
        imageEdits[item.photo.id] = undo ? item.before : item.after
        publishThumbnailEdit(item.photo.id)
      }
      persistEdits(items.map(\.photo))
      rebuildVisible(preferred: focus)
    }
  }
  private func restoreDecision(_ change: DecisionChange, undo: Bool) {
    decisionRevision += 1
    for item in change.items {
      let value = undo ? item.before : item.after
      decisions[item.photo.id] = value
      publishThumbnailDecision(item.photo.id)
      let reviewed = undo ? item.beforeReviewed : item.afterReviewed
      if reviewed {
        sourceReviewedIDs.insert(item.photo.id)
      } else {
        sourceReviewedIDs.remove(item.photo.id)
      }
      sourceFields[item.photo.id] = undo ? item.beforeFields : item.afterFields
    }
    persistDecisions(
      change.items.map { item in
        (
          item.photo, undo ? item.before : item.after,
          undo ? item.beforeReviewed : item.afterReviewed
        )
      })
    if sort == .rating {
      allPhotos = sort.ordered(
        allPhotos, metadata: metadata, ratings: decisions.mapValues(\.rating),
        filenameRanks: filenameRanks)
    }
    rebuildVisible(preferred: change.focus)
  }

  private struct DecisionSaveSnapshot {
    let id: String
    let version: Int
    let request: DecisionWrite
    let reviewed: Bool
    let fields: SourceDecisionFields
  }
  private func persist(
    _ photo: PhotoItem, _ decision: CullingDecision, resolveConflict: Bool = false,
    reviewed: Bool = true
  ) {
    persistDecisions([(photo, decision, reviewed)], resolveConflict: resolveConflict)
  }
  private func persistDecisions(
    _ updates: [(PhotoItem, CullingDecision, Bool)], resolveConflict: Bool = false
  ) {
    let session = sessionID
    let review = sourceReview
    var requests: [DecisionSaveSnapshot] = []
    requests.reserveCapacity(updates.count)
    for (photo, decision, reviewed) in updates {
      guard let url = photo.fileURL else { continue }
      let version = decisionVersions[photo.id, default: 0] + 1
      decisionVersions[photo.id] = version
      saveStatus[photo.id] = review == nil ? "Saving…" : "Saving review…"
      requests.append(
        DecisionSaveSnapshot(
          id: photo.id, version: version,
          request: DecisionWrite(
            image: url, decision: decision, expectedIdentity: fileIdentities[photo.id],
            resolveConflict: resolveConflict),
          reviewed: reviewed, fields: sourceFields[photo.id] ?? []))
    }
    guard !requests.isEmpty else { return }
    let snapshot = requests
    let store = decisionStore
    DecisionSaveQueue.shared.enqueue { [weak self] in
      for start in stride(from: 0, to: snapshot.count, by: DecisionStore.decisionBatchLimit) {
        let chunk = Array(
          snapshot[start..<min(start + DecisionStore.decisionBatchLimit, snapshot.count)])
        let results: [Result<DecisionEntry, any Error>]
        do {
          if let review {
            var values = chunk.map { _ in
              Result<DecisionEntry, any Error>.failure(SourceReviewError.unavailable)
            }
            var writes: [SourceDecisionWrite] = []
            var indices: [Int] = []
            for (index, value) in chunk.enumerated() {
              guard let identity = value.request.expectedIdentity else { continue }
              indices.append(index)
              writes.append(
                SourceDecisionWrite(
                  image: value.request.image, identity: identity, decision: value.request.decision,
                  reviewed: value.reviewed, fields: value.fields))
            }
            let saved = try await store.saveSourceDecisions(writes, session: review)
            for (index, result) in zip(indices, saved) { values[index] = result }
            results = values
          } else {
            results = try await store.saveDecisions(chunk.map(\.request))
          }
        } catch { results = chunk.map { _ in .failure(error) } }
        if let self, self.sessionID == session {
          for (value, result) in zip(chunk, results)
          where self.decisionVersions[value.id] == value.version {
            switch result {
            case .success(let entry): self.saveStatus[value.id] = entry.status
            case .failure(let error): self.saveStatus[value.id] = error.localizedDescription
            }
          }
        }
        // The store releases its transaction/registry boundary before this yield.
        await Task.yield()
      }
    }
  }

  public func retrySync(useLocal: Bool = false) {
    guard let photo = selectedPhoto else { return }
    persist(
      photo, decisions[photo.id] ?? CullingDecision(), resolveConflict: useLocal,
      reviewed: sourceReviewedIDs.contains(photo.id))
  }

  public func useExternalDecision() async {
    guard !isSourceReview else { return }
    guard let photo = selectedPhoto, let url = photo.fileURL else { return }
    let session = sessionID
    let identity = fileIdentities[photo.id]
    await DecisionSaveQueue.shared.flush()
    guard session == sessionID else { return }
    do {
      let entry = try await decisionStore.useExternal(for: url, expectedIdentity: identity)
      guard session == sessionID else { return }
      decisionRevision += 1
      decisions[photo.id] = entry.decision
      publishThumbnailDecision(photo.id)
      saveStatus[photo.id] = entry.status
      repositionRating(photo)
      rebuildVisible(preferred: photo.id)
    } catch { saveStatus[photo.id] = error.localizedDescription }
  }

  private struct LoadedPhotos: Sendable {
    let photos: [PhotoItem]
    let context: SourceReviewSession?
    let folderLabels: [String: String]
    let indices: [PhotoItem.ID: Int]
    let filenameRanks: [String: Int]
    let families: [String: [PhotoItem]]
    let byID: [String: PhotoItem]
  }

  private nonisolated static func makeIndex(_ photos: [PhotoItem]) -> [PhotoItem.ID: Int] {
    var indices: [PhotoItem.ID: Int] = [:]
    indices.reserveCapacity(photos.count)
    for (index, photo) in photos.enumerated() where indices[photo.id] == nil {
      indices[photo.id] = index
    }
    return indices
  }

}
