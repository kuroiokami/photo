import CSQLite
import Foundation
import Observation
import Testing

@testable import PhotoCore

private final class CommitCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  func record() { lock.withLock { count += 1 } }
  var value: Int { lock.withLock { count } }
}

struct HotPathTests {
  private func scratch() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  @MainActor @Test
  func readinessIsReusedAndInvalidatesForLoadingSelectionGroupingAndCollectionReplacement() async {
    let items = (0..<2000).map {
      PhotoItem(id: String($0), filename: "Frame\($0).jpg", resourceName: "")
    }
    let state = WorkspaceState(photos: items)
    state.selectAllVisible()
    #expect(!state.decisionSelectionReady)
    let cold = state.selectionReadinessEvaluations
    for _ in 0..<2000 { #expect(!state.decisionSelectionReady) }
    #expect(state.selectionReadinessEvaluations == cold)
    await state.loadDecisions()
    #expect(state.decisionSelectionReady)
    let warm = state.selectionReadinessEvaluations
    for _ in 0..<2000 { #expect(state.decisionSelectionReady) }
    #expect(state.selectionReadinessEvaluations == warm)
    // Cached reads still subscribe to the revision through Observation.
    let changed = CommitCounter()
    withObservationTracking {
      _ = state.decisionSelectionReady
    } onChange: {
      changed.record()
    }
    state.deselectAll()
    #expect(changed.value == 1)
    #expect(!state.decisionSelectionReady)
    state.select(items[10].id)
    #expect(state.decisionSelectionReady)
    state.setGrouping(true)
    #expect(state.decisionSelectionReady)
    state.showSamples()
    #expect(!state.decisionSelectionReady)
  }

  @Test func filenameRanksPreserveNativeOrderingAcrossEverySort() {
    let names = [
      "Frame10.jpg", "frame2.JPG", "Frame02.jpg", "café.jpg", "café.jpg",
      "日本10.jpg", "日本2.jpg", "Å1.jpg", "A1.jpg", "same.jpg", "same.jpg",
    ]
    let photos = names.enumerated().map {
      PhotoItem(id: String($0.offset), filename: $0.element, resourceName: "")
    }
    let ranks = PhotoSort.filenameRanks(for: photos)
    var metadata: [String: PhotoMetadata] = [:]
    var ratings: [String: Int] = [:]
    for (index, photo) in photos.enumerated() {
      if index % 3 != 0 {
        var value = PhotoMetadata(pixelWidth: 100, pixelHeight: 80)
        value.iso = Double(index % 2 * 100)
        value.aperture = Double(index % 2 + 2)
        value.captureTime = Date(timeIntervalSince1970: Double(index % 2))
        metadata[photo.id] = value
      }
      ratings[photo.id] = index % 3
    }
    for sort in PhotoSort.allCases {
      #expect(
        sort.ordered(photos, metadata: metadata, ratings: ratings).map(\.id)
          == sort.ordered(photos, metadata: metadata, ratings: ratings, filenameRanks: ranks).map(
            \.id))
    }
    let sorted = PhotoSort.filename.ordered(photos, metadata: [:])
    #expect(PhotoSort.filenameRanks(for: sorted) == ranks)
  }

  @Test func coldDecisionIndexingCommitsOncePerBoundedBatchAndSurvivesRestart() async throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let images = try (0..<24).map { index in
      let file = root.appendingPathComponent("Frame\(index).jpg")
      try Data("unchanged source".utf8).write(to: file)
      return file
    }
    let database = root.appendingPathComponent("decisions.sqlite")
    let store = DecisionStore(databaseURL: database)
    let counter = CommitCounter()
    try await store.withDB { db in
      _ = sqlite3_commit_hook(
        db,
        { context in
          Unmanaged<CommitCounter>.fromOpaque(context!).takeUnretainedValue().record()
          return 0
        }, Unmanaged.passUnretained(counter).toOpaque())
    }
    let results = try await store.loadImageStates(for: images)
    try await store.withDB { db in _ = sqlite3_commit_hook(db, nil, nil) }
    #expect(counter.value == 2)
    #expect(results.count == 24)
    for result in results { #expect(try result.get().0.decision == CullingDecision()) }
    let changes = try await store.withDB { sqlite3_total_changes($0) }
    _ = try await store.loadImageStates(for: images)
    #expect(try await store.withDB { sqlite3_total_changes($0) } == changes)
    let restarted = DecisionStore(databaseURL: database)
    for image in images {
      #expect(try await restarted.load(for: image).decision == CullingDecision())
      #expect(try Data(contentsOf: image) == Data("unchanged source".utf8))
      #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: image).path))
    }
  }

  @Test func failedBatchCommitCannotPublishRolledBackCacheSeedsAndCanRetry() async throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let images = ["good.jpg", "bad.jpg", "later.jpg"].map { root.appendingPathComponent($0) }
    for image in images { try Data("source".utf8).write(to: image) }
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db"))
    try await store.withDB { db in
      #expect(
        sqlite3_exec(
          db,
          "CREATE TRIGGER fail_path BEFORE INSERT ON paths WHEN NEW.path LIKE '%/bad.jpg' BEGIN SELECT RAISE(ROLLBACK, 'test rollback'); END",
          nil, nil, nil) == SQLITE_OK)
    }
    await #expect(throws: (any Error).self) { try await store.loadImageStates(for: images) }
    try await store.withDB { db in
      #expect(sqlite3_get_autocommit(db) != 0)
      var statement: OpaquePointer?
      #expect(
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM decisions", -1, &statement, nil) == SQLITE_OK)
      defer { sqlite3_finalize(statement) }
      #expect(sqlite3_step(statement) == SQLITE_ROW)
      #expect(sqlite3_column_int(statement, 0) == 0)
      #expect(sqlite3_exec(db, "DROP TRIGGER fail_path", nil, nil, nil) == SQLITE_OK)
    }
    for result in try await store.loadImageStates(for: images) {
      #expect(try result.get().0.decision == CullingDecision())
    }
  }
}
