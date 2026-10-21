import Foundation
import PhotoCore
import Testing

private actor PausedIndexReader: PhotoMetadataReading {
  private let pauseAt: Int
  private var calls = 0
  private var paused: CheckedContinuation<Void, Never>?
  private var observer: CheckedContinuation<Void, Never>?
  init(pauseAt: Int = 8) { self.pauseAt = pauseAt }
  func metadata(for file: URL) async throws -> PhotoMetadata {
    calls += 1
    if calls == pauseAt {
      await withCheckedContinuation { continuation in
        paused = continuation
        observer?.resume()
        observer = nil
      }
    }
    try Task.checkCancellation()
    var value = PhotoMetadata(pixelWidth: 100, pixelHeight: 80)
    value.iso = Double(file.deletingPathExtension().lastPathComponent) ?? 0
    return value
  }
  func waitUntilPaused() async {
    if paused != nil { return }
    await withCheckedContinuation { observer = $0 }
  }
  func resume() {
    paused?.resume()
    paused = nil
  }
}

@MainActor
struct BackgroundPublicationTests {
  private func photos(_ count: Int) -> [PhotoItem] {
    (0..<count).map { PhotoItem(fileURL: URL(fileURLWithPath: "/publication/\($0).jpg")) }
  }

  @Test func selectingBufferedMetadataPublishesWhileAnUnrelatedReadIsBlocked() async {
    let items = photos(20)
    let state = WorkspaceState(photos: items)
    let reader = PausedIndexReader()
    let indexing = Task { await state.indexMetadata(using: reader) }
    await reader.waitUntilPaused()
    #expect(state.metadata[items[0].id]?.iso == 0)
    state.select(items[5].id)
    // Selection must promote an already-read result without waiting on the reader.
    #expect(state.metadata[items[5].id]?.iso == 5)
    state.removeTrashedPhotos([items[3].fileURL!])
    await state.setSort(.iso)
    await reader.resume()
    await indexing.value
    #expect(state.selectedID == items[5].id)
    #expect(state.metadata[items[3].id] == nil)
    #expect(state.metadata.count == 19)
    #expect(state.indexedCount == 19)
    #expect(state.photos.map(\.id) == items.filter { $0.id != items[3].id }.map(\.id))
    #expect(!state.indexing)
  }

  @Test func folderChangesCannotPublishBufferedOrInFlightResults() async {
    let state = WorkspaceState(photos: photos(20))
    let reader = PausedIndexReader()
    let indexing = Task { await state.indexMetadata(using: reader) }
    await reader.waitUntilPaused()
    state.showSamples()
    let session = state.sessionID
    await reader.resume()
    await indexing.value
    #expect(state.sessionID == session)
    #expect(state.metadata.isEmpty)
    #expect(state.indexedCount == 0)
    #expect(!state.indexing)
  }

  @Test func cancellationFlushesCompletedReadsAndAllowsTheInterruptedReadToRetry() async {
    let items = photos(20)
    let state = WorkspaceState(photos: items)
    let reader = PausedIndexReader()
    let indexing = Task { await state.indexMetadata(using: reader) }
    await reader.waitUntilPaused()
    indexing.cancel()
    await reader.resume()
    await indexing.value
    #expect(state.metadata.count == 7)
    #expect(state.indexedCount == 7)
    #expect(!state.indexing)
    await state.indexMetadata(using: reader)
    #expect(state.metadata.count == 20)
    #expect(state.indexedCount == 20)
  }

  @Test func decisionsMadeDuringLoadingSurviveBackgroundCompletionFiltersAndUndo() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("photos")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for index in 0..<160 {
      try Data("disposable source".utf8).write(to: folder.appendingPathComponent("\(index).jpg"))
    }
    let store = DecisionStore(databaseURL: root.appendingPathComponent("decisions.sqlite"))
    let state = WorkspaceState(decisionStore: store)
    await state.openFolder(folder)
    let items = state.photos
    let loading = Task { await state.loadDecisions() }
    while state.selectedID.map({ !state.decisionsReady.contains($0) }) == true {
      await Task.yield()
    }
    state.applyDecision(rating: 4, flag: .pick)
    state.select(items.last!.id)
    while !state.decisionsReady.contains(items.last!.id) { await Task.yield() }
    state.applyDecision(rating: 5, flag: .reject)
    state.setFilter(.pick, minimumRating: 3)
    await loading.value
    #expect(state.photos.map(\.id) == [items[0].id])
    #expect(state.decisions[items[0].id] == CullingDecision(rating: 4, flag: .pick))
    #expect(state.decisions[items.last!.id] == CullingDecision(rating: 5, flag: .reject))
    #expect(state.decisionsReady.count == items.count)
    state.undoDecision()
    #expect(state.decisions[items.last!.id] == CullingDecision())
    state.redoDecision()
    await DecisionSaveQueue.shared.flush()
    let saved = try await store.load(for: items.last!.fileURL!)
    #expect(saved.decision == CullingDecision(rating: 5, flag: .reject))
    #expect(try Data(contentsOf: items.last!.fileURL!) == Data("disposable source".utf8))
  }
}
