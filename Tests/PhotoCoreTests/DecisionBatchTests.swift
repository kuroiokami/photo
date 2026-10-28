import CSQLite
import Foundation
import Testing

@testable import PhotoCore

private enum SimulatedDecisionStop: Error { case interrupted }
private struct DecisionBatchFixture {
  let root: URL
  let folder: URL
  let database: URL
  let policy: SourceProtection
  let store: DecisionStore
  let images: [URL]
  init(count: Int = 4) throws {
    root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
      UUID().uuidString)
    folder = root.appendingPathComponent("photos")
    database = root.appendingPathComponent("state/decisions.sqlite")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    policy = SourceProtection(registryURL: root.appendingPathComponent("state/protection.json"))
    store = DecisionStore(databaseURL: database, sourceProtection: policy)
    let imageFolder = folder
    images = (0..<count).map {
      imageFolder.appendingPathComponent(String(format: "frame%03d.jpg", $0))
    }
    for (index, image) in images.enumerated() {
      try Data("original \(index)".utf8).write(to: image)
    }
  }
  func seed() async throws -> [DecisionWrite] {
    var result: [DecisionWrite] = []
    for image in images {
      let entry = try await store.load(for: image)
      result.append(
        DecisionWrite(
          image: image, decision: CullingDecision(rating: 4, flag: .pick),
          expectedIdentity: entry.identity))
    }
    return result
  }
  func sql(_ sql: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open(database.path, &db) == SQLITE_OK, let db else {
      throw SimulatedDecisionStop.interrupted
    }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
    }
  }
  func originalsUnchanged() throws -> Bool {
    for (index, image) in images.enumerated() {
      if try Data(contentsOf: image) != Data("original \(index)".utf8) { return false }
    }
    return true
  }
  var sidecars: [URL] { images.map(XMPSidecar.url) }
  func sidecarCount() -> Int {
    sidecars.filter { FileManager.default.fileExists(atPath: $0.path) }.count
  }
}

