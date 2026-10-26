import Foundation
import PhotoCore
import Testing

private struct ArrivalMetadata: PhotoMetadataReading {
  func metadata(for file: URL) async throws -> PhotoMetadata {
    var value = PhotoMetadata(pixelWidth: 100, pixelHeight: 80)
    value.iso = file.lastPathComponent.hasPrefix("b") ? 200 : 100
    return value
  }
}
private actor ArrivalAudit {
  var groups: [[URL]] = []
  var valid = true
  var failures: [String] = []
  func record(_ progress: IngestProgress, primary: URL, backup: URL) {
    guard !progress.verifiedImages.isEmpty else { return }
    groups.append(progress.verifiedImages)
    for image in progress.verifiedImages {
      let relative = image.pathComponents.dropFirst(
        PhotoPath.canonical(primary).pathComponents.count
      ).joined(
        separator: "/")
      let copied = backup.appendingPathComponent(relative)
      if (try? Data(contentsOf: image)) != (try? Data(contentsOf: copied)) {
        valid = false
        failures.append("Copy mismatch: " + image.path + " -> " + copied.path)
      }
      if image.lastPathComponent.hasPrefix("a.") {
        for name in ["a.ARW", "a.JPG", "a.xmp", "a.JPG.xmp"] {
          if !FileManager.default.fileExists(
            atPath: image.deletingLastPathComponent().appendingPathComponent(name).path)
          {
            valid = false
            failures.append("Missing " + name + " when publishing " + image.lastPathComponent)
          }
        }
      }
    }
  }
}
@MainActor
struct VerifiedArrivalTests {
  private func root() throws -> URL {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
  @Test func missingDestinationAndExistingAliasHaveTheSameCanonicalPath() throws {
    let folder = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("working/subfolder")
    let before = PhotoPath.canonical(folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(
        at: folder.deletingLastPathComponent().deletingLastPathComponent())
    }
    #expect(PhotoPath.canonical(folder) == before)
    #expect(
      PhotoPath.canonical(
        URL(fileURLWithPath: "/private/tmp").appendingPathComponent(
          folder.pathComponents.suffix(3).joined(separator: "/"))) == before)
  }
  @Test func arrivalsWaitForBothCopiesAndCompleteFamiliesAcrossSubfolders() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("card")
    let primary = root.appendingPathComponent("working")
    let backup = root.appendingPathComponent("backup")
    for directory in ["A", "B"] {
      let folder = source.appendingPathComponent(directory)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for name in ["a.ARW", "a.JPG", "a.xmp", "a.JPG.xmp"] {
        try Data((directory + name).utf8).write(to: folder.appendingPathComponent(name))
      }
    }
    let audit = ArrivalAudit()
    _ = try await MediaOperations().ingest(source: source, primary: primary, backup: backup) {
      progress in
      await audit.record(progress, primary: primary, backup: backup)
    }
    let failures = await audit.failures
    #expect(failures == [])
    #expect(await audit.valid)
    let groups = await audit.groups
    #expect(groups.count == 2)
    #expect(
      groups.allSatisfy {
        $0.count == 2 && $0[0].deletingLastPathComponent() == $0[1].deletingLastPathComponent()
      })
  }
  @Test func anEmptyVerifiedSetCannotExposeFilesAlreadyOnDisk() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("a.jpg")
    let b = root.appendingPathComponent("b.jpg")
    try Data().write(to: a)
    try Data().write(to: b)
    let state = WorkspaceState(
      decisionStore: DecisionStore(databaseURL: root.appendingPathComponent("db")))
    await state.openFolder(root, verifiedImages: [])
    #expect(state.filePhotos.isEmpty)
    await state.publishVerified([a], in: root, using: ArrivalMetadata())?.value
    #expect(state.photos.map(\.filename) == ["a.jpg"])
    let other = root.appendingPathComponent("other")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    await state.openFolder(other)
    #expect(await state.publishVerified([b], in: root, using: ArrivalMetadata()) == nil)
    #expect(state.filePhotos.isEmpty)
  }
  @Test func publishingPreservesSelectionSessionReviewAndDecisionUndo() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let images = ["a.jpg", "b.jpg", "not-verified.jpg"].map { root.appendingPathComponent($0) }
    for image in images { try Data("image".utf8).write(to: image) }
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db"))
    let state = WorkspaceState(decisionStore: store)
    await state.openFolder(root, verifiedImages: [images[0]])
    await state.loadDecisions()
    state.autoAdvance = false
    state.applyDecision(rating: 4)
    state.reviewSelection()
    let session = state.sessionID
    let chosen = state.selectedID
    await state.publishVerified([images[1], images[1]], in: root, using: ArrivalMetadata())?.value
    #expect(state.sessionID == session)
    #expect(state.selectedID == chosen)
    #expect(state.filePhotos.count == 2)
    #expect(state.photos.count == 1)
    #expect(state.canUndo)
    state.undoDecision()
    #expect(state.decisions[try #require(chosen)]?.rating == 0)
    state.endReview()
    #expect(state.photos.count == 2)
    #expect(state.metadata[PhotoItem(fileURL: images[1]).id]?.iso == 200)
    #expect(state.filePhotos.allSatisfy { $0.filename != "not-verified.jpg" })
  }
  @Test func sortingDuringArrivalDoesNotDropNewItemsOrChangeFocus() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<1000 { try Data().write(to: root.appendingPathComponent("Photo\(index).jpg")) }
    let state = WorkspaceState(
      decisionStore: DecisionStore(databaseURL: root.appendingPathComponent("db")))
    await state.openFolder(root)
    let selected = state.selectedID
    let sorting = Task { await state.setSort(.filename) }
    await Task.yield()
    let added = root.appendingPathComponent("b.jpg")
    try Data().write(to: added)
    await state.publishVerified([added], in: root, using: ArrivalMetadata())?.value
    await sorting.value
    #expect(state.filePhotos.count == 1001)
    #expect(state.selectedID == selected)
    #expect(state.filePhotos.contains { $0.filename == "b.jpg" })
  }
}
