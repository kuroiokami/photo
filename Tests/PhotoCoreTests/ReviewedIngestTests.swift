import Foundation
import Testing

@testable import PhotoCore

private struct ReviewedIngestFixture {
  let root: URL
  let card: URL
  let primary: URL
  let backup: URL
  let database: URL
  let registry: URL
  let journals: URL
  let policy: SourceProtection
  let store: DecisionStore
  let operations: MediaOperations
  init() throws {
    root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
      UUID().uuidString)
    card = root.appendingPathComponent("Card")
    primary = root.appendingPathComponent("Photos/Shoot/Originals")
    backup = root.appendingPathComponent("Backup/Shoot/Originals")
    database = root.appendingPathComponent("Local/state.sqlite")
    registry = root.appendingPathComponent("Local/sources.json")
    journals = root.appendingPathComponent("Local/Operations")
    policy = SourceProtection(registryURL: registry)
    store = DecisionStore(databaseURL: database, sourceProtection: policy)
    operations = MediaOperations(journalDirectory: journals, sourceProtection: policy)
    try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
  }
  func file(_ relative: String, _ bytes: String = "fixture") throws -> URL {
    let file = card.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(bytes.utf8).write(to: file)
    return file
  }
  func decide(_ image: URL, _ decision: CullingDecision, fields: SourceDecisionFields = .all)
    async throws
  {
    let session = try #require(await store.sourceReview(for: image))
    let entry = try await store.loadSourceReview(session, image: image).0
    _ = try await store.saveSourceDecision(
      decision, reviewed: true, session: session, image: image, identity: #require(entry.identity),
      fields: fields)
  }
  func plan(
    _ scope: ReviewedCopyScope = .all, selection: [URL] = [], pairs: Bool = true,
    acceptMetadata: Bool = false
  ) async throws -> ReviewedCopyPlan {
    let session = try await store.beginSourceReview(card)
    return try await operations.planReviewedCopy(
      session: session, scope: scope, selection: selection, primary: primary, backup: backup,
      keepPairs: pairs, acceptMetadataChanges: acceptMetadata, store: store)
  }
  func tree() throws -> [String: Data] {
    var result: [String: Data] = [:]
    for relative in try FileManager.default.subpathsOfDirectory(atPath: card.path) {
      let file = card.appendingPathComponent(relative)
      result[relative] =
        (try FileManager.default.attributesOfItem(atPath: file.path)[.type]) as? FileAttributeType
          == .typeRegular ? try Data(contentsOf: file) : Data()
    }
    return result
  }
  func expectedTargets(_ plan: ReviewedCopyPlan) throws -> [URL: FileFingerprint] {
    try Dictionary(
      uniqueKeysWithValues: plan.families.flatMap(\.images).flatMap { image in
        let relative = image.source.pathComponents.dropFirst(plan.session.root.pathComponents.count)
          .joined(separator: "/")
        return try [plan.primary, plan.backup].map { root in
          let target = root.appendingPathComponent(relative)
          return (target, try FileFingerprint.read(target))
        }
      })
  }
  /// Emulates a process stopping after verified bytes, before destination intent.
  func stageBytes(_ plan: ReviewedCopyPlan) throws {
    try FileManager.default.createDirectory(at: journals, withIntermediateDirectories: true)
    try JSONEncoder().encode(plan).write(
      to: journals.appendingPathComponent("review-copy-\(plan.id.uuidString).json"))
    var events = Data()
    for file in plan.files {
      for folder in [primary, backup] {
        let target = folder.appendingPathComponent(file.relative)
        try FileManager.default.createDirectory(
          at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: file.source).write(to: target)
      }
      events.append(
        try JSONEncoder().encode(
          ReviewCopyEvent(
            relative: file.relative, sha256: MediaOperations.checksum(file.source), verified: true))
      )
      events.append(0x0A)
    }
    try events.write(
      to: journals.appendingPathComponent("review-copy-\(plan.id.uuidString).events"))
  }
}

