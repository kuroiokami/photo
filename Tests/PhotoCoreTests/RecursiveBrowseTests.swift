import Foundation
import PhotoCore
import Testing

private struct TreeMetadata: PhotoMetadataReading {
  func metadata(for file: URL) async throws -> PhotoMetadata {
    PhotoMetadata(pixelWidth: 100, pixelHeight: 80)
  }
}
private struct BrowseTree {
  let root: URL
  let shoot: URL
  let protection: SourceProtection
  let store: DecisionStore
  init() throws {
    root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
      UUID().uuidString)
    shoot = root.appendingPathComponent("Shoot")
    try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
    protection = SourceProtection(registryURL: root.appendingPathComponent("Local/registry.json"))
    store = DecisionStore(
      databaseURL: root.appendingPathComponent("Local/db"), sourceProtection: protection)
  }
  func file(_ path: String) throws -> URL {
    let url = shoot.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("original source".utf8).write(to: url)
    return PhotoPath.canonical(url)
  }
}

private actor DelayedTreeAccess: PhotoFileAccess {
  let delayed: URL
  let immediate: URL
  var continuation: CheckedContinuation<[URL], Never>?
  var began: CheckedContinuation<Void, Never>?
  init(delayed: URL, immediate: URL) {
    self.delayed = delayed
    self.immediate = immediate
  }
  func photos(in directory: URL) async throws -> [URL] { [immediate] }
  func photos(in directory: URL, includingSubfolders: Bool) async throws -> [URL] {
    guard includingSubfolders else { return [immediate] }
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      began?.resume()
      began = nil
    }
  }
  func waitForRecursiveRead() async {
    if continuation != nil { return }
    await withCheckedContinuation { began = $0 }
  }
  func release() {
    continuation?.resume(returning: [delayed])
    continuation = nil
  }
}

@MainActor
struct RecursiveBrowseTests {
  @Test func recursiveInventorySkipsHiddenPackagesAndLinksAndOrdersDuplicateNamesDeterministically()
    async throws
  {
    let tree = try BrowseTree()
    defer { try? FileManager.default.removeItem(at: tree.root) }
    let a = try tree.file("Card A/Frame10.jpeg")
    let b = try tree.file("Card B/Frame10.jpeg")
    let c = try tree.file("Card A/Day2/Frame2.JPG")
    let direct = try tree.file("Cover.png")
    _ = try tree.file(".Hidden/private.jpg")
    _ = try tree.file("Card A/.hidden.jpg")
    _ = try tree.file("Library.bundle/inside.jpg")
    let outside = tree.root.appendingPathComponent("outside.jpg")
    try Data().write(to: outside)
    try FileManager.default.createSymbolicLink(
      at: tree.shoot.appendingPathComponent("alias.jpg"), withDestinationURL: outside)
    try FileManager.default.createSymbolicLink(
      at: tree.shoot.appendingPathComponent("Loop"), withDestinationURL: tree.shoot)
    let access = LocalPhotoFileAccess()
    #expect(try await access.photos(in: tree.shoot).map(PhotoPath.canonical) == [direct])
    let recursive = try await access.photos(in: tree.shoot, includingSubfolders: true)
    #expect(recursive.map(PhotoPath.canonical) == [direct, c, a, b])
    let cancelled = Task {
      try Task.checkCancellation()
      return try await access.photos(in: tree.shoot, includingSubfolders: true)
    }
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
  }

