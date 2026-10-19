import CSQLite
import Foundation
import PhotoCore
import Testing

struct DecisionStoreTests {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  @Test func independentFlagsStarsAndUnknownXMPPreserved() throws {
    let xml = Data(
      """
      <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:other="http://example.com/other/" xmlns:r="http://ns.adobe.com/xap/1.0/" r:Rating="2" other:untouched="yes"><other:Develop>keep me</other:Develop></rdf:Description></rdf:RDF></x:xmpmeta>
      """.utf8)
    let output = try XMPSidecar.merging(CullingDecision(rating: 5, flag: .reject), into: xml)
    #expect(try XMPSidecar.read(output) == CullingDecision(rating: 5, flag: .reject))
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains("keep me"))
    #expect(text.contains("untouched=\"yes\""))
    let neutral = try XMPSidecar.merging(CullingDecision(rating: 3), into: output)
    #expect(try XMPSidecar.read(neutral) == CullingDecision(rating: 3))
    #expect(!String(decoding: neutral, as: UTF8.self).contains("good="))
  }
  @Test func restartConflictAndExplicitResolutionProtectImageBytes() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let image = dir.appendingPathComponent("photo.ARW")
    let original = Data("synthetic image bytes".utf8)
    try original.write(to: image)
    let database = dir.appendingPathComponent("local.sqlite")
    let store = DecisionStore(databaseURL: database)
    _ = try await store.load(for: image)
    let decision = CullingDecision(rating: 4, flag: .pick)
    #expect(try await store.save(decision, for: image).status == "Saved")
    let restarted = DecisionStore(databaseURL: database)
    #expect(try await restarted.load(for: image).decision == decision)
    let external = try XMPSidecar.merging(CullingDecision(rating: 2), into: nil)
    try external.write(to: XMPSidecar.url(for: image))
    #expect(try await store.save(CullingDecision(rating: 5, flag: .reject), for: image).conflict)
    #expect(try Data(contentsOf: XMPSidecar.url(for: image)) == external)
    #expect(try await restarted.load(for: image).conflict)
    #expect(try await store.save(decision, for: image, resolveConflict: true).status == "Saved")
    #expect(try Data(contentsOf: image) == original)
  }
  @Test func externalImportMinusOneAndSidecarNames() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let image = dir.appendingPathComponent("photo.ArW")
    try Data().write(to: image)
    let xml = Data(
      "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmp:Rating=\"-1\"/></rdf:RDF>"
        .utf8)
    try xml.write(to: XMPSidecar.url(for: image))
    let store = DecisionStore(databaseURL: dir.appendingPathComponent("db.sqlite"))
    #expect(try await store.load(for: image).decision == CullingDecision(flag: .reject))
    #expect(XMPSidecar.url(for: image).lastPathComponent == "photo.xmp")
    #expect(
      XMPSidecar.url(for: dir.appendingPathComponent("photo.jpg")).lastPathComponent
        == "photo.jpg.xmp")
  }
  @Test func malformedAndEntitySidecarsAreUntouched() throws {
    for text in ["not xml", "<!DOCTYPE a [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><a>&x;</a>"] {
      #expect(throws: (any Error).self) {
        try XMPSidecar.merging(CullingDecision(rating: 5), into: Data(text.utf8))
      }
    }
  }
  @Test func interruptedAcknowledgementRecoversWithoutRewritingXMP() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let image = dir.appendingPathComponent("a.arw")
    let database = dir.appendingPathComponent("db.sqlite")
    try Data().write(to: image)
    let store = DecisionStore(databaseURL: database)
    _ = try await store.load(for: image)
    let decision = CullingDecision(rating: 4, flag: .pick)
    _ = try await store.save(decision, for: image)
    let published = try Data(contentsOf: XMPSidecar.url(for: image))
    // Simulate durable intent + published XMP with the final acknowledgement lost.
    var db: OpaquePointer?
    #expect(sqlite3_open(database.path, &db) == SQLITE_OK)
    let sql =
      #"UPDATE decisions SET payload = '{"decision":{"rating":4,"flag":1},"pending":true,"baseline":"absent"}'"#
    let result = sqlite3_exec(db, sql, nil, nil, nil)
    sqlite3_close(db)
    #expect(result == SQLITE_OK)
    let recovered = try await DecisionStore(databaseURL: database).load(for: image)
    #expect(recovered.status == "Saved")
    #expect(recovered.decision == decision)
    #expect(try Data(contentsOf: XMPSidecar.url(for: image)) == published)
  }

  @Test func readOnlyFailureKeepsDurableLocalDecision() async throws {
    let dir = try folder()
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
      try? FileManager.default.removeItem(at: dir)
    }
    let image = dir.appendingPathComponent("a.arw")
    try Data().write(to: image)
    let database = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".sqlite")
    defer { try? FileManager.default.removeItem(at: database) }
    let store = DecisionStore(databaseURL: database)
    _ = try await store.load(for: image)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
    let decision = CullingDecision(rating: 3, flag: .pick)
    let saved = try await store.save(decision, for: image)
    #expect(saved.status.contains("Saved locally"))
    #expect(try await DecisionStore(databaseURL: database).load(for: image).decision == decision)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    #expect(try await store.save(decision, for: image).status == "Saved")
  }
  @Test func queuedSaveCannotAttachToReplacedFile() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let image = dir.appendingPathComponent("a.arw")
    try Data("before".utf8).write(to: image)
    let store = DecisionStore(databaseURL: dir.appendingPathComponent("db"))
    let loaded = try await store.load(for: image)
    try Data("a different replacement".utf8).write(to: image)
    await #expect(throws: (any Error).self) {
      try await store.save(
        CullingDecision(rating: 5), for: image, expectedIdentity: loaded.identity)
    }
    #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: image).path))
  }

  @Test func symbolicLinkAndAmbiguousRawSidecarsAreNotWritten() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let image = dir.appendingPathComponent("a.arw")
    try Data().write(to: image)
    let target = dir.appendingPathComponent("target.xmp")
    let untouched = try XMPSidecar.merging(CullingDecision(rating: 2), into: nil)
    try untouched.write(to: target)
    try FileManager.default.createSymbolicLink(
      at: XMPSidecar.url(for: image), withDestinationURL: target)
    let store = DecisionStore(databaseURL: dir.appendingPathComponent("db"))
    _ = try await store.save(CullingDecision(rating: 5), for: image, resolveConflict: true)
    #expect(try Data(contentsOf: target) == untouched)
    #expect(
      try FileManager.default.destinationOfSymbolicLink(atPath: XMPSidecar.url(for: image).path)
        == target.path)
    try FileManager.default.removeItem(at: XMPSidecar.url(for: image))
    try Data().write(to: dir.appendingPathComponent("a.ARW"))
    let peers = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension.lowercased() == "arw" }
    // A case-insensitive volume cannot represent this ambiguous pair.
    if peers.count == 2 {
      _ = try await store.save(CullingDecision(rating: 5), for: image, resolveConflict: true)
      #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: image).path))
    }
  }

  @Test func replacementCannotInheritItsPredecessorsSidecar() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let image = dir.appendingPathComponent("same.arw")
    try Data("original image".utf8).write(to: image)
    let database = dir.appendingPathComponent("db")
    let store = DecisionStore(databaseURL: database)
    _ = try await store.load(for: image)
    _ = try await store.save(CullingDecision(rating: 5, flag: .pick), for: image)
    let originalSidecar = try Data(contentsOf: XMPSidecar.url(for: image))
    try Data("different replacement image bytes".utf8).write(to: image)
    let replacement = try await store.load(for: image)
    #expect(replacement.decision == CullingDecision())
    #expect(replacement.conflict)
    let restarted = try await DecisionStore(databaseURL: database).load(for: image)
    #expect(restarted.decision == CullingDecision())
    #expect(restarted.conflict)
    #expect(try Data(contentsOf: XMPSidecar.url(for: image)) == originalSidecar)
    #expect(try await store.useExternal(for: image).decision.rating == 5)
  }

  @Test func renamedIdentityRetainedAndReplacementNotInherited() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appendingPathComponent("a.jpg")
    let b = dir.appendingPathComponent("b.jpg")
    try Data("original".utf8).write(to: a)
    let store = DecisionStore(databaseURL: dir.appendingPathComponent("db"))
    _ = try await store.load(for: a)
    _ = try await store.save(CullingDecision(rating: 5), for: a)
    try FileManager.default.moveItem(at: a, to: b)
    #expect(try await store.load(for: b).decision.rating == 5)
    try Data("replacement with different content".utf8).write(to: b)
    #expect(try await store.load(for: b).decision.rating == 0)
  }
}