struct DecisionBatchTests {
  @Test func commitsOneIntentAndAcknowledgementAndRestoresOnRestart() async throws {
    let f = try DecisionBatchFixture(count: 32)
    defer { try? FileManager.default.removeItem(at: f.root) }
    let requests = try await f.seed()
    for result in try await f.store.saveDecisions(requests) {
      #expect(try result.get().status == "Saved")
    }
    let counters = await f.store.decisionWriteStatistics
    #expect(counters.intentCommits == 1 && counters.acknowledgementCommits == 1)
    #expect(counters.sidecarPublications == 32)
    let restarted = DecisionStore(databaseURL: f.database, sourceProtection: f.policy)
    for request in requests {
      #expect(try await restarted.load(for: request.image).decision == request.decision)
      #expect(
        try XMPSidecar.read(Data(contentsOf: XMPSidecar.url(for: request.image)))
          == request.decision)
    }
    #expect(try f.originalsUnchanged())
  }
  @Test func malformedConflictAndReplacementDoNotBlockOtherFiles() async throws {
    let f = try DecisionBatchFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    var requests = try await f.seed()
    requests[0] = DecisionWrite(
      image: f.images[0], decision: requests[0].decision,
      expectedIdentity: requests[0].expectedIdentity, resolveConflict: true)
    let malformed = Data("not XML".utf8)
    let external = try XMPSidecar.merging(CullingDecision(rating: 2), into: nil)
    try malformed.write(to: f.sidecars[0])
    try external.write(to: f.sidecars[1])
    let replacement = f.folder.appendingPathComponent("new")
    try Data("replacement".utf8).write(to: replacement)
    try FileManager.default.removeItem(at: f.images[2])
    try FileManager.default.moveItem(at: replacement, to: f.images[2])
    let results = try await f.store.saveDecisions(requests)
    #expect(try results[0].get().status.contains("Saved locally"))
    #expect(try results[1].get().conflict)
    if case .success = results[2] { Issue.record("Replacement identity was accepted") }
    #expect(try results[3].get().status == "Saved")
    #expect(try Data(contentsOf: f.sidecars[0]) == malformed)
    #expect(try Data(contentsOf: f.sidecars[1]) == external)
    #expect(!FileManager.default.fileExists(atPath: f.sidecars[2].path))
    #expect(try await f.store.load(for: f.images[2]).decision == CullingDecision())
  }
  @Test func failedIntentTransactionRollsBackEveryRowBeforeAnyXMP() async throws {
    let f = try DecisionBatchFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let requests = try await f.seed()
    let identity = try #require(requests[1].expectedIdentity)
    try f.sql(
      "CREATE TRIGGER fail_intent BEFORE INSERT ON decisions WHEN NEW.identity='\(identity)' BEGIN SELECT RAISE(ROLLBACK,'intent failure'); END"
    )
    await #expect(throws: (any Error).self) { _ = try await f.store.saveDecisions(requests) }
    #expect(f.sidecarCount() == 0)
    for image in f.images {
      #expect(try await f.store.load(for: image).decision == CullingDecision())
    }
    #expect(await f.store.decisionWriteStatistics.rollbacks == 1)
    #expect(try f.originalsUnchanged())
  }
  @Test func interruptedPartialPublicationRecoversAckAndMetadataTogether() async throws {
    let f = try DecisionBatchFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    var patch = MetadataPatch()
    patch.fields[.copyright] = "Original copyright"
    for image in f.images {
      _ = try await f.store.saveMetadata(
        try #require(await f.store.prepareMetadata(patch, images: [image]).first))
    }
    let requests = try await f.seed()
    await f.store.setDecisionBatchProbe { checkpoint in
      if case .sidecarPublished(0) = checkpoint { throw SimulatedDecisionStop.interrupted }
    }
    await #expect(throws: SimulatedDecisionStop.self) {
      _ = try await f.store.saveDecisions(requests)
    }
    let restarted = DecisionStore(databaseURL: f.database, sourceProtection: f.policy)
    // Exercises recovery nested inside the existing read/index transaction.
    let restored = try await restarted.loadImageStates(for: f.images)
    #expect(try restored[0].get().0.status == "Saved")
    #expect(try restored[1].get().0.status.contains("pending"))
    #expect(try await restarted.loadMetadata(for: f.images[0]).status == "Saved")
    for result in restored { #expect(try result.get().0.decision.rating == 4) }
    for result in try await restarted.saveDecisions(requests) {
      #expect(try result.get().status == "Saved")
    }
    for image in f.images {
      #expect(
        try await restarted.loadMetadata(for: image).value.fields[.copyright]
          == "Original copyright")
      #expect(try await restarted.loadMetadata(for: image).status == "Saved")
    }
    #expect(try f.originalsUnchanged())
  }
  @Test func failedAcknowledgementRollsBackRebasesAndRestartRecoversExactly() async throws {
    let f = try DecisionBatchFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let requests = try await f.seed()
    let identity = try #require(requests[1].expectedIdentity)
    try f.sql(
      "CREATE TRIGGER fail_ack BEFORE INSERT ON decisions WHEN NEW.identity='\(identity)' AND CAST(NEW.payload AS TEXT) LIKE '%\"pending\":false%' BEGIN SELECT RAISE(ROLLBACK,'ack failure'); END"
    )
    let results = try await f.store.saveDecisions(requests)
    for result in results { #expect(try result.get().status.contains("XMP pending")) }
    #expect(f.sidecarCount() == f.images.count)
    #expect(await f.store.decisionWriteStatistics.acknowledgementCommits == 0)
    await #expect(throws: (any Error).self) { _ = try await f.store.loadImageStates(for: f.images) }
    try f.sql("DROP TRIGGER fail_ack")
    let restarted = DecisionStore(databaseURL: f.database, sourceProtection: f.policy)
    for image in f.images { #expect(try await restarted.load(for: image).status == "Saved") }
    #expect(await restarted.decisionWriteStatistics.recoveryCommits == f.images.count)
  }
  @Test func immediateRetryAfterFailedAckRepairsMetadataBeforeNextDecision() async throws {
    let f = try DecisionBatchFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    var patch = MetadataPatch()
    patch.fields[.copyright] = "Keep this copyright"
    for image in f.images {
      _ = try await f.store.saveMetadata(
        try #require(await f.store.prepareMetadata(patch, images: [image]).first))
    }
    let requests = try await f.seed()
    try f.sql(
      "CREATE TRIGGER fail_ack BEFORE INSERT ON decisions WHEN CAST(NEW.payload AS TEXT) LIKE '%\"pending\":false%' BEGIN SELECT RAISE(ROLLBACK,'ack failure'); END"
    )
    for result in try await f.store.saveDecisions(requests) {
      #expect(try result.get().status.contains("XMP pending"))
    }
    try f.sql("DROP TRIGGER fail_ack")
    let next = requests.map {
      DecisionWrite(
        image: $0.image, decision: CullingDecision(rating: 2, flag: .reject),
        expectedIdentity: $0.expectedIdentity)
    }
    // No intervening Reload: preserve the old receipt before replacing intent.
    for result in try await f.store.saveDecisions(next) {
      #expect(try result.get().status == "Saved")
    }
    for image in f.images {
      #expect(try await f.store.loadMetadata(for: image).status == "Saved")
      #expect(
        try await f.store.loadMetadata(for: image).value.fields[.copyright] == "Keep this copyright"
      )
      #expect(
        try await f.store.load(for: image).decision == CullingDecision(rating: 2, flag: .reject))
    }
    #expect(await f.store.decisionWriteStatistics.recoveryCommits == 4)
    #expect(try f.originalsUnchanged())
  }
  @Test func externalEditAfterPublicationCannotBeHiddenByMatchingStars() async throws {
    let f = try DecisionBatchFixture(count: 1)
    defer { try? FileManager.default.removeItem(at: f.root) }
    let requests = try await f.seed()
    await f.store.setDecisionBatchProbe { checkpoint in
      if case .sidecarPublished = checkpoint { throw SimulatedDecisionStop.interrupted }
    }
    await #expect(throws: SimulatedDecisionStop.self) {
      _ = try await f.store.saveDecisions(requests)
    }
    let current = try Data(contentsOf: f.sidecars[0])
    var patch = MetadataPatch()
    patch.fields[.title] = "Late external edit"
    let value = try patch.applying(to: XMPSidecar.descriptive(current))
    let external = try XMPSidecar.mergingMetadata(
      value, fields: [.title], keywords: false, into: current)
    try external.write(to: f.sidecars[0])
    let restarted = DecisionStore(databaseURL: f.database, sourceProtection: f.policy)
    #expect(try await restarted.load(for: f.images[0]).conflict)
    #expect(try Data(contentsOf: f.sidecars[0]) == external)
  }
  @Test func lateExternalEditIsProtectedEvenDuringExplicitResolution() async throws {
    let f = try DecisionBatchFixture(count: 1)
    defer { try? FileManager.default.removeItem(at: f.root) }
    _ = try await f.seed()
    let external = try XMPSidecar.merging(CullingDecision(rating: 2), into: nil)
    let sidecar = f.sidecars[0]
    await f.store.setDecisionBatchProbe { checkpoint in
      if case .intentCommitted = checkpoint { try external.write(to: sidecar) }
    }
    let result = try await f.store.saveDecisions([
      DecisionWrite(image: f.images[0], decision: CullingDecision(rating: 5), resolveConflict: true)
    ])
    #expect(try result[0].get().conflict)
    #expect(try Data(contentsOf: sidecar) == external)
    #expect(try await f.store.load(for: f.images[0]).decision.rating == 5)
  }
  @Test func cancellationBeforeCommitAndOversizedChunkNeverPublish() async throws {
    let f = try DecisionBatchFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let requests = try await f.seed()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await f.store.saveDecisions(requests)
    }
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    await #expect(throws: (any Error).self) {
      _ = try await f.store.saveDecisions(Array(repeating: requests[0], count: 33))
    }
    #expect(f.sidecarCount() == 0)
    #expect(await f.store.decisionWriteStatistics.intentCommits == 0)
  }
  @Test func committedIntentFinishesDespiteLaterCancellationAndAliasesKeepOrdering() async throws {
    let f = try DecisionBatchFixture(count: 1)
    defer { try? FileManager.default.removeItem(at: f.root) }
    let request = try #require(await f.seed().first)
    await f.store.setDecisionBatchProbe { checkpoint in
      if case .intentCommitted = checkpoint { withUnsafeCurrentTask { $0?.cancel() } }
    }
    let task = Task { try await f.store.saveDecisions([request]) }
    #expect(try await task.value[0].get().status == "Saved")
    #expect(task.isCancelled)
    await f.store.setDecisionBatchProbe(nil)
    let next = DecisionWrite(
      image: request.image, decision: CullingDecision(rating: 1, flag: .reject),
      expectedIdentity: request.expectedIdentity)
    for result in try await f.store.saveDecisions([request, next]) {
      #expect(try result.get().status == "Saved")
    }
    #expect(try await f.store.load(for: request.image).decision == next.decision)
    #expect(await f.store.decisionWriteStatistics.intentCommits == 3)
    #expect(try f.originalsUnchanged())
  }
  @Test func preparedXMLBudgetAndUnrelatedPropertiesSurviveRecomputation() async throws {
    let f = try DecisionBatchFixture(count: 8)
    defer { try? FileManager.default.removeItem(at: f.root) }
    let payload = String(repeating: "a", count: 220000)
    let xml = Data(
      "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description xmlns:other=\"http://example.com/\" other:untouched=\"\(payload)\"/></rdf:RDF>"
        .utf8)
    for sidecar in f.sidecars { try xml.write(to: sidecar) }
    let requests = try await f.seed()
    for result in try await f.store.saveDecisions(requests) {
      #expect(try result.get().status == "Saved")
    }
    #expect(await f.store.decisionWriteStatistics.maximumPreparedXMPBytes <= 1024 * 1024)
    for sidecar in f.sidecars {
      #expect(try String(contentsOf: sidecar, encoding: .utf8).contains(payload))
    }
  }
  @Test func protectedReviewBatchIsAtomicAndPreservesEditsAndFieldOwnership() async throws {
    let f = try DecisionBatchFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let session = try await f.store.beginSourceReview(f.folder)
    var writes: [SourceDecisionWrite] = []
    for image in f.images {
      let state = try await f.store.loadSourceReview(session, image: image)
      let identity = try #require(state.0.identity)
      writes.append(
        SourceDecisionWrite(
          image: image, identity: identity, decision: CullingDecision(flag: .reject),
          reviewed: true, fields: .flag))
      try await f.store.saveSourceEdits(
        [ImageEditWrite(image: image, identity: identity, edit: PhotoEdit(quarterTurns: 1))],
        session: session)
    }
    try f.sql(
      "CREATE TRIGGER fail_review BEFORE INSERT ON source_review_items WHEN NEW.identity='\(writes[1].identity)' BEGIN SELECT RAISE(ROLLBACK,'review failure'); END"
    )
    await #expect(throws: (any Error).self) {
      _ = try await f.store.saveSourceDecisions(writes, session: session)
    }
    for image in f.images {
      #expect(
        try await f.store.loadSourceReview(session, image: image).0.decision == CullingDecision())
    }
    try f.sql("DROP TRIGGER fail_review")
    for result in try await f.store.saveSourceDecisions(writes, session: session) {
      #expect(try result.get().reviewFields == .flag)
    }
    #expect(await f.store.decisionWriteStatistics.reviewCommits == 1)
    let restarted = DecisionStore(databaseURL: f.database, sourceProtection: f.policy)
    for image in f.images {
      let result = try await restarted.loadSourceReview(session, image: image)
      #expect(
        result.0.reviewed && result.0.decision.flag == .reject && result.0.decision.rating == 0)
      #expect(result.0.reviewFields == .flag && result.1.turns == 1)
    }
    #expect(f.sidecarCount() == 0)
    #expect(try f.originalsUnchanged())
  }
}

