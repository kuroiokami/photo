import Foundation
import PhotoCore
import Testing

struct MetadataHistoryTests {
  private func fixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
  private func patch(_ copyright: String) -> MetadataPatch {
    var patch = MetadataPatch()
    patch.fields = [.copyright: copyright]
    return patch
  }
  @Test func undoRedoSurviveRestartAndPreserveOtherFieldsAndDecisions() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("a.ARW")
    let db = root.appendingPathComponent("db")
    let original = Data("original RAW".utf8)
    try original.write(to: image)
    let store = DecisionStore(databaseURL: db)
    _ = try await store.save(CullingDecision(rating: 4, flag: .pick), for: image)
    var initial = patch("Original")
    initial.fields[.caption] = "Unique caption"
    initial.keywordAction = .append
    initial.keywordText = "Original|Tag"
    _ = try await store.saveMetadata(
      try #require(await store.prepareMetadata(initial, images: [image]).first))
    var shared = patch("Shared")
    shared.keywordAction = .append
    shared.keywordText = "Birds|Herons"
    _ = try await store.saveMetadataBatch(await store.prepareMetadata(shared, images: [image]))
    _ = try await store.save(CullingDecision(rating: 5, flag: .reject), for: image)
    var external = patch("Shared")
    external.fields = [.title: "External title"]
    let current = try XMPSidecar.descriptive(Data(contentsOf: XMPSidecar.url(for: image)))
    try XMPSidecar.mergingMetadata(
      try external.applying(to: current), fields: [.title], keywords: false,
      into: Data(contentsOf: XMPSidecar.url(for: image))
    ).write(to: XMPSidecar.url(for: image))
    let reopened = DecisionStore(databaseURL: db)
    #expect(try await reopened.metadataHistoryState().undoCount == 1)
    #expect(
      try await reopened.metadataHistoryState().undoSummary?.contains("Copyright notice") == true)
    #expect(try await reopened.undoMetadataBatch().values.allSatisfy { $0.status == "Saved" })
    var value = try await reopened.loadMetadata(for: image).value
    #expect(value.fields[.copyright] == "Original")
    #expect(value.fields[.caption] == "Unique caption")
    #expect(value.fields[.title] == "External title")
    #expect(value.keywords == ["Tag"])
    #expect(
      try await reopened.load(for: image).decision == CullingDecision(rating: 5, flag: .reject))
    #expect(try await DecisionStore(databaseURL: db).metadataHistoryState().redoCount == 1)
    _ = try await reopened.redoMetadataBatch()
    value = try await reopened.loadMetadata(for: image).value
    #expect(value.fields[.copyright] == "Shared")
    #expect(value.hierarchy == ["Original|Tag", "Birds|Herons"])
    #expect(value.fields[.title] == "External title")
    #expect(try Data(contentsOf: image) == original)
  }
  @Test func externalOwnedChangesStopTheWholeUndoAndStalePreviewsAreRejected() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let images = ["a.ARW", "b.ARW"].map { root.appendingPathComponent($0) }
    for image in images { try Data("RAW".utf8).write(to: image) }
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db"))
    _ = try await store.saveMetadataBatch(
      await store.prepareMetadata(patch("Shared"), images: images))
    let firstBefore = try Data(contentsOf: XMPSidecar.url(for: images[0]))
    let external = try patch("Someone else's edit").applying(
      to: XMPSidecar.descriptive(Data(contentsOf: XMPSidecar.url(for: images[1]))))
    try XMPSidecar.mergingMetadata(
      external, fields: [.copyright], keywords: false,
      into: Data(contentsOf: XMPSidecar.url(for: images[1]))
    ).write(to: XMPSidecar.url(for: images[1]))
    await #expect(throws: (any Error).self) { try await store.undoMetadataBatch() }
    #expect(try Data(contentsOf: XMPSidecar.url(for: images[0])) == firstBefore)
    #expect(try await store.metadataHistoryState().undoCount == 2)
    let preview = try await store.prepareMetadata(patch("Next"), images: [images[0]])
    _ = try await store.saveMetadata(
      try #require(await store.prepareMetadata(patch("Intervening"), images: [images[0]]).first))
    await #expect(throws: (any Error).self) { try await store.saveMetadataBatch(preview) }
    #expect(try await store.loadMetadata(for: images[0]).value.fields[.copyright] == "Intervening")
  }
  @Test func failedSyncKeepsDurableHistoryAndUndoCanRestorePendingIntent() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("a.ARW")
    let db = root.appendingPathComponent("db")
    try Data("RAW".utf8).write(to: image)
    let store = DecisionStore(databaseURL: db)
    _ = try await store.saveMetadata(
      try #require(await store.prepareMetadata(patch("Old"), images: [image]).first))
    let old = try Data(contentsOf: XMPSidecar.url(for: image))
    let plans = try await store.prepareMetadata(patch("New"), images: [image])
    try FileManager.default.removeItem(at: XMPSidecar.url(for: image))
    try FileManager.default.createDirectory(
      at: XMPSidecar.url(for: image), withIntermediateDirectories: false)
    let saved = try await store.saveMetadataBatch(plans)
    #expect(saved.values.allSatisfy { $0.status.hasPrefix("Saved locally") })
    let reopened = DecisionStore(databaseURL: db)
    #expect(try await reopened.loadMetadata(for: image).value.fields[.copyright] == "New")
    #expect(try await reopened.metadataHistoryState().undoCount == 1)
    try FileManager.default.removeItem(at: XMPSidecar.url(for: image))
    try old.write(to: XMPSidecar.url(for: image))
    #expect(try await reopened.undoMetadataBatch().values.allSatisfy { $0.status == "Saved" })
    #expect(try await reopened.loadMetadata(for: image).value.fields[.copyright] == "Old")
    _ = try await reopened.redoMetadataBatch()
    #expect(try await reopened.loadMetadata(for: image).value.fields[.copyright] == "New")
  }
  @Test func replacementRefusesUndoAndNewBatchClearsRedo() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("a.ARW")
    try Data("RAW".utf8).write(to: image)
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db"))
    _ = try await store.saveMetadataBatch(
      await store.prepareMetadata(patch("One"), images: [image]))
    _ = try await store.undoMetadataBatch()
    _ = try await store.saveMetadataBatch(
      await store.prepareMetadata(patch("Two"), images: [image]))
    #expect(try await store.metadataHistoryState().redoCount == 0)
    let sidecar = try Data(contentsOf: XMPSidecar.url(for: image))
    try Data("replacement RAW".utf8).write(to: image, options: .atomic)
    await #expect(throws: (any Error).self) { try await store.undoMetadataBatch() }
    #expect(try Data(contentsOf: XMPSidecar.url(for: image)) == sidecar)
  }
  @Test func cancellationBeforeCommitLeavesMetadataAndHistoryUnchanged() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("a.ARW")
    try Data("RAW".utf8).write(to: image)
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db"))
    let plans = try await store.prepareMetadata(patch("Not committed"), images: [image])
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await store.saveMetadataBatch(plans)
    }
    do {
      _ = try await task.value
      Issue.record("Cancelled metadata unexpectedly committed")
    } catch is CancellationError {} catch { throw error }
    #expect(try await store.metadataHistoryState().undoCount == 0)
    #expect(try await store.loadMetadata(for: image).value.fields[.copyright] == nil)
  }
  @Test func historyRetainsTwentyBatchesInUndoOrder() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("a.ARW")
    try Data("RAW".utf8).write(to: image)
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db"))
    for index in 1...22 {
      _ = try await store.saveMetadataBatch(
        await store.prepareMetadata(patch(String(index)), images: [image]))
    }
    for _ in 0..<20 { _ = try await store.undoMetadataBatch() }
    #expect(try await store.metadataHistoryState().undoCount == 0)
    #expect(try await store.loadMetadata(for: image).value.fields[.copyright] == "2")
    _ = try await store.redoMetadataBatch()
    #expect(try await store.loadMetadata(for: image).value.fields[.copyright] == "3")
  }
}