@MainActor
struct CullingWorkflowTests {
  @Test func filteredAutoAdvanceDoesNotSkipAndUndoRestoresStars() async {
    let previous = UserDefaults.standard.bool(forKey: "Photo.autoAdvance")
    defer { UserDefaults.standard.set(previous, forKey: "Photo.autoAdvance") }
    let state = WorkspaceState()
    state.autoAdvance = false
    await state.loadDecisions()
    state.applyDecision(rating: 4)
    #expect(state.selectedIndex == 0)
    state.setFilter(.unflagged, minimumRating: 0)
    state.applyDecision(flag: .pick, advance: true)
    #expect(state.selectedPhoto?.id == SampleLibrary.photos[1].id)
    #expect(state.decisions[SampleLibrary.photos[0].id]?.rating == 4)
    state.undoDecision()
    #expect(state.selectedPhoto?.id == SampleLibrary.photos[0].id)
    #expect(state.decisions[SampleLibrary.photos[0].id]?.rating == 4)
    state.redoDecision()
    #expect(state.photos.count == 2)
  }
  @Test func filteringToEmptyClearsSelectionAndUndoRecovers() async {
    let state = WorkspaceState()
    await state.loadDecisions()
    state.setFilter(.pick, minimumRating: 5)
    #expect(state.selectedPhoto == nil)
    #expect(state.photos.isEmpty)
    state.setFilter(.all, minimumRating: 0)
    state.select(state.photos.last?.id)
    state.setFilter(.reject, minimumRating: 0)
    #expect(state.selectedPhoto == nil)
    state.setFilter(.all, minimumRating: 0)
    #expect(state.selectedPhoto != nil)
  }

