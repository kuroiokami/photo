import Foundation
import Testing

@testable import PhotoCore

private actor JournalObservations {
  var primarySnapshot: Data?
  var backupSnapshot: Data?
  var primaryEvents = Data()
  var backupEvents = Data()
  var count = 0
  func observe(primary: URL, backup: URL) throws {
    let a = try Data(contentsOf: primary.appendingPathComponent(".photo-ingest.json"))
    let b = try Data(contentsOf: backup.appendingPathComponent(".photo-ingest.json"))
    if let primarySnapshot { #expect(a == primarySnapshot) }
    if let backupSnapshot { #expect(b == backupSnapshot) }
    primarySnapshot = a
    backupSnapshot = b
    for (root, previous) in [(primary, primaryEvents), (backup, backupEvents)] {
      let data = try Data(contentsOf: root.appendingPathComponent(".photo-ingest.events"))
      #expect(data.starts(with: previous))
      #expect(data.last == 0x0A)
      #expect(data.filter { $0 == 0x0A }.count == count + 2)
      if root == primary { primaryEvents = data } else { backupEvents = data }
    }
    count += 1
  }
}

struct IngestJournalTests {
  private func fixture(count: Int = 3) throws -> (URL, URL, URL, URL) {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("card")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    for i in 0..<count {
      try Data("source-\(i)".utf8).write(to: source.appendingPathComponent("photo\(i).jpg"))
    }
    return (
      root, source, root.appendingPathComponent("primary"), root.appendingPathComponent("backup")
    )
  }

  @Test func appendsOnlyNewRecordsBeforeArrivalAndCompactsOnceAtCompletion() async throws {
    let (root, source, primary, backup) = try fixture(count: 24)
    defer { try? FileManager.default.removeItem(at: root) }
    let operations = MediaOperations()
    let observations = JournalObservations()
    let result = try await operations.ingest(source: source, primary: primary, backup: backup) {
      _ in
      do { try await observations.observe(primary: primary, backup: backup) } catch {
        Issue.record(error)
      }
    }
    #expect(result.copiedCount == 48)
    #expect(await observations.count == 24)
    for destination in [primary, backup] {
      let manifest = destination.appendingPathComponent(".photo-ingest.json")
      #expect(try await operations.readManifest(manifest).records.count == 24)
      #expect(!FileManager.default.fileExists(atPath: IngestJournal.url(for: manifest).path))
      for i in 0..<24 {
        #expect(
          try Data(contentsOf: destination.appendingPathComponent("photo\(i).jpg"))
            == Data("source-\(i)".utf8))
        #expect(
          try Data(contentsOf: source.appendingPathComponent("photo\(i).jpg"))
            == Data("source-\(i)".utf8))
      }
    }
  }

  @Test func interruptedIngestReplaysAndDropsOnlyAnUnterminatedTail() async throws {
    let (root, source, primary, backup) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let interrupted = Task {
      try await MediaOperations().ingest(source: source, primary: primary, backup: backup) { item in
        if item.completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    await #expect(throws: CancellationError.self) { try await interrupted.value }
    let operations = MediaOperations()
    for destination in [primary, backup] {
      let manifest = destination.appendingPathComponent(".photo-ingest.json")
      let events = IngestJournal.url(for: manifest)
      let handle = try FileHandle(forWritingTo: events)
      _ = try handle.seekToEnd()
      try handle.write(contentsOf: Data("{torn final record".utf8))
      try handle.close()
      #expect(try await operations.readManifest(manifest).records.count == 1)
    }
    let resumed = try await operations.ingest(source: source, primary: primary, backup: backup)
    #expect(resumed.copiedCount == 4)
    #expect(resumed.alreadyVerifiedCount == 2)
    #expect(
      try await operations.readManifest(primary.appendingPathComponent(".photo-ingest.json"))
        .records.count == 3)
  }

  @Test func snapshotCursorPreventsOldJournalUndoingRenameMappings() async throws {
    let (root, source, primary, _) = try fixture(count: 1)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: true)
    let url = primary.appendingPathComponent(".photo-ingest.json")
    let operations = MediaOperations()
    let writer = try IngestJournalWriter(
      manifest: url,
      protection: SourceProtection(registryURL: root.appendingPathComponent("protection.json")))
    let old = IngestRecord(
      relativePath: "photo0.jpg", originalFilename: "photo0.jpg",
      source: source.appendingPathComponent("photo0.jpg"), sha256: "digest",
      verifiedDestinations: [primary.appendingPathComponent("photo0.jpg")])
    let cursor = try writer.append(old)
    let renamed = IngestRecord(
      relativePath: old.relativePath, originalFilename: old.originalFilename, source: old.source,
      sha256: old.sha256, verifiedDestinations: [primary.appendingPathComponent("renamed.jpg")])
    let snapshot = IngestManifest(records: [old.relativePath: renamed], journalCheckpoint: cursor)
    let invalid = IngestManifest(
      records: snapshot.records,
      journalCheckpoint: IngestJournalCursor(id: cursor.id, offset: cursor.offset + 1))
    try await operations.durableJSON(invalid, at: url)
    await #expect(throws: (any Error).self) { try await operations.readManifest(url) }
    // Simulate interruption after snapshot fsync but before journal removal.
    try await operations.durableJSON(snapshot, at: url)
    #expect(
      try await operations.readManifest(url).records[old.relativePath]?.verifiedDestinations
        == renamed.verifiedDestinations)
    try await operations.checkpointManifest(snapshot, at: url)
    // A new journal generation must replay even when an old cursor is retained.
    let next = try IngestJournalWriter(
      manifest: url,
      protection: SourceProtection(registryURL: root.appendingPathComponent("protection.json")))
    _ = try next.append(old)
    #expect(
      try await operations.readManifest(url).records[old.relativePath]?.verifiedDestinations
        == old.verifiedDestinations)
  }

  @Test func malformedCompleteRecordsAndUnsupportedVersionsRemainUntouched() async throws {
    let (root, _, primary, _) = try fixture(count: 0)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: true)
    let manifest = primary.appendingPathComponent(".photo-ingest.json")
    let events = IngestJournal.url(for: manifest)
    let operations = MediaOperations()
    for bytes in [
      "{\"version\":9,\"id\":\"\(UUID())\"}\n", "{\"version\":1,\"id\":\"\(UUID())\"}\ninvalid\n",
    ] {
      let data = Data(bytes.utf8)
      try data.write(to: events)
      await #expect(throws: (any Error).self) { try await operations.readManifest(manifest) }
      #expect(try Data(contentsOf: events) == data)
    }
    try Data("{unfinished header".utf8).write(to: events)
    let recovered = try await operations.readManifest(manifest)
    #expect(recovered.records.isEmpty)
    try await operations.checkpointManifest(recovered, at: manifest)
    #expect(!FileManager.default.fileExists(atPath: events.path))
  }

  @Test func secondJournalFailureDoesNotPublishAndRetryReverifiesBothCopies() async throws {
    let (root, source, primary, backup) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let saved = root.appendingPathComponent("saved-events")
    let events = backup.appendingPathComponent(".photo-ingest.events")
    let observations = JournalObservations()
    await #expect(throws: (any Error).self) {
      try await MediaOperations().ingest(source: source, primary: primary, backup: backup) { item in
        do {
          try await observations.observe(primary: primary, backup: backup)
          if item.completed == 1 {
            try Data(contentsOf: events).write(to: saved)
            try Data("unrecognized replacement\n".utf8).write(to: events, options: .atomic)
          }
        } catch { Issue.record(error) }
      }
    }
    #expect(await observations.count == 1)
    try Data(contentsOf: saved).write(to: events, options: .atomic)
    let result = try await MediaOperations().ingest(
      source: source, primary: primary, backup: backup)
    #expect(result.alreadyVerifiedCount == 4)
    #expect(result.copiedCount == 2)
    for i in 0..<3 {
      #expect(
        try Data(contentsOf: source.appendingPathComponent("photo\(i).jpg"))
          == Data("source-\(i)".utf8))
    }
  }

  @Test func legacyManifestWithoutCursorRetainsRenamedDestinations() async throws {
    let (root, source, primary, backup) = try fixture(count: 1)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = source.appendingPathComponent("photo0.jpg")
    let bytes = try Data(contentsOf: image)
    let targets = [primary, backup].map { $0.appendingPathComponent("renamed.jpg") }
    for target in targets {
      try FileManager.default.createDirectory(
        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: target)
    }
    let record = IngestRecord(
      relativePath: "photo0.jpg", originalFilename: "photo0.jpg", source: image,
      sha256: try MediaOperations.checksum(image), verifiedDestinations: targets)
    let legacy = try JSONEncoder().encode(IngestManifest(records: [record.relativePath: record]))
    #expect(!(String(decoding: legacy, as: UTF8.self).contains("journalCheckpoint")))
    for folder in [primary, backup] {
      try legacy.write(to: folder.appendingPathComponent(".photo-ingest.json"))
    }
    let result = try await MediaOperations().ingest(
      source: source, primary: primary, backup: backup)
    #expect(result.copiedCount == 0)
    #expect(result.alreadyVerifiedCount == 2)
    for folder in [primary, backup] {
      #expect(
        !FileManager.default.fileExists(atPath: folder.appendingPathComponent("photo0.jpg").path))
      #expect(try Data(contentsOf: folder.appendingPathComponent("renamed.jpg")) == bytes)
    }
  }

  @Test func journalSymlinkNeverWritesOutsideDestination() async throws {
    let (root, source, primary, backup) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: true)
    let victim = root.appendingPathComponent("unrelated")
    let bytes = Data("leave untouched".utf8)
    try bytes.write(to: victim)
    try FileManager.default.createSymbolicLink(
      at: primary.appendingPathComponent(".photo-ingest.events"), withDestinationURL: victim)
    await #expect(throws: (any Error).self) {
      try await MediaOperations().ingest(source: source, primary: primary, backup: backup)
    }
    #expect(try Data(contentsOf: victim) == bytes)
  }
}
