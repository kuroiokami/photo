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
  private var undoStack: [DecisionChange] = []
  private var redoStack: [DecisionChange] = []
  @ObservationIgnored private var fileIdentities: [String: String] = [:]
  @ObservationIgnored private var decisionVersions: [String: Int] = [:]
  public var canUndo: Bool { !undoStack.isEmpty }
  public var canRedo: Bool { !redoStack.isEmpty }
  public private(set) var metadata: [String: PhotoMetadata] = [:]
  @ObservationIgnored private var decisionRevision = 0
  @ObservationIgnored private var metadataAttempted: Set<String> = []
  public private(set) var indexedCount = 0
  public private(set) var indexing = false
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

  public func openFolder(_ directory: URL) async {
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
    // Build models and the lookup table away from the main actor as well as IO.
    let task = Task.detached(priority: .userInitiated) {
      let urls = try await fileAccess.photos(in: directory)
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
      folderTask = nil
    } catch {
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
    guard expectedSession == nil || expectedSession == sessionID else { return }
    guard loadState == .ready else { return }
    let session = sessionID
    let snapshot = allPhotos
    indexing = true
    for photo in snapshot {
      guard !Task.isCancelled, sessionID == session else { return }
      // Re-check selection between each low-priority read.
      if let selectedPhoto { await readMetadata(selectedPhoto, using: reader) }
      guard !Task.isCancelled, sessionID == session else { return }
      await readMetadata(photo, using: reader)
      guard !Task.isCancelled, sessionID == session else { return }
      indexedCount += 1
      await Task.yield()
    }
    guard sessionID == session else { return }
    indexing = false
    await setSort(sort)
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
    let metadata = metadata
    let ratings = decisions.mapValues(\.rating)
    let revision = decisionRevision
    let ordered = await Task.detached(priority: .userInitiated) {
      sort.ordered(snapshot, metadata: metadata, ratings: ratings)
    }.value
    guard session == sessionID, self.sort == sort else { return }
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

  private struct DecisionItemChange {
    let photo: PhotoItem
    let before: CullingDecision
    let after: CullingDecision
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
    do {
      if let url = photo.fileURL {
        entry = try await decisionStore.load(for: url)
      } else {
        entry = DecisionEntry(decision: CullingDecision(), status: "Sample · not saved")
      }
    } catch {
      entry = DecisionEntry(decision: CullingDecision(), status: error.localizedDescription)
    }
    guard session == sessionID, !Task.isCancelled, !decisionsReady.contains(photo.id) else {
      return
    }
    fileIdentities[photo.id] = entry.identity
    decisionRevision += 1
    decisions[photo.id] = entry.decision
    saveStatus[photo.id] = entry.status
    decisionsReady.insert(photo.id)
  }

  private func matches(_ photo: PhotoItem) -> Bool {
    let decision = decisions[photo.id] ?? CullingDecision()
    let representative = !groupPairs || (familyMembers[photo.id]?.first?.id ?? photo.id) == photo.id
    return representative && flagFilter.includes(decision.flag) && decision.rating >= minimumRating
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

  public func applyDecision(rating: Int? = nil, flag: PhotoFlag? = nil, advance: Bool = false) {
    guard let photo = selectedPhoto else { return }
    let targets = operationPhotos.isEmpty ? [photo] : operationPhotos
    guard targets.allSatisfy({ decisionsReady.contains($0.id) }) else { return }
    let index = selectedIndex ?? 0
    let next = index + 1 < photos.count ? photos[index + 1].id : nil
    let previous = index > 0 ? photos[index - 1].id : nil
    let changes = targets.compactMap { target -> DecisionItemChange? in
      let before = decisions[target.id] ?? CullingDecision()
      let after = CullingDecision(rating: rating ?? before.rating, flag: flag ?? before.flag)
      return before == after ? nil : DecisionItemChange(photo: target, before: before, after: after)
    }
    if !changes.isEmpty {
      undoStack.append(DecisionChange(items: changes, focus: photo.id))
      redoStack = []
      decisionRevision += 1
      for change in changes {
        decisions[change.photo.id] = change.after
        persist(change.photo, change.after)
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
    let shouldAdvance = advance || autoAdvance
    if remains, sort != .rating {
      if shouldAdvance { moveSelection(by: 1) }
      return
    }
    rebuildVisible(
      preferred: remains && !shouldAdvance ? photo.id : nil,
      fallback: [next, remains ? photo.id : previous].compactMap { $0 })
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
  private func restore(_ change: DecisionChange, undo: Bool) {
    decisionRevision += 1
    for item in change.items {
      let value = undo ? item.before : item.after
      decisions[item.photo.id] = value
      persist(item.photo, value)
    }
    if sort == .rating {
      allPhotos = sort.ordered(
        allPhotos, metadata: metadata, ratings: decisions.mapValues(\.rating))
    }
    rebuildVisible(preferred: change.focus)
  }

  private func persist(
    _ photo: PhotoItem, _ decision: CullingDecision, resolveConflict: Bool = false
  ) {
    guard let url = photo.fileURL else { return }
    let session = sessionID
    let version = decisionVersions[photo.id, default: 0] + 1
    decisionVersions[photo.id] = version
    saveStatus[photo.id] = "Saving…"
    let store = decisionStore
    let identity = fileIdentities[photo.id]
    DecisionSaveQueue.shared.enqueue { [weak self] in
      let status: String
      do {
        status = try await store.save(
          decision, for: url, resolveConflict: resolveConflict, expectedIdentity: identity
        ).status
      } catch { status = error.localizedDescription }
      guard let self, self.sessionID == session, self.decisionVersions[photo.id] == version else {
        return
      }
      self.saveStatus[photo.id] = status
    }
  }

  public func retrySync(useLocal: Bool = false) {
    guard let photo = selectedPhoto else { return }
    persist(photo, decisions[photo.id] ?? CullingDecision(), resolveConflict: useLocal)
  }

  public func useExternalDecision() async {
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