@MainActor
struct DecisionBatchWorkspaceTests {
  @Test func bulkUndoRedoUsesOneQueueEntryPerActionAndBoundedCommits() async throws {
    let f = try DecisionBatchFixture(count: 65)
    defer { try? FileManager.default.removeItem(at: f.root) }
    let state = WorkspaceState(decisionStore: f.store)
    await state.openFolder(f.folder)
    await state.loadDecisions()
    state.selectAllVisible()
    let queued = DecisionSaveQueue.shared.pendingOperationCount
    state.applyDecision(rating: 4, flag: .pick)
    #expect(DecisionSaveQueue.shared.pendingOperationCount == queued + 1)
    state.undoDecision()
    #expect(DecisionSaveQueue.shared.pendingOperationCount == queued + 2)
    state.redoDecision()
    #expect(DecisionSaveQueue.shared.pendingOperationCount == queued + 3)
    await DecisionSaveQueue.shared.flush()
    #expect(state.decisions.values.allSatisfy { $0 == CullingDecision(rating: 4, flag: .pick) })
    #expect(state.saveStatus.values.allSatisfy { $0 == "Saved" })
    let counters = await f.store.decisionWriteStatistics
    #expect(counters.intentCommits == 9 && counters.acknowledgementCommits == 9)
    #expect(try f.originalsUnchanged())
  }
  @Test func queuedPersistenceOutlivesReleasedWorkspace() async throws {
    let f = try DecisionBatchFixture(count: 65)
    defer { try? FileManager.default.removeItem(at: f.root) }
    var state: WorkspaceState? = WorkspaceState(decisionStore: f.store)
    await state?.openFolder(f.folder)
    await state?.loadDecisions()
    state?.selectAllVisible()
    weak var released: WorkspaceState?
    released = state
    state?.applyDecision(flag: .reject)
    state = nil
    await DecisionSaveQueue.shared.flush()
    #expect(released == nil)
    #expect(await f.store.decisionWriteStatistics.intentCommits == 3)
    let restarted = DecisionStore(databaseURL: f.database, sourceProtection: f.policy)
    for image in f.images { #expect(try await restarted.load(for: image).decision.flag == .reject) }
    #expect(try f.originalsUnchanged())
  }
  @Test func sourceReviewUndoRedoPreservesOwnedFieldsWithNoSourceWrites() async throws {
    let f = try DecisionBatchFixture(count: 65)
    defer { try? FileManager.default.removeItem(at: f.root) }
    _ = try await f.store.beginSourceReview(f.folder)
    let state = WorkspaceState(decisionStore: f.store)
    await state.openFolder(f.folder)
    await state.loadDecisions()
    state.selectAllVisible()
    state.applyDecision(flag: .pick)
    state.undoDecision()
    state.redoDecision()
    state.applyDecision(rating: 3)
    await DecisionSaveQueue.shared.flush()
    #expect(await f.store.decisionWriteStatistics.reviewCommits == 12)
    #expect(state.sourceReviewedIDs.count == 65)
    for image in f.images {
      let value = try await f.store.load(for: image)
      #expect(value.decision == CullingDecision(rating: 3, flag: .pick))
      #expect(value.reviewFields == .all)
    }
    #expect(f.sidecarCount() == 0)
    #expect(try f.originalsUnchanged())
  }
}
