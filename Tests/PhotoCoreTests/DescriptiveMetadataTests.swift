import Foundation
import PhotoCore
import Testing

struct DescriptiveMetadataTests {
  @Test func explicitPatchesHierarchyAndAlternatesPreserveUnownedData() throws {
    let input = Data(
      """
      <x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description xmlns:dc='http://purl.org/dc/elements/1.1/' xmlns:crs='http://ns.adobe.com/camera-raw-settings/1.0/' crs:Exposure2012='1.2'><dc:title><rdf:Alt><rdf:li xml:lang='fr'>Titre</rdf:li><rdf:li xml:lang='x-default'>Old</rdf:li></rdf:Alt></dc:title></rdf:Description></rdf:RDF></x:xmpmeta>
      """.utf8)
    var patch = MetadataPatch()
    patch.fields = [
      .title: "New & <safe>", .creator: "Author", .createdCity: "Atlanta",
      .shownCountry: "United States",
    ]
    patch.keywordAction = .append
    patch.keywordText = "Wildlife|Birds|Great Blue Heron\nFlying"
    let before = try XMPSidecar.descriptive(input)
    #expect(before.fields[.title] == "Old")
    let after = try patch.applying(to: before)
    let merged = try XMPSidecar.mergingMetadata(
      after, fields: Set(patch.fields.keys), keywords: true, into: input)
    let result = try XMPSidecar.descriptive(merged)
    #expect(result.fields[.title] == "New & <safe>")
    #expect(result.fields[.createdCity] == "Atlanta")
    #expect(result.fields[.shownCountry] == "United States")
    #expect(result.keywords == ["Great Blue Heron", "Flying"])
    #expect(result.hierarchy == ["Wildlife|Birds|Great Blue Heron"])
    let text = String(decoding: merged, as: UTF8.self)
    #expect(text.contains("Titre"))
    #expect(text.contains("Exposure2012"))
    let rated = try XMPSidecar.merging(CullingDecision(rating: 4, flag: .pick), into: merged)
    #expect(try XMPSidecar.read(rated).rating == 4)
    #expect(try XMPSidecar.descriptive(rated).fields[.createdCity] == "Atlanta")
  }
  @Test func appendRemoveReplaceClearAreDistinctAndRejectEmptyHierarchyLevels() throws {
    var source = DescriptiveMetadata()
    source.keywords = ["Existing"]
    var patch = MetadataPatch()
    patch.keywordAction = .append
    patch.keywordText = "existing,New"
    #expect(try patch.applying(to: source).keywords == ["Existing", "New"])
    patch.keywordAction = .replace
    #expect(try patch.applying(to: source).keywords == ["existing", "New"])
    patch.keywordAction = .remove
    #expect(try patch.applying(to: source).keywords.isEmpty)
    patch.keywordAction = .clear
    #expect(try patch.applying(to: source).keywords.isEmpty)
    patch.keywordAction = .append
    patch.keywordText = "Birds||Heron"
    #expect(throws: (any Error).self) { try patch.applying(to: source) }
  }
  @Test func metadataAndRatingsShareBaselinesAndExternalChangesConflict() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("a.ORF")
    let bytes = Data("original RAW bytes".utf8)
    try bytes.write(to: image)
    let db = root.appendingPathComponent("db")
    let store = DecisionStore(databaseURL: db)
    _ = try await store.load(for: image)
    _ = try await store.save(CullingDecision(rating: 3), for: image)
    var patch = MetadataPatch()
    patch.fields = [.caption: "Caption", .createdCity: "Atlanta"]
    patch.keywordAction = .append
    patch.keywordText = "Birds|Herons"
    let plans = try await store.prepareMetadata(patch, images: [image])
    let saved = try await store.saveMetadata(try #require(plans.first))
    #expect(saved.status == "Saved")
    #expect(
      try await store.save(CullingDecision(rating: 5, flag: .pick), for: image).status == "Saved")
    #expect(
      try await DecisionStore(databaseURL: db).loadMetadata(for: image).value.fields[.caption]
        == "Caption")
    patch.fields[.caption] = "A later caption"
    let second = try await store.prepareMetadata(patch, images: [image])
    try XMPSidecar.merging(
      CullingDecision(rating: 2), into: Data(contentsOf: XMPSidecar.url(for: image))
    ).write(to: XMPSidecar.url(for: image))
    #expect(try await store.saveMetadata(try #require(second.first)).status == "XMP conflict")
    #expect(
      try await DecisionStore(databaseURL: db).loadMetadata(for: image).status == "XMP conflict")
    #expect(try await store.retryMetadata(for: image, useLocal: true).status == "Saved")
    #expect(try Data(contentsOf: image) == bytes)
  }
  @Test func subsequentMetadataPatchRetainsEarlierPendingFields() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("test.ORF")
    try Data("raw".utf8).write(to: image)
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db"))
    var first = MetadataPatch()
    first.fields = [.caption: "Pending caption"]
    let plan = try #require(try await store.prepareMetadata(first, images: [image]).first)
    try XMPSidecar.merging(CullingDecision(rating: 2), into: nil).write(
      to: XMPSidecar.url(for: image))
    #expect(try await store.saveMetadata(plan).status == "XMP conflict")
    var second = MetadataPatch()
    second.fields = [.creator: "Later author"]
    let later = try #require(try await store.prepareMetadata(second, images: [image]).first)
    #expect(try await store.saveMetadata(later).status == "XMP conflict")
    #expect(try await store.retryMetadata(for: image, useLocal: true).status == "Saved")
    let read = try XMPSidecar.descriptive(Data(contentsOf: XMPSidecar.url(for: image)))
    #expect(read.fields[.caption] == "Pending caption")
    #expect(read.fields[.creator] == "Later author")
    #expect(try XMPSidecar.read(Data(contentsOf: XMPSidecar.url(for: image))).rating == 2)
  }
  @Test func rawSidecarCollisionAcrossVendorsIsNotOverwritten() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("same.ARW")
    try Data().write(to: a)
    try Data().write(to: root.appendingPathComponent("same.CR3"))
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db"))
    let result = try await store.save(CullingDecision(rating: 5), for: a)
    #expect(result.status.contains("Multiple files"))
    #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: a).path))
  }
}

