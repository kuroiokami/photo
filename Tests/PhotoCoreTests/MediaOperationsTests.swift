import Foundation
import PhotoCore
import Testing

private struct FixedMetadata: PhotoMetadataReading {
  func metadata(for file: URL) async throws -> PhotoMetadata {
    var value = PhotoMetadata(pixelWidth: 10, pixelHeight: 10)
    value.captureTime = Date(timeIntervalSince1970: 1_700_000_000)
    return value
  }
}
struct MediaOperationsTests {
  private func folder() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
  @Test func ingestVerifiesBothCopiesResumesAndPreservesCompanions() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("card/DCIM")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    for name in ["café.CR3", "café.JPG", "café.xmp", "café.acr", "café.JPG.xmp"] {
      try Data(name.utf8).write(to: source.appendingPathComponent(name))
    }
    try Data().write(to: source.appendingPathComponent("ignore.txt"))
    try FileManager.default.createSymbolicLink(
      at: source.appendingPathComponent("linked.ORF"),
      withDestinationURL: source.appendingPathComponent("café.CR3"))
    let primary = root.appendingPathComponent("primary")
    let backup = root.appendingPathComponent("backup")
    let operations = MediaOperations(journalDirectory: root.appendingPathComponent("journals"))
    let report = try await operations.ingest(
      source: source.deletingLastPathComponent(), primary: primary, backup: backup)
    #expect(report.fileCount == 5)
    #expect(report.copiedCount == 10)
    for name in ["café.CR3", "café.JPG", "café.xmp", "café.acr", "café.JPG.xmp"] {
      let data = try Data(contentsOf: source.appendingPathComponent(name))
      #expect(try Data(contentsOf: primary.appendingPathComponent("DCIM/" + name)) == data)
      #expect(try Data(contentsOf: backup.appendingPathComponent("DCIM/" + name)) == data)
    }
    let resumed = try await operations.ingest(
      source: source.deletingLastPathComponent(), primary: primary, backup: backup)
    #expect(resumed.copiedCount == 0)
    #expect(resumed.alreadyVerifiedCount == 10)
    try Data("different".utf8).write(to: primary.appendingPathComponent("DCIM/café.CR3"))
    await #expect(throws: (any Error).self) {
      try await operations.ingest(
        source: source.deletingLastPathComponent(), primary: primary, backup: backup)
    }
    #expect(
      try Data(contentsOf: source.appendingPathComponent("café.CR3")) == Data("café.CR3".utf8))
  }
  @Test func ingestRejectsOverlapAndNeverFollowsDestinationSymlinks() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("card")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data().write(to: source.appendingPathComponent("a.ORF"))
    let operations = MediaOperations()
    await #expect(throws: (any Error).self) {
      try await operations.ingest(
        source: source, primary: source.appendingPathComponent("inside"),
        backup: root.appendingPathComponent("backup"))
    }
    let link = root.appendingPathComponent("linked")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
    await #expect(throws: (any Error).self) {
      try await operations.ingest(
        source: source, primary: link, backup: root.appendingPathComponent("backup"))
    }
    let primary = root.appendingPathComponent("primary")
    try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: true)
    let alias = primary.appendingPathComponent("a.ORF")
    try FileManager.default.createSymbolicLink(
      at: alias, withDestinationURL: source.appendingPathComponent("a.ORF"))
    await #expect(throws: (any Error).self) {
      try await operations.ingest(
        source: source, primary: primary, backup: root.appendingPathComponent("backup"))
    }
    #expect(try alias.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
  }
  @Test func renamePlansPairAndEveryCompanionThenUndoRestoresBytes() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let names = ["a.ORF", "a.JPG", "a.xmp", "a.acr", "a.JPG.xmp", "b.CR2"]
    for name in names { try Data(name.utf8).write(to: root.appendingPathComponent(name)) }
    let operations = MediaOperations(journalDirectory: root.appendingPathComponent("journals"))
    let plan = try await operations.planRename(
      images: [root.appendingPathComponent("a.ORF"), root.appendingPathComponent("b.CR2")],
      pattern: "{date}_{camera}_{sequence}", camera: "C1", start: 1, reader: FixedMetadata())
    #expect(plan.entries.count == 6)
    #expect(plan.nextSequence == 3)
    #expect(
      Set(
        plan.entries.filter { $0.original.lastPathComponent.hasPrefix("a.") }.map {
          $0.destination.lastPathComponent.components(separatedBy: ".")[0]
        }
      ).count == 1)
    let journal = try await operations.rename(plan)
    for entry in plan.entries {
      #expect(
        try Data(contentsOf: entry.destination) == Data(entry.original.lastPathComponent.utf8))
    }
    try await operations.undoRename(journal: journal)
    for name in names {
      #expect(try Data(contentsOf: root.appendingPathComponent(name)) == Data(name.utf8))
    }
    #expect(try await operations.pendingRenames().isEmpty)
  }
  @Test func renameRejectsCollisionsUnsafeTokensAndChangedInputs() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("a.CR3")
    let b = root.appendingPathComponent("b.CR3")
    try Data("a".utf8).write(to: a)
    try Data("b".utf8).write(to: b)
    let operations = MediaOperations(journalDirectory: root.appendingPathComponent("journals"))
    await #expect(throws: (any Error).self) {
      try await operations.planRename(
        images: [a, b], pattern: "same", camera: "", start: 1, reader: FixedMetadata())
    }
    await #expect(throws: (any Error).self) {
      try await operations.planRename(
        images: [a], pattern: "../bad", camera: "", start: 1, reader: FixedMetadata())
    }
    let plan = try await operations.planRename(
      images: [a], pattern: "new", camera: "", start: 1, reader: FixedMetadata())
    try Data("replacement".utf8).write(to: a)
    await #expect(throws: (any Error).self) { try await operations.rename(plan) }
    #expect(try Data(contentsOf: b) == Data("b".utf8))
  }
  @Test func interruptedRenameCanBeRecoveredFromStagingWithoutAcknowledgement() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("a.CR2")
    try Data("original".utf8).write(to: image)
    let operations = MediaOperations(journalDirectory: root.appendingPathComponent("journals"))
    let plan = try await operations.planRename(
      images: [image], pattern: "new", camera: "", start: 1, reader: FixedMetadata())
    let journal = try await operations.rename(plan)
    let entry = try #require(plan.entries.first)
    // Simulate an interrupted operation with its image in the hidden staging path.
    try FileManager.default.moveItem(
      at: entry.destination, to: root.appendingPathComponent(".photo-rename-\(plan.id)-0"))
    var json = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [String: Any])
    json["phase"] = "executing"
    try JSONSerialization.data(withJSONObject: json).write(to: journal)
    #expect(try await operations.pendingRenames().count == 1)
    try await operations.undoRename(journal: journal)
    #expect(try Data(contentsOf: image) == Data("original".utf8))
  }
  @Test func handoffCopiesOnlyChosenImagesAndSidecarsWithoutOverwriting() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    for name in ["keep.CR3", "keep.xmp", "keep.acr", "reject.CR3"] {
      try Data(name.utf8).write(to: source.appendingPathComponent(name))
    }
    let target = root.appendingPathComponent("handoff")
    let count = try await MediaOperations().prepareHandoff(
      images: [source.appendingPathComponent("keep.CR3")], destination: target)
    #expect(count == 1)
    #expect(
      !FileManager.default.fileExists(atPath: target.appendingPathComponent("reject.CR3").path))
    #expect(
      try Data(contentsOf: target.appendingPathComponent("keep.acr")) == Data("keep.acr".utf8))
  }
  @Test func renameMappingKeepsReingestIncrementalAndRetainsEditedWorkingMetadata() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("card")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("original RAW".utf8).write(to: source.appendingPathComponent("a.ORF"))
    try Data("original sidecar".utf8).write(to: source.appendingPathComponent("a.xmp"))
    let primary = root.appendingPathComponent("primary")
    let backup = root.appendingPathComponent("backup")
    let operations = MediaOperations(journalDirectory: root.appendingPathComponent("journals"))
    _ = try await operations.ingest(source: source, primary: primary, backup: backup)
    let plan = try await operations.planRename(
      images: [primary.appendingPathComponent("a.ORF")], pattern: "renamed", camera: "", start: 1,
      reader: FixedMetadata())
    _ = try await operations.rename(plan)
    try Data("updated working metadata".utf8).write(
      to: primary.appendingPathComponent("renamed.xmp"))
    let resumed = try await operations.ingest(source: source, primary: primary, backup: backup)
    #expect(resumed.copiedCount == 0)
    #expect(resumed.preservedMetadataCount == 1)
    #expect(!FileManager.default.fileExists(atPath: primary.appendingPathComponent("a.ORF").path))
    #expect(
      try Data(contentsOf: primary.appendingPathComponent("renamed.xmp"))
        == Data("updated working metadata".utf8))
  }
  @Test func caseOnlyRenameCanUndoAndHardLinkAliasesAreRejected() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("a.CR3")
    try Data("original".utf8).write(to: image)
    let operations = MediaOperations(journalDirectory: root.appendingPathComponent("journals"))
    let plan = try await operations.planRename(
      images: [image], pattern: "A", camera: "", start: 1, reader: FixedMetadata())
    let journal = try await operations.rename(plan)
    try await operations.undoRename(journal: journal)
    #expect(try image.resourceValues(forKeys: [.nameKey]).name == "a.CR3")
    let link = root.appendingPathComponent("other.CR3")
    try FileManager.default.linkItem(at: image, to: link)
    await #expect(throws: (any Error).self) {
      try await operations.planRename(
        images: [image, link], pattern: "{sequence}", camera: "", start: 1, reader: FixedMetadata())
    }
  }
  @Test func handoffRefusesStaleUnselectedPhotos() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("handoff")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let image = source.appendingPathComponent("keep.CR3")
    try Data().write(to: image)
    let stale = target.appendingPathComponent("rejected.CR3")
    try Data("untouched".utf8).write(to: stale)
    await #expect(throws: (any Error).self) {
      try await MediaOperations().prepareHandoff(images: [image], destination: target)
    }
    #expect(try Data(contentsOf: stale) == Data("untouched".utf8))
  }

}