  @Test func combinedDecisionsKeepDuplicateFilenamesIndependentAndPairsWithinTheirOwnFolders()
    async throws
  {
    let tree = try BrowseTree()
    defer { try? FileManager.default.removeItem(at: tree.root) }
    let direct = try tree.file("Cover.jpg")
    let a = try tree.file("Card A/Frame.ARW")
    let aj = try tree.file("Card A/Frame.JPG")
    let b = try tree.file("Card B/Frame.ARW")
    let bj = try tree.file("Card B/Frame.JPG")
    let state = WorkspaceState(photos: [], decisionStore: tree.store)
    state.autoAdvance = false
    await state.openFolder(tree.shoot, includingSubfolders: true)
    await state.loadDecisions()
    #expect(state.photos.count == 5 && state.includesSubfolders)
    let aID = PhotoItem(fileURL: a).id
    let bID = PhotoItem(fileURL: b).id
    #expect(state.folderLabel(for: aID) == "Card A")
    #expect(state.folderLabel(for: bID) == "Card B")
    state.setGrouping(true)
    #expect(state.photos.count == 3)
    state.select(aID)
    state.applyDecision(rating: 4, flag: .pick)
    #expect(state.decisions[PhotoItem(fileURL: aj).id]?.rating == 4)
    #expect(
      state.decisions[bID]?.rating == 0
        && state.decisions[PhotoItem(fileURL: bj).id]?.flag == .unflagged)
    state.selectGroup([aID, bID])
    #expect(state.selectionSummary.fileCount == 4)
    state.applyDecision(flag: .reject)
    state.undoDecision()
    #expect(state.decisions[aID]?.flag == .pick && state.decisions[bID]?.flag == .unflagged)
    await state.setSort(.rating)
    state.setFilter(.pick, minimumRating: 3)
    #expect(state.photos.map(\.id) == [aID])
    state.setFilter(.all, minimumRating: 0)
    state.select(PhotoItem(fileURL: direct).id)
    await DecisionSaveQueue.shared.flush()
    await state.openFolder(tree.shoot, includingSubfolders: false)
    await state.loadDecisions()
    #expect(state.photos.map(\.fileURL) == [direct] && !state.includesSubfolders)
    for url in [direct, a, aj, b, bj] {
      #expect(try Data(contentsOf: url) == Data("original source".utf8))
    }
  }

  @Test func verifiedParentScopeNeverPublishesUnverifiedSiblingsAndKeepsNewFolderLabels()
    async throws
  {
    let tree = try BrowseTree()
    defer { try? FileManager.default.removeItem(at: tree.root) }
    let a = try tree.file("Card A/a.jpg")
    let b = try tree.file("Card B/b.jpg")
    _ = try tree.file("Card B/unverified.jpg")
    let state = WorkspaceState(photos: [], decisionStore: tree.store)
    await state.openFolder(tree.shoot, verifiedImages: [a], includingSubfolders: true)
    await state.loadDecisions()
    #expect(state.photos.map(\.fileURL) == [a])
    async let first = state.publishVerified([b], in: tree.shoot, using: TreeMetadata())
    async let duplicate = state.publishVerified([b], in: tree.shoot, using: TreeMetadata())
    let arrivals = await (first, duplicate)
    await arrivals.0?.value
    await arrivals.1?.value
    #expect((arrivals.0 == nil) != (arrivals.1 == nil))
    #expect(Set(state.filePhotos.compactMap(\.fileURL)) == [a, b])
    #expect(state.folderLabel(for: PhotoItem(fileURL: b).id) == "Card B")
    let session = state.sessionID
    await state.openFolder(b.deletingLastPathComponent(), includingSubfolders: false)
    #expect(state.sessionID != session)
    #expect(await state.publishVerified([a], in: tree.shoot, using: TreeMetadata()) == nil)
  }

  @Test func completedVerifiedDescendantsStillPublishWhenTheIngestCallerWasCancelled() async throws
  {
    let tree = try BrowseTree()
    defer { try? FileManager.default.removeItem(at: tree.root) }
    let image = try tree.file("Card A/completed.jpg")
    let state = WorkspaceState(photos: [], decisionStore: tree.store)
    await state.openFolder(tree.shoot, verifiedImages: [], includingSubfolders: true)
    let cancelledIngest = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      #expect(Task.isCancelled)
      await state.publishVerified([image], in: tree.shoot, using: TreeMetadata())?.value
    }
    await cancelledIngest.value
    #expect(state.filePhotos.map(\.filename) == ["completed.jpg"])
    #expect(state.folderLabel(for: PhotoItem(fileURL: image).id) == "Card A")
    #expect(state.decisionSelectionReady)
  }

  @Test func aLateRecursiveInventoryCannotReplaceANewerDirectFolder() async throws {
    let tree = try BrowseTree()
    defer { try? FileManager.default.removeItem(at: tree.root) }
    let old = try tree.file("Card A/old.jpg")
    let next = try tree.file("Card B/current.jpg")
    let access = DelayedTreeAccess(delayed: old, immediate: next)
    let state = WorkspaceState(photos: [], fileAccess: access, decisionStore: tree.store)
    let pending = Task { await state.openFolder(tree.shoot, includingSubfolders: true) }
    await access.waitForRecursiveRead()
    await state.openFolder(next.deletingLastPathComponent(), includingSubfolders: false)
    await access.release()
    await pending.value
    #expect(!state.includesSubfolders && state.photos.map(\.filename) == ["current.jpg"])
    #expect(state.folderLabel(for: try #require(state.selectedID)) == nil)
  }

  @Test func protectionActivatedDuringIndexingInvalidatesTheCombinedCollection() async throws {
    let tree = try BrowseTree()
    defer { try? FileManager.default.removeItem(at: tree.root) }
    let image = try tree.file("Card/DCIM/source.jpg")
    _ = try tree.file("Working/a.jpg")
    let state = WorkspaceState(photos: [], decisionStore: tree.store)
    await state.openFolder(tree.shoot, includingSubfolders: true)
    #expect(state.photos.count == 2)
    await state.indexMetadata(using: TreeMetadata())
    #expect(state.metadata.count == 2)
    _ = try await tree.store.beginSourceReview(tree.shoot.appendingPathComponent("Card"))
    await state.loadDecisions()
    guard case .failed = state.loadState else {
      Issue.record("Changed source boundary must invalidate the collection")
      return
    }
    #expect(state.photos.isEmpty && state.operationPhotos.isEmpty)
    #expect(state.metadata.isEmpty && state.indexedCount == 0 && !state.indexing)
    #expect(!state.decisionSelectionReady)
    state.applyDecision(flag: .reject)
    await DecisionSaveQueue.shared.flush()
    #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: image).path))
  }

  @Test func combinedParentCannotMixProtectedSourceContextsButProtectedRootCanIncludeChildren()
    async throws
  {
    let tree = try BrowseTree()
    defer { try? FileManager.default.removeItem(at: tree.root) }
    let source = try tree.file("Card/DCIM/source.jpg")
    _ = try tree.file("Working/other.jpg")
    let session = try await tree.store.beginSourceReview(tree.shoot.appendingPathComponent("Card"))
    let state = WorkspaceState(photos: [], decisionStore: tree.store)
    await state.openFolder(tree.shoot, includingSubfolders: true)
    guard case .failed(let message) = state.loadState else {
      Issue.record("Mixed protected source should be unavailable")
      return
    }
    #expect(message.contains("protected") && state.photos.isEmpty)
    await state.openFolder(session.root, includingSubfolders: true)
    await state.loadDecisions()
    #expect(state.photos.count == 1 && state.isSourceReview)
    state.applyDecision(rating: 5, flag: .pick)
    await DecisionSaveQueue.shared.flush()
    #expect(try await tree.store.loadSourceReview(session, image: source).0.decision.rating == 5)
    #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: source).path))
    #expect(try Data(contentsOf: source) == Data("original source".utf8))
  }
}