  @Test func activeFiltersWaitForDecisionsAndReloadPreservesIdentity() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let picked = dir.appendingPathComponent("picked.png")
    try Data().write(to: picked)
    try Data().write(to: dir.appendingPathComponent("unflagged.png"))
    let store = DecisionStore(databaseURL: dir.appendingPathComponent("db"))
    _ = try await store.load(for: picked)
    _ = try await store.save(CullingDecision(rating: 4, flag: .pick), for: picked)
    let state = WorkspaceState(decisionStore: store)
    state.setFilter(.pick, minimumRating: 0)
    await state.openFolder(dir)
    #expect(state.decisionsLoading)
    #expect(state.photos.isEmpty)
    await state.loadDecisions()
    #expect(!state.decisionsLoading)
    #expect(state.photos.map(\.filename) == ["picked.png"])
    let selected = state.selectedID
    await state.openFolder(dir)
    #expect(state.photos.isEmpty)
    await state.loadDecisions()
    #expect(state.selectedID == selected)
    state.showSamples()
    await state.loadDecisions()
    state.setFilter(.all, minimumRating: 0)
    #expect(state.decisionsReady.count == SampleLibrary.photos.count)
  }

  @Test func terminationBarrierWaitsForOrderedSaves() async {
    var writes: [Int] = []
    DecisionSaveQueue.shared.enqueue {
      await Task.yield()
      writes.append(1)
    }
    DecisionSaveQueue.shared.enqueue { writes.append(2) }
    await DecisionSaveQueue.shared.flush()
    #expect(writes == [1, 2])
    #expect(!DecisionSaveQueue.shared.hasPending)
  }

  @Test func ratingSortAdvancesUsingPreviousOrder() async {
    let previous = UserDefaults.standard.bool(forKey: "Photo.autoAdvance")
    defer { UserDefaults.standard.set(previous, forKey: "Photo.autoAdvance") }
    let state = WorkspaceState()
    state.autoAdvance = false
    await state.loadDecisions()
    await state.setSort(.rating)
    let first = state.photos[0].id
    let next = state.photos[1].id
    state.select(first)
    state.applyDecision(rating: 5, advance: true)
    #expect(state.selectedID == next)
    state.select(first)
    state.applyDecision(rating: 1)
    #expect(state.selectedID == first)
    state.select(state.photos.last?.id)
    let last = state.selectedID
    state.applyDecision(flag: .pick, advance: true)
    #expect(state.selectedID == last)
  }
}