struct ReviewedIngestTests {
  @Test func sourceWideScopesCountUnreviewedAndSelectionIgnoresUnrelatedMetadata() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("DCIM/a.JPG")
    let b = try f.file("Day2/b.JPEG")
    let c = try f.file("DCIM/c.ORF")
    _ = try f.file("movie.mov")
    _ = try await f.store.beginSourceReview(f.card)
    try await f.decide(a, CullingDecision(rating: 4, flag: .pick))
    try await f.decide(b, CullingDecision(flag: .reject))
    let all = try await f.plan()
    #expect(
      all.images.count == 3 && all.sourceUnreviewedCount == 1 && all.omittedUnreviewedCount == 0
        && all.otherFileCount == 1)
    let picks = try await f.plan(.picks)
    #expect(
      picks.images.map(\.source) == [PhotoPath.canonical(a)] && picks.omittedUnreviewedCount == 1)
    let survivors = try await f.plan(.nonRejected)
    #expect(
      Set(survivors.images.map(\.source)) == [PhotoPath.canonical(a), PhotoPath.canonical(c)]
        && survivors.omittedUnreviewedCount == 0)
    _ = try f.file("DCIM/c.xmp", "not XML")
    let selected = try await f.plan(.selection, selection: [a], pairs: false)
    #expect(
      selected.images.map(\.source) == [PhotoPath.canonical(a)] && selected.sourcePhotoCount == nil)
    #expect(!FileManager.default.fileExists(atPath: f.primary.path))
  }

  @Test func pairsExposeOpposingFlagsAndPreserveIndependentDecisionsAndSourceBytes() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let raw = try f.file("DCIM/pair.CR3", "raw original")
    let jpg = try f.file("DCIM/pair.JPEG", "jpeg original")
    let xmp = XMPSidecar.url(for: raw)
    let packet =
      "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\" xmlns:crs=\"http://ns.adobe.com/camera-raw-settings/1.0/\" crs:Exposure2012=\"0.35\"/></rdf:RDF></x:xmpmeta>"
    try Data(packet.utf8).write(to: xmp)
    _ = try f.file("DCIM/pair.acr", "develop companion")
    let before = try f.tree()
    let session = try await f.store.beginSourceReview(f.card)
    try await f.decide(raw, CullingDecision(rating: 5, flag: .pick))
    try await f.decide(jpg, CullingDecision(rating: 2, flag: .reject))
    let entry = try await f.store.loadSourceReview(session, image: raw).0
    let edit = PhotoEdit(
      quarterTurns: 1, mirrored: true, crop: PhotoCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.6))
    try await f.store.saveSourceEdits(
      [ImageEditWrite(image: raw, identity: #require(entry.identity), edit: edit)], session: session
    )
    let plan = try await f.plan(.picks)
    #expect(
      plan.addedPairImages == [PhotoPath.canonical(jpg)]
        && plan.opposingPairImages == [PhotoPath.canonical(jpg)])
    await #expect(throws: (any Error).self) {
      try await f.operations.copyReviewed(plan, store: f.store)
    }
    #expect(!FileManager.default.fileExists(atPath: f.primary.path))
    let report = try await f.operations.copyReviewed(
      plan, store: f.store, includeOpposingPairs: true)
    #expect(report.photoCount == 2 && report.pendingMetadata == 0)
    for root in [f.primary, f.backup] {
      let r = root.appendingPathComponent("DCIM/pair.CR3")
      let j = root.appendingPathComponent("DCIM/pair.JPEG")
      #expect(try MediaOperations.checksum(r) == MediaOperations.checksum(raw))
      #expect(try MediaOperations.checksum(j) == MediaOperations.checksum(jpg))
      #expect(try await f.store.loadImageState(for: r).1 == edit)
      #expect(try await f.store.load(for: r).decision == CullingDecision(rating: 5, flag: .pick))
      #expect(try await f.store.load(for: j).decision == CullingDecision(rating: 2, flag: .reject))
      #expect(
        try String(contentsOf: XMPSidecar.url(for: r), encoding: .utf8).contains(
          "Exposure2012=\"0.35\""))
      #expect(
        try Data(contentsOf: root.appendingPathComponent("DCIM/pair.acr"))
          == Data("develop companion".utf8))
      let manifest = try JSONDecoder().decode(
        IngestManifest.self,
        from: Data(contentsOf: root.appendingPathComponent(".photo-ingest.json")))
      #expect(manifest.records["DCIM/pair.xmp"]?.sha256 == XMPSidecar.digest(Data(packet.utf8)))
    }
    #expect(try f.tree() == before)
  }

  @Test func pairOptionOffCopiesOnlyTheChosenPhysicalFileAndRequiredSidecars() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("same.ARW")
    _ = try f.file("same.jpg")
    try XMPSidecar.merging(CullingDecision(rating: 2), into: nil).write(to: XMPSidecar.url(for: a))
    let plan = try await f.plan(.selection, selection: [a], pairs: false)
    #expect(plan.images.count == 1 && plan.files.count == 2 && plan.addedPairImages.isEmpty)
    _ = try await f.operations.copyReviewed(plan, store: f.store)
    #expect(
      !FileManager.default.fileExists(atPath: f.primary.appendingPathComponent("same.jpg").path))
  }

  @Test func frozenListAndDestinationArrivalsUseTheReviewedRevision() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("a.jpg")
    let b = try f.file("b.jpg")
    _ = try await f.store.beginSourceReview(f.card)
    try await f.decide(a, CullingDecision(rating: 3, flag: .pick))
    let plan = try await f.plan(.picks)
    try await f.decide(a, CullingDecision(rating: 1, flag: .reject))
    try await f.decide(b, CullingDecision(rating: 5, flag: .pick))
    let report = try await f.operations.copyReviewed(plan, store: f.store) { progress in
      for image in progress.verifiedImages {
        do {
          #expect(
            try await f.store.load(for: image).decision == CullingDecision(rating: 3, flag: .pick))
        } catch { Issue.record(error) }
        #expect(
          FileManager.default.fileExists(
            atPath: f.backup.appendingPathComponent(image.lastPathComponent).path))
      }
    }
    #expect(report.photoCount == 1 && report.changedSourceReviews == 1)
    #expect(!FileManager.default.fileExists(atPath: f.primary.appendingPathComponent("b.jpg").path))
  }

  @Test(arguments: [0, 1, 2]) func restartRecoversEveryHandoverBoundaryWithoutReplayingNewerWork(
    stage: Int
  ) async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("a.ARW")
    let original = try XMPSidecar.merging(CullingDecision(rating: 1), into: nil)
    try original.write(to: XMPSidecar.url(for: a))
    _ = try await f.store.beginSourceReview(f.card)
    try await f.decide(a, CullingDecision(rating: 5, flag: .pick))
    let plan = try await f.plan()
    try f.stageBytes(plan)
    if stage >= 1 {
      try await f.store.installReviewCopy(
        plan, family: plan.families[0], expectedImages: f.expectedTargets(plan))
    }
    if stage == 2 {
      let target = f.primary.appendingPathComponent("a.ARW")
      try XMPSidecar.merging(plan.images[0].decision, into: original, fields: plan.images[0].fields)
        .write(to: XMPSidecar.url(for: target), options: .atomic)
    }
    let store = DecisionStore(
      databaseURL: f.database, sourceProtection: SourceProtection(registryURL: f.registry))
    let operations = MediaOperations(journalDirectory: f.journals, sourceProtection: f.policy)
    let saved = try #require(await operations.savedReviewedCopies().first)
    let result = try await operations.copyReviewed(saved, store: store)
    #expect(result.pendingMetadata == 0)
    let target = f.primary.appendingPathComponent("a.ARW")
    #expect(try await store.load(for: target).decision == CullingDecision(rating: 5, flag: .pick))
    _ = try await store.save(CullingDecision(rating: 2, flag: .reject), for: target)
    let edit = PhotoEdit(quarterTurns: 2)
    try await store.saveImageEdits([
      ImageEditWrite(
        image: target, identity: #require(try await store.load(for: target).identity), edit: edit)
    ])
    var patch = MetadataPatch()
    patch.fields[.caption] = "Later destination caption"
    let metadata = try #require(await store.prepareMetadata(patch, images: [target]).first)
    _ = try await store.saveMetadata(metadata)
    let later = try Data(contentsOf: XMPSidecar.url(for: target))
    _ = try await operations.copyReviewed(saved, store: store)
    #expect(try Data(contentsOf: XMPSidecar.url(for: target)) == later)
    #expect(try await store.loadImageState(for: target).1 == edit)
    #expect(try await store.load(for: target).decision == CullingDecision(rating: 2, flag: .reject))
    #expect(
      try await store.load(for: f.backup.appendingPathComponent("a.ARW")).decision.rating == 5)
    #expect(try Data(contentsOf: XMPSidecar.url(for: a)) == original)
  }

  @Test func metadataConflictStaysLocalAndExplicitRetryDoesNotOverwriteExternalCaption()
    async throws
  {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("a.jpg")
    _ = try await f.store.beginSourceReview(f.card)
    try await f.decide(a, CullingDecision(rating: 4, flag: .pick))
    let plan = try await f.plan()
    try f.stageBytes(plan)
    try await f.store.installReviewCopy(
      plan, family: plan.families[0], expectedImages: f.expectedTargets(plan))
    let target = f.backup.appendingPathComponent("a.jpg")
    var value = DescriptiveMetadata()
    value.fields[.caption] = "External caption"
    let external = try XMPSidecar.mergingMetadata(
      value, fields: [.caption], keywords: false, into: nil)
    try external.write(to: XMPSidecar.url(for: target))
    let result = try await f.operations.copyReviewed(plan, store: f.store)
    #expect(result.pendingMetadata == 1)
    #expect(try await f.store.load(for: target).decision.rating == 4)
    #expect(try Data(contentsOf: XMPSidecar.url(for: target)) == external)
    let repeated = try await f.operations.copyReviewed(plan, store: f.store)
    #expect(repeated.pendingMetadata == 1)
    #expect(try Data(contentsOf: XMPSidecar.url(for: target)) == external)
    // The existing explicit Use Local conflict action merges decisions into the latest packet.
    _ = try await f.store.save(
      CullingDecision(rating: 4, flag: .pick), for: target, resolveConflict: true)
    let finished = try await f.operations.copyReviewed(plan, store: f.store)
    #expect(finished.pendingMetadata == 0)
    #expect(
      try XMPSidecar.descriptive(Data(contentsOf: XMPSidecar.url(for: target))).fields[.caption]
        == "External caption")
  }

  @Test func updatedSourceMetadataRequiresExplicitChoiceAndOnlyOwnedFieldsOverride() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("a.jpg")
    try XMPSidecar.merging(CullingDecision(rating: 1), into: nil).write(to: XMPSidecar.url(for: a))
    _ = try await f.store.beginSourceReview(f.card)
    try await f.decide(a, CullingDecision(rating: 5), fields: .rating)
    let newer = try XMPSidecar.merging(CullingDecision(rating: 2, flag: .pick), into: nil)
    try newer.write(to: XMPSidecar.url(for: a), options: .atomic)
    await #expect(throws: (any Error).self) { try await f.plan() }
    let plan = try await f.plan(acceptMetadata: true)
    #expect(
      plan.images[0].fields == .rating
        && plan.images[0].decision == CullingDecision(rating: 5, flag: .pick))
    _ = try await f.operations.copyReviewed(plan, store: f.store)
    #expect(
      try await f.store.load(for: f.primary.appendingPathComponent("a.jpg")).decision
        == CullingDecision(rating: 5, flag: .pick))
    #expect(try Data(contentsOf: XMPSidecar.url(for: a)) == newer)
  }

  @Test func cancellationKeepsVerifiedFilesAndSavedPlanForExactResume() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("a.jpg")
    _ = try f.file("b.jpg")
    _ = try await f.store.beginSourceReview(f.card)
    try await f.decide(a, CullingDecision(rating: 3, flag: .pick))
    let plan = try await f.plan()
    let task = Task {
      try await f.operations.copyReviewed(plan, store: f.store) { progress in
        if !progress.verifiedImages.isEmpty { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    do {
      _ = try await task.value
      Issue.record("Expected cancellation")
    } catch is CancellationError {}
    let saved = try #require(await f.operations.savedReviewedCopies().first)
    #expect(saved.id == plan.id)
    let report = try await f.operations.copyReviewed(saved, store: f.store)
    #expect(report.photoCount == 2 && report.pendingMetadata == 0)
    #expect(
      try await f.store.load(for: f.primary.appendingPathComponent("a.jpg")).decision.rating == 3)
  }

  @Test func sourceReplacementDestinationCollisionAndOverlapNeverTransferDecisions() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("a.jpg")
    let session = try await f.store.beginSourceReview(f.card)
    await #expect(throws: (any Error).self) {
      try await f.operations.planReviewedCopy(
        session: session, scope: .all, primary: f.card.appendingPathComponent("bad"),
        backup: f.backup, store: f.store)
    }
    let plan = try await f.plan()
    try FileManager.default.createDirectory(at: f.primary, withIntermediateDirectories: true)
    let target = f.primary.appendingPathComponent("a.jpg")
    try Data("different".utf8).write(to: target)
    await #expect(throws: (any Error).self) {
      try await f.operations.copyReviewed(plan, store: f.store)
    }
    #expect(try Data(contentsOf: target) == Data("different".utf8))
    try FileManager.default.removeItem(at: a)
    try Data("replacement".utf8).write(to: a)
    await #expect(throws: (any Error).self) {
      try await f.operations.copyReviewed(plan, store: f.store)
    }
    #expect(try await f.store.load(for: a).decision == CullingDecision())
  }

  @Test func ambiguousRawSidecarsAndDestinationSymlinksAreRefused() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    _ = try f.file("same.ARW")
    _ = try f.file("same.ORF")
    _ = try f.file("same.xmp", "ambiguous")
    await #expect(throws: (any Error).self) { try await f.plan() }
    try FileManager.default.removeItem(at: f.card.appendingPathComponent("same.xmp"))
    try FileManager.default.createDirectory(
      at: f.root.appendingPathComponent("Elsewhere"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: f.root.appendingPathComponent("Photos"),
      withDestinationURL: f.root.appendingPathComponent("Elsewhere"))
    await #expect(throws: (any Error).self) { try await f.plan() }
    #expect(
      try FileManager.default.contentsOfDirectory(
        atPath: f.root.appendingPathComponent("Elsewhere").path
      ).isEmpty)
  }
  @Test func tornLastJournalEventIsReverifiedAndRepairedOnResume() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    _ = try f.file("a.jpg")
    let plan = try await f.plan()
    try f.stageBytes(plan)
    let journal = f.journals.appendingPathComponent("review-copy-\(plan.id.uuidString).events")
    let handle = try FileHandle(forWritingTo: journal)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{incomplete".utf8))
    try handle.close()
    _ = try await f.operations.copyReviewed(plan, store: f.store)
    let data = try Data(contentsOf: journal)
    #expect(data.last == 0x0A)
    for line in data.split(separator: 0x0A) {
      _ = try JSONDecoder().decode(ReviewCopyEvent.self, from: Data(line))
    }
  }

  @Test func destinationReplacementBetweenVerificationAndTransferIsRefused() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    _ = try f.file("a.jpg")
    let plan = try await f.plan()
    try f.stageBytes(plan)
    let expected = try f.expectedTargets(plan)
    let image = plan.primary.appendingPathComponent("a.jpg")
    try Data("replaced destination".utf8).write(to: image, options: .atomic)
    await #expect(throws: DecisionStoreError.self) {
      try await f.store.installReviewCopy(plan, family: plan.families[0], expectedImages: expected)
    }
    #expect(try await f.store.load(for: image).decision == CullingDecision())
  }

  @Test func failedDestinationSidecarWriteKeepsLocalReviewAndCanBeRetried() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("a.jpg")
    _ = try await f.store.beginSourceReview(f.card)
    try await f.decide(a, CullingDecision(rating: 4, flag: .pick))
    let plan = try await f.plan()
    try f.stageBytes(plan)
    try await f.store.installReviewCopy(
      plan, family: plan.families[0], expectedImages: f.expectedTargets(plan))
    let sidecar = XMPSidecar.url(for: f.backup.appendingPathComponent("a.jpg"))
    try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
    let report = try await f.operations.copyReviewed(plan, store: f.store)
    #expect(report.pendingMetadata == 1)
    #expect(
      try await f.store.load(for: f.backup.appendingPathComponent("a.jpg")).decision.rating == 4)
    try FileManager.default.removeItem(at: sidecar)
    #expect(try await f.operations.copyReviewed(plan, store: f.store).pendingMetadata == 0)
    #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: a).path))
  }

  @Test func readOnlyDestinationBrowseAfterCrashDoesNotBlockResumeButRealIntentDoes() async throws {
    let f = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("a.jpg")
    _ = try await f.store.beginSourceReview(f.card)
    try await f.decide(a, CullingDecision(rating: 5, flag: .pick))
    let plan = try await f.plan()
    try f.stageBytes(plan)
    let target = plan.primary.appendingPathComponent("a.jpg")
    _ = try await f.store.loadImageState(for: target)
    _ = try await f.store.loadMetadata(for: target)
    #expect(try await f.operations.copyReviewed(plan, store: f.store).pendingMetadata == 0)
    #expect(try await f.store.load(for: target).decision.rating == 5)
    let other = try ReviewedIngestFixture()
    defer { try? FileManager.default.removeItem(at: other.root) }
    let b = try other.file("b.jpg")
    _ = try await other.store.beginSourceReview(other.card)
    try await other.decide(b, CullingDecision(rating: 5, flag: .pick))
    let second = try await other.plan()
    try other.stageBytes(second)
    let edited = second.primary.appendingPathComponent("b.jpg")
    _ = try await other.store.load(for: edited)
    // Even an explicit same-value save establishes destination intent.
    _ = try await other.store.save(CullingDecision(), for: edited)
    await #expect(throws: (any Error).self) {
      try await other.operations.copyReviewed(second, store: other.store)
    }
    #expect(try await other.store.load(for: edited).decision == CullingDecision())
  }

}
