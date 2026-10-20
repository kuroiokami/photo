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
  public private(set) var photos: [PhotoItem]
  public private(set) var selectedIDs: Set<String> = []
  public private(set) var groupPairs = false
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
  @ObservationIgnored private var familyMembers: [String: [PhotoItem]] = [:]
  @ObservationIgnored private var allByID: [String: PhotoItem] = [:]
  public var filePhotos: [PhotoItem] { allPhotos }
  public var persistence: DecisionStore { decisionStore }
  public var operationPhotos: [PhotoItem] {
    let chosen = selectedIDs.isEmpty ? Set([selectedID].compactMap { $0 }) : selectedIDs
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
  public var selectionSummary: DecisionSelectionSummary {
    DecisionSelectionSummary(operationPhotos.map { decisions[$0.id] ?? CullingDecision() })
  }
  public var decisionSelectionReady: Bool {
    let targets = operationPhotos
    return !targets.isEmpty && targets.allSatisfy { decisionsReady.contains($0.id) }
  }
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
  public private(set) var metadata: [String: PhotoMetadata] = [:]
  @ObservationIgnored private var decisionRevision = 0
  @ObservationIgnored private var metadataAttempted: Set<String> = []
  public private(set) var indexedCount = 0
  public private(set) var indexing = false
  @ObservationIgnored private var metadataJobs: Set<UUID> = []
  public private(set) var collectionRevision = 0
  public private(set) var sort: PhotoSort = .filename
  @ObservationIgnored private var allPhotos: [PhotoItem] = []
  public private(set) var selectedIndex: Int?
  @ObservationIgnored private var indicesByID: [PhotoItem.ID: Int]
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
    buildFamilies(photos)
  }

  public func openFolder(_ directory: URL, verifiedImages: [URL]? = nil) async {
    let previousID = self.directory == directory ? selectedID : nil
    folderTask?.cancel()
    resetDecisions()
    decisionsLoading = true
    reloadSelection = previousID
    sessionID = UUID()
    let session = sessionID
    self.directory = directory
    selectedIndex = nil
    photos = []
    allPhotos = []
    metadata = [:]
    metadataAttempted = []
    indexedCount = 0
    indexing = false
    indicesByID = [:]
    loadState = .loading
    let fileAccess = fileAccess
    let verified = verifiedImages.map {
      Set($0.map(PhotoPath.canonical))
    }
    // Build models and the lookup table away from the main actor as well as IO.
    let task = Task.detached(priority: .userInitiated) {
      var urls = try await fileAccess.photos(in: directory)
      if let verified {
        urls = urls.map(PhotoPath.canonical).filter {
          verified.contains($0)
        }
      }
      try Task.checkCancellation()
      let photos = urls.map(PhotoItem.init(fileURL:))
      let indices = Self.makeIndex(photos)
      try Task.checkCancellation()
      return LoadedPhotos(
        photos: photos, indices: indices, families: Self.makeFamilies(photos),
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
      allPhotos = loaded.photos
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

  public func showSamples() {
    folderTask?.cancel()
    folderTask = nil
    resetDecisions()
    decisionsLoading = true
    sessionID = UUID()
    directory = nil
    selectedIndex = nil
    allPhotos = SampleLibrary.photos
    buildFamilies(allPhotos)
    photos = flagFilter == .all && minimumRating == 0 ? allPhotos : []
    metadata = [:]
    metadataAttempted = []
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
    let job = UUID()
    metadataJobs.insert(job)
    indexing = true
    defer {
      metadataJobs.remove(job)
      indexing = !metadataJobs.isEmpty
    }
    for photo in snapshot {
      guard !Task.isCancelled, sessionID == session else { return }
      if let selectedPhoto { await readMetadata(selectedPhoto, using: reader) }
      guard !Task.isCancelled, sessionID == session else { return }
      await readMetadata(photo, using: reader)
      guard !Task.isCancelled, sessionID == session else { return }
      indexedCount = metadataAttempted.count
      await Task.yield()
    }
    metadataJobs.remove(job)
    indexing = !metadataJobs.isEmpty
    guard sessionID == session else { return }
    await setSort(sort)
  }

  /// Merge only the explicitly verified arrivals; preserve the current session,
  /// selection, review set, decision history and image-cache identities.
  @discardableResult
  public func publishVerified(_ urls: [URL], in folder: URL, using reader: any PhotoMetadataReading)
    -> Task<Void, Never>?
  {
    guard loadState == .ready,
      directory.map(PhotoPath.canonical) == PhotoPath.canonical(folder)
    else { return nil }
    let parent = PhotoPath.canonical(folder)
    var known = Set(allPhotos.map(\.id))
    let added = urls.compactMap { url -> PhotoItem? in
      let url = PhotoPath.canonical(url)
      guard PhotoPath.canonical(url.deletingLastPathComponent()) == parent,
        PhotoFormats.supports(url)
      else {
        return nil
      }
      let photo = PhotoItem(fileURL: url)
      return known.insert(photo.id).inserted ? photo : nil
    }
    guard !added.isEmpty else { return nil }
    let focused = selectedID
    allPhotos += added
    collectionRevision += 1
    if sort == .filename || sort == .rating {
      allPhotos = sort.ordered(
        allPhotos, metadata: metadata, ratings: decisions.mapValues(\.rating))
    }
    buildFamilies(allPhotos)
    rebuildVisible(preferred: focused)
    let session = sessionID
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
    guard !metadataAttempted.contains(photo.id), let url = photo.fileURL else { return }
    metadataAttempted.insert(photo.id)
    let session = sessionID
    let value = try? await reader.metadata(for: url)
    guard session == sessionID, !Task.isCancelled else { return }
    if let value { metadata[photo.id] = value }
  }

  public func setSort(_ sort: PhotoSort) async {
    self.sort = sort
    guard loadState == .ready else { return }
    guard sort == .filename || sort == .rating || !indexing else { return }
    let session = sessionID
    let snapshot = allPhotos
    let collection = collectionRevision
    let metadata = metadata
    let ratings = decisions.mapValues(\.rating)
    let revision = decisionRevision
    let ordered = await Task.detached(priority: .userInitiated) {
      sort.ordered(snapshot, metadata: metadata, ratings: ratings)
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
    decisionsLoading = true
    let session = sessionID
    let snapshot = allPhotos
    await DecisionSaveQueue.shared.flush()
    for photo in snapshot {
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
      await loadDecision(photo, session: session)
    }
    guard session == sessionID, !Task.isCancelled else { return }
    if sort == .rating {
      allPhotos = sort.ordered(
        allPhotos, metadata: metadata, ratings: decisions.mapValues(\.rating))
    }
    decisionsLoading = false
    rebuildVisible(preferred: selectedID ?? reloadSelection)
    reloadSelection = nil
  }

  private func loadDecision(_ photo: PhotoItem, session: UUID) async {
    guard !decisionsReady.contains(photo.id) else { return }
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
    guard session == sessionID, !Task.isCancelled, !decisionsReady.contains(photo.id) else {
      return
    }
    if let review = entry.sourceReview { sourceReview = review }
    imageEdits[photo.id] = edit
    fileIdentities[photo.id] = entry.identity
    decisionRevision += 1
    decisions[photo.id] = entry.decision
    sourceFields[photo.id] = entry.reviewFields
    if entry.reviewed { sourceReviewedIDs.insert(photo.id) }
    saveStatus[photo.id] = entry.status
    decisionsReady.insert(photo.id)
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
        if change.afterReviewed { sourceReviewedIDs.insert(change.photo.id) }
        sourceFields[change.photo.id] = change.afterFields
        persist(change.photo, change.after, reviewed: change.afterReviewed)
      }
      if sort == .rating {
        if changes.count == 1 {
          repositionRating(photo)
        } else {
          allPhotos = sort.ordered(
            allPhotos, metadata: metadata, ratings: decisions.mapValues(\.rating))
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
    for item in changes { imageEdits[item.photo.id] = item.after }
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
        ? photo.filename.localizedStandardCompare(other.filename) == .orderedAscending
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
      for item in items { imageEdits[item.photo.id] = undo ? item.before : item.after }
      persistEdits(items.map(\.photo))
      rebuildVisible(preferred: focus)
    }
  }
  private func restoreDecision(_ change: DecisionChange, undo: Bool) {
    decisionRevision += 1
    for item in change.items {
      let value = undo ? item.before : item.after
      decisions[item.photo.id] = value
      let reviewed = undo ? item.beforeReviewed : item.afterReviewed
      if reviewed {
        sourceReviewedIDs.insert(item.photo.id)
      } else {
        sourceReviewedIDs.remove(item.photo.id)
      }
      sourceFields[item.photo.id] = undo ? item.beforeFields : item.afterFields
      persist(item.photo, value, reviewed: reviewed)
    }
    if sort == .rating {
      allPhotos = sort.ordered(
        allPhotos, metadata: metadata, ratings: decisions.mapValues(\.rating))
    }
    rebuildVisible(preferred: change.focus)
  }

  private func persist(
    _ photo: PhotoItem, _ decision: CullingDecision, resolveConflict: Bool = false,
    reviewed: Bool = true
  ) {
    guard let url = photo.fileURL else { return }
    let session = sessionID
    let version = decisionVersions[photo.id, default: 0] + 1
    decisionVersions[photo.id] = version
    saveStatus[photo.id] = isSourceReview ? "Saving review…" : "Saving…"
    let review = sourceReview
    let fields = sourceFields[photo.id] ?? []
    let store = decisionStore
    let identity = fileIdentities[photo.id]
    DecisionSaveQueue.shared.enqueue { [weak self] in
      let status: String
      do {
        if let review {
          guard let identity else { throw SourceReviewError.unavailable }
          status = try await store.saveSourceDecision(
            decision, reviewed: reviewed,
            session: review, image: url, identity: identity, fields: fields
          ).status
        } else {
          status = try await store.save(
            decision, for: url, resolveConflict: resolveConflict, expectedIdentity: identity
          ).status
        }
      } catch { status = error.localizedDescription }
      guard let self, self.sessionID == session, self.decisionVersions[photo.id] == version else {
        return
      }
      self.saveStatus[photo.id] = status
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
      saveStatus[photo.id] = entry.status
      repositionRating(photo)
      rebuildVisible(preferred: photo.id)
    } catch { saveStatus[photo.id] = error.localizedDescription }
  }

  private struct LoadedPhotos: Sendable {
    let photos: [PhotoItem]
    let indices: [PhotoItem.ID: Int]
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