private struct IndexGuardReader: PhotoMetadataReading {
  func metadata(for file: URL) async throws -> PhotoMetadata {
    PhotoMetadata(pixelWidth: 1, pixelHeight: 1)
  }
}

@MainActor
struct BatchCullingTests {
  @Test func staleIndexingJobsCannotPopulateANewFolderSession() async {
    let state = WorkspaceState()
    let old = state.sessionID
    state.showSamples()
    await state.indexMetadata(using: IndexGuardReader(), expectedSession: old)
    await state.loadDecisions(expectedSession: old)
    #expect(state.metadata.isEmpty)
    #expect(state.decisionsReady.isEmpty)
    #expect(state.filePhotos.count == 3)
    await state.loadDecisions(expectedSession: state.sessionID)
    #expect(state.decisionsReady.count == 3)
  }

  @Test func workflowQuitBarrierDoesNotBlockDecisionSaves() async {
    var finished = false
    let operation = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(25))
      finished = true
    }
    WorkflowOperationBarrier.shared.track(operation)
    #expect(WorkflowOperationBarrier.shared.hasPending)
    var saved = false
    DecisionSaveQueue.shared.enqueue { saved = true }
    await DecisionSaveQueue.shared.flush()
    #expect(saved)
    await WorkflowOperationBarrier.shared.flush()
    #expect(finished)
    #expect(!WorkflowOperationBarrier.shared.hasPending)
  }

  @Test func batchDecisionsUndoAsOneAction() async {
    let state = WorkspaceState()
    await state.loadDecisions()
    state.selectAllVisible()
    state.applyDecision(rating: 4, flag: .pick)
    #expect(state.decisions.values.allSatisfy { $0.rating == 4 && $0.flag == .pick })
    state.undoDecision()
    #expect(state.decisions.values.allSatisfy { $0.rating == 0 && $0.flag == .unflagged })
    state.redoDecision()
    #expect(state.decisions.values.allSatisfy { $0.rating == 4 })
  }
  @Test func groupedRawJPEGReceiveIndependentMatchingSidecarsAndUndo() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let raw = root.appendingPathComponent("a.CR3")
    let jpg = root.appendingPathComponent("a.JPEG")
    try Data().write(to: raw)
    try Data().write(to: jpg)
    let state = WorkspaceState(
      decisionStore: DecisionStore(databaseURL: root.appendingPathComponent("db")))
    await state.openFolder(root)
    await state.loadDecisions()
    state.setGrouping(true)
    #expect(state.photos.count == 1)
    #expect(state.operationPhotos.count == 2)
    state.applyDecision(rating: 5, flag: .pick)
    await DecisionSaveQueue.shared.flush()
    #expect(try XMPSidecar.read(Data(contentsOf: XMPSidecar.url(for: raw))).rating == 5)
    #expect(try XMPSidecar.read(Data(contentsOf: XMPSidecar.url(for: jpg))).rating == 5)
    state.undoDecision()
    await DecisionSaveQueue.shared.flush()
    #expect(state.decisions.values.allSatisfy { $0.rating == 0 })
  }
}
