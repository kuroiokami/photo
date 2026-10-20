import Foundation
import PhotoCore
import Testing

private struct ReviewMetadata: PhotoMetadataReading {
  func metadata(for file: URL) async throws -> PhotoMetadata {
    PhotoMetadata(pixelWidth: 10, pixelHeight: 10)
  }
}
private struct ReviewFixture {
  let root: URL
  let card: URL
  let image: URL
  let database: URL
  let registry: URL
  let policy: SourceProtection
  let store: DecisionStore
  init() throws {
    root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
      UUID().uuidString)
    card = root.appendingPathComponent("Card")
    image = card.appendingPathComponent("frame.jpg")
    database = root.appendingPathComponent("Local/state.sqlite")
    registry = root.appendingPathComponent("Local/sources.json")
    try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
    try Data("original photo".utf8).write(to: image)
    policy = SourceProtection(registryURL: registry)
    store = DecisionStore(databaseURL: database, sourceProtection: policy)
  }
  func snapshot() throws -> [String: Data] {
    var result: [String: Data] = [:]
    for name in try FileManager.default.subpathsOfDirectory(atPath: card.path) {
      let file = card.appendingPathComponent(name)
      let a = try FileManager.default.attributesOfItem(atPath: file.path)
      result[name] =
        a[.type] as? FileAttributeType == .typeRegular ? try Data(contentsOf: file) : Data()
    }
    return result
  }
}
private actor ReviewGate {
  var open = false
  var continuation: CheckedContinuation<Void, Never>?
  func wait() async {
    if open { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func release() {
    open = true
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
struct SourceReviewTests {
  @Test func reviewDecisionsAndCompositionSurviveRestartWithoutTouchingWritableSource() async throws
  {
    let f = try ReviewFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let sidecar = XMPSidecar.url(for: f.image)
    try XMPSidecar.merging(CullingDecision(rating: 2), into: nil).write(to: sidecar)
    let before = try f.snapshot()
    let session = try await f.store.beginSourceReview(f.card)
    let initial = try await f.store.loadImageState(for: f.image)
    #expect(initial.0.decision.rating == 2 && !initial.0.reviewed)
    let identity = try #require(initial.0.identity)
    _ = try await f.store.saveSourceDecision(
      CullingDecision(rating: 5, flag: .pick), reviewed: true, session: session, image: f.image,
      identity: identity)
    let edit = PhotoEdit(
      quarterTurns: 1, mirrored: true, crop: PhotoCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.6))
    try await f.store.saveSourceEdits(
      [ImageEditWrite(image: f.image, identity: identity, edit: edit)], session: session)
    let restarted = DecisionStore(
      databaseURL: f.database, sourceProtection: SourceProtection(registryURL: f.registry))
    #expect(try await restarted.sourceReview(for: f.card)?.id == session.id)
    let restored = try await restarted.loadImageState(for: f.image)
    #expect(restored.0.decision == CullingDecision(rating: 5, flag: .pick))
    #expect(restored.0.reviewed && restored.0.status == "Review saved on this Mac")
    #expect(restored.1 == edit)
    #expect(try f.snapshot() == before)
  }
  @Test func explicitClearUndoGroupingAndOtherWindowReloadKeepReviewStateLocal() async throws {
    let f = try ReviewFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let raw = f.card.appendingPathComponent("frame.ARW")
    try Data("raw original".utf8).write(to: raw)
    let before = try f.snapshot()
    let oldWindow = WorkspaceState(decisionStore: f.store)
    await oldWindow.openFolder(f.card)
    await oldWindow.loadDecisions()
    _ = try await f.store.beginSourceReview(f.card)
    let first = WorkspaceState(decisionStore: f.store)
    await first.openFolder(f.card)
    await first.loadDecisions()
    #expect(first.isSourceReview && first.sourceReviewedIDs.isEmpty)
    first.setGrouping(true)
    first.applyDecision(flag: .unflagged)
    await DecisionSaveQueue.shared.flush()
    #expect(first.sourceReviewedIDs.count == 2)
    first.undoDecision()
    await DecisionSaveQueue.shared.flush()
    #expect(first.sourceReviewedIDs.isEmpty)
    first.redoDecision()
    first.applyDecision(rating: 4, flag: .pick)
    first.editSelection(.clockwise)
    await DecisionSaveQueue.shared.flush()
    oldWindow.applyDecision(rating: 1)
    await DecisionSaveQueue.shared.flush()
    #expect(oldWindow.saveStatus.values.contains { $0.contains("source is protected") })
    await oldWindow.openFolder(f.card)
    await oldWindow.loadDecisions()
    #expect(oldWindow.isSourceReview && oldWindow.sourceReviewedIDs.count == 2)
    #expect(oldWindow.decisions.values.allSatisfy { $0.rating == 4 && $0.flag == .pick })
    #expect(oldWindow.imageEdits.values.allSatisfy { $0.turns == 1 })
    #expect(try f.snapshot() == before)
  }
  @Test func queuedNormalIntentAndExistingPendingXMPNeverBecomeReviewWrites() async throws {
    let f = try ReviewFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    _ = try await f.store.load(for: f.image)
    try XMPSidecar.merging(CullingDecision(rating: 2), into: nil).write(
      to: XMPSidecar.url(for: f.image))
    let pending = try await f.store.save(CullingDecision(rating: 5), for: f.image)
    #expect(pending.conflict)
    let gate = ReviewGate()
    var blocked = false
    DecisionSaveQueue.shared.enqueue {
      await gate.wait()
      do {
        _ = try await f.store.save(CullingDecision(rating: 1), for: f.image, resolveConflict: true)
      } catch SourceReviewError.protectedSource { blocked = true } catch { Issue.record(error) }
    }
    let before = try f.snapshot()
    _ = try await f.store.beginSourceReview(f.card)
    await gate.release()
    await DecisionSaveQueue.shared.flush()
    #expect(blocked)
    let review = try await f.store.load(for: f.image)
    #expect(review.decision.rating == 2 && !review.reviewed)
    await #expect(throws: SourceReviewError.protectedSource) {
      _ = try await f.store.useExternal(for: f.image)
    }
    #expect(try f.snapshot() == before)
  }
  @Test func metadataBatchesHistoryRetryAndRenameAreGuardedBelowTheUI() async throws {
    let f = try ReviewFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    var patch = MetadataPatch()
    patch.fields[.copyright] = "Before review"
    let initial = try await f.store.prepareMetadata(patch, images: [f.image])
    _ = try await f.store.saveMetadataBatch(initial)
    patch.fields[.copyright] = "Must not write"
    let stale = try await f.store.prepareMetadata(patch, images: [f.image])
    let operations = MediaOperations(
      journalDirectory: f.root.appendingPathComponent("Local/operations"),
      sourceProtection: f.policy)
    let rename = try await operations.planRename(
      images: [f.image], pattern: "renamed_{original}", camera: "C1", start: 1,
      reader: ReviewMetadata())
    let historyBefore = try await f.store.metadataHistoryState()
    let before = try f.snapshot()
    _ = try await f.store.beginSourceReview(f.card)
    await #expect(throws: SourceReviewError.protectedSource) {
      _ = try await f.store.saveMetadataBatch(stale)
    }
    await #expect(throws: SourceReviewError.protectedSource) {
      _ = try await f.store.saveMetadata(stale[0])
    }
    await #expect(throws: SourceReviewError.protectedSource) {
      _ = try await f.store.retryMetadata(for: f.image, useLocal: true)
    }
    await #expect(throws: SourceReviewError.protectedSource) {
      _ = try await f.store.undoMetadataBatch()
    }
    await #expect(throws: SourceReviewError.protectedSource) {
      _ = try await operations.rename(rename)
    }
    #expect(try await f.store.metadataHistoryState().undoCount == historyBefore.undoCount)
    #expect(try f.snapshot() == before)
  }
  @Test func renameRecoveryAndCopyRoutesCannotBypassProtection() async throws {
    let f = try ReviewFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let operations = MediaOperations(
      journalDirectory: f.root.appendingPathComponent("Local/operations"),
      sourceProtection: f.policy)
    let rename = try await operations.planRename(
      images: [f.image], pattern: "renamed_{original}", camera: "C1", start: 1,
      reader: ReviewMetadata())
    let journal = try await operations.rename(rename)
    _ = try await f.store.beginSourceReview(f.card)
    let before = try f.snapshot()
    await #expect(throws: SourceReviewError.protectedSource) {
      try await operations.undoRename(journal: journal)
    }
    await #expect(throws: SourceReviewError.copyNotReady) {
      _ = try await operations.ingest(
        source: f.card, primary: f.root.appendingPathComponent("Copy"),
        backup: f.root.appendingPathComponent("Backup"))
    }
    await #expect(throws: SourceReviewError.copyNotReady) {
      _ = try await operations.prepareHandoff(
        images: [rename.entries.first { PhotoFormats.supports($0.destination) }!.destination],
        destination: f.root.appendingPathComponent("Delivery"))
    }
    let outside = f.root.appendingPathComponent("Other")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data("outside".utf8).write(to: outside.appendingPathComponent("other.jpg"))
    await #expect(throws: SourceReviewError.protectedSource) {
      _ = try await operations.ingest(
        source: outside, primary: f.card.appendingPathComponent("Nested"),
        backup: f.root.appendingPathComponent("Backup"))
    }
    #expect(try f.snapshot() == before)
  }
  @Test func childFoldersAliasesMovedRootsAndReplacementFilesDoNotEscapeProtection() async throws {
    let f = try ReviewFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let child = f.card.appendingPathComponent("Child")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    let second = child.appendingPathComponent("second.ORF")
    try Data("second".utf8).write(to: second)
    let session = try await f.store.beginSourceReview(f.card)
    #expect(try f.policy.session(for: child)?.id == session.id)
    let entry = try await f.store.load(for: second)
    _ = try await f.store.saveSourceDecision(
      CullingDecision(rating: 5), reviewed: true, session: session, image: second,
      identity: try #require(entry.identity))
    let link = f.root.appendingPathComponent("Alias")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.card)
    #expect(try f.policy.session(for: link.appendingPathComponent("Child"))?.id == session.id)
    let hardlink = f.root.appendingPathComponent("hardlink.ORF")
    try FileManager.default.linkItem(at: second, to: hardlink)
    #expect(throws: SourceReviewError.protectedSource) { try f.policy.withWritable([hardlink]) {} }
    try FileManager.default.removeItem(at: hardlink)
    let replacement = f.root.appendingPathComponent("replacement")
    try Data("different replacement".utf8).write(to: replacement)
    try FileManager.default.removeItem(at: second)
    try FileManager.default.moveItem(at: replacement, to: second)
    let fresh = try await f.store.load(for: second)
    #expect(fresh.decision.rating == 0 && !fresh.reviewed)
    let moved = f.root.appendingPathComponent("MovedCard")
    try FileManager.default.moveItem(at: f.card, to: moved)
    #expect(try f.policy.session(for: moved.appendingPathComponent("Child"))?.id == session.id)
    #expect(throws: SourceReviewError.protectedSource) {
      try f.policy.withWritable([moved.appendingPathComponent("new.xmp")]) {}
    }
  }
  @Test func reusingASourceLocationStartsFreshWithoutUnprotectingThePreviousCard() async throws {
    let f = try ReviewFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let first = try await f.store.beginSourceReview(f.card)
    let entry = try await f.store.load(for: f.image)
    _ = try await f.store.saveSourceDecision(
      CullingDecision(rating: 5), reviewed: true,
      session: first, image: f.image, identity: try #require(entry.identity))
    let original = f.root.appendingPathComponent("OriginalCard")
    try FileManager.default.moveItem(at: f.card, to: original)
    try FileManager.default.createDirectory(at: f.card, withIntermediateDirectories: true)
    try Data("new card photo".utf8).write(to: f.image)
    #expect(throws: SourceReviewError.sourceChanged) { _ = try f.policy.session(for: f.image) }
    let second = try await f.store.beginSourceReview(f.card)
    #expect(second.id != first.id)
    let fresh = try await f.store.load(for: f.image)
    #expect(fresh.decision.rating == 0 && !fresh.reviewed)
    let oldImage = original.appendingPathComponent("frame.jpg")
    #expect(try await f.store.load(for: oldImage).decision.rating == 5)
    #expect(throws: SourceReviewError.protectedSource) { try f.policy.withWritable([oldImage]) {} }
  }
  @Test func damagedRegistryFailsClosedAndLocalDataCannotBeChosenAsSource() async throws {
    let f = try ReviewFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    _ = try await f.store.beginSourceReview(f.card)
    _ = try f.policy.session(for: f.card)
    let before = try f.snapshot()
    try Data("broken".utf8).write(to: f.registry, options: .atomic)
    let reopened = SourceProtection(registryURL: f.registry)
    #expect(throws: SourceReviewError.unavailable) { try reopened.withWritable([f.image]) {} }
    #expect(try f.snapshot() == before)
    await #expect(throws: SourceReviewError.localData) {
      _ = try await f.store.beginSourceReview(f.database.deletingLastPathComponent())
    }
  }
}
