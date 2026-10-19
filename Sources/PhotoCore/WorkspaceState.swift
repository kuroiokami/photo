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
  public private(set) var decisions: [String: CullingDecision] = [:]
  public private(set) var saveStatus: [String: String] = [:]
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
  }

  public func openFolder(_ directory: URL) async {
    let previousID = self.directory == directory ? selectedID : nil
    folderTask?.cancel()
    resetDecisions()
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
      return LoadedPhotos(photos: photos, indices: indices)
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
      photos = loaded.photos
      allPhotos = loaded.photos
      indicesByID = loaded.indices
      selectedIndex = previousID.flatMap { indicesByID[$0] } ?? (photos.isEmpty ? nil : 0)
      loadState = .ready
      folderTask = nil
    } catch {
      guard sessionID == session else { return }
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
    sessionID = UUID()
    directory = nil
    selectedIndex = nil
    photos = SampleLibrary.photos
    allPhotos = photos
    metadata = [:]
    metadataAttempted = []
    indexedCount = 0
    indexing = false
    indicesByID = Self.makeIndex(photos)
    selectedIndex = photos.isEmpty ? nil : 0
    loadState = .ready
  }

  public func select(_ id: PhotoItem.ID?) {
    guard let id else {
      selectedIndex = nil
      return
    }
    guard let index = indicesByID[id] else { return }
    selectedIndex = index
  }

  public func moveSelection(by offset: Int) {
    guard !photos.isEmpty else { return }
    let current = selectedIndex ?? 0
    let movement = min(max(offset, -current), photos.count - 1 - current)
    selectedIndex = current + movement
  }

  public func indexMetadata(using reader: any PhotoMetadataReading) async {
    let session = sessionID
    let snapshot = allPhotos
    indexing = true
    for photo in snapshot {
      guard !Task.isCancelled, sessionID == session else { return }
      // Re-check selection between each low-priority read.
      if let selectedPhoto { await readMetadata(selectedPhoto, using: reader) }
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
    guard sort == .filename || sort == .rating || !indexing else { return }
    let session = sessionID
    let snapshot = allPhotos
    let metadata = metadata
    let ratings = decisions.mapValues(\.rating)
    let ordered = await Task.detached(priority: .userInitiated) {
      sort.ordered(snapshot, metadata: metadata, ratings: ratings)
    }.value
    guard session == sessionID, self.sort == sort else { return }
    let selected = selectedID
    allPhotos = ordered
    photos = ordered.filter { matches($0) }
    indicesByID = Self.makeIndex(photos)
    selectedIndex = selected.flatMap { indicesByID[$0] } ?? (photos.isEmpty ? nil : 0)
  }

  private struct DecisionChange {
    let photo: PhotoItem
    let before: CullingDecision
    let after: CullingDecision
  }

  private func resetDecisions() {
    decisions = [:]
    saveStatus = [:]
    decisionsReady = []
    decisionVersions = [:]
    fileIdentities = [:]
    undoStack = []
    redoStack = []
  }

  public func loadDecisions() async {
    let session = sessionID
    let snapshot = allPhotos
    await DecisionSaveQueue.shared.flush()
    for photo in snapshot {
      guard session == sessionID, !Task.isCancelled else { return }
      if let selectedPhoto { await loadDecision(selectedPhoto, session: session) }
      await loadDecision(photo, session: session)
    }
    guard session == sessionID, !Task.isCancelled else { return }
    if sort == .rating {
      allPhotos = sort.ordered(
        allPhotos, metadata: metadata, ratings: decisions.mapValues(\.rating))
    }
    rebuildVisible(preferred: selectedID)
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
    decisions[photo.id] = entry.decision
    saveStatus[photo.id] = entry.status
    decisionsReady.insert(photo.id)
  }

  private func matches(_ photo: PhotoItem) -> Bool {
    let decision = decisions[photo.id] ?? CullingDecision()
    return flagFilter.includes(decision.flag) && decision.rating >= minimumRating
  }

  private func rebuildVisible(preferred: String?, fallback: [String] = []) {
    photos = allPhotos.filter { matches($0) }
    indicesByID = Self.makeIndex(photos)
    selectedIndex =
      preferred.flatMap { indicesByID[$0] }
      ?? fallback.lazy.compactMap { self.indicesByID[$0] }.first
      ?? (photos.isEmpty ? nil : 0)
  }

  public func setFilter(_ filter: FlagFilter, minimumRating: Int) {
    flagFilter = filter
    self.minimumRating = min(5, max(0, minimumRating))
    rebuildVisible(preferred: selectedID)
  }

  public func applyDecision(rating: Int? = nil, flag: PhotoFlag? = nil, advance: Bool = false) {
    guard let photo = selectedPhoto, decisionsReady.contains(photo.id) else { return }
    let before = decisions[photo.id] ?? CullingDecision()
    let after = CullingDecision(rating: rating ?? before.rating, flag: flag ?? before.flag)
    let index = selectedIndex ?? 0
    let next = index + 1 < photos.count ? photos[index + 1].id : nil
    let previous = index > 0 ? photos[index - 1].id : nil
    if before != after {
      undoStack.append(DecisionChange(photo: photo, before: before, after: after))
      redoStack = []
      decisions[photo.id] = after
      repositionRating(photo)
      persist(photo, after)
    }
    let remains = matches(photo)
    let shouldAdvance = advance || autoAdvance
    if remains, sort != .rating {
      if shouldAdvance { moveSelection(by: 1) }
      return
    }
    // Filter removal already advances. Use pre-action neighbors exactly once.
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
    decisions[change.photo.id] = change.before
    repositionRating(change.photo)
    persist(change.photo, change.before)
    rebuildVisible(preferred: change.photo.id)
  }
  public func redoDecision() {
    guard let change = redoStack.popLast() else { return }
    undoStack.append(change)
    decisions[change.photo.id] = change.after
    repositionRating(change.photo)
    persist(change.photo, change.after)
    rebuildVisible(preferred: change.photo.id)
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
      decisions[photo.id] = entry.decision
      saveStatus[photo.id] = entry.status
      rebuildVisible(preferred: photo.id)
    } catch { saveStatus[photo.id] = error.localizedDescription }
  }

  private struct LoadedPhotos: Sendable {
    let photos: [PhotoItem]
    let indices: [PhotoItem.ID: Int]
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
