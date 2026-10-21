import Foundation
import Testing

@testable import PhotoCore

private struct TrashFixture: Sendable {
  let root: URL
  let folder: URL
  let trash: URL
  let store: DecisionStore
  init() throws {
    root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
      UUID().uuidString)
    folder = root.appendingPathComponent("Photos")
    trash = root.appendingPathComponent("RecoverableTrash")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    store = DecisionStore(
      databaseURL: root.appendingPathComponent("Local/local.sqlite"),
      sourceProtection: SourceProtection(registryURL: root.appendingPathComponent("protected.json"))
    )
  }
  func file(_ name: String) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data(name.utf8).write(to: url)
    return url
  }
  func engine() -> PhotoTrash {
    PhotoTrash(store: store) { url in
      try FileManager.default.moveItem(
        at: url, to: trash.appendingPathComponent(url.lastPathComponent))
    }
  }
  func identities(_ urls: [URL]) async throws -> [URL: String] {
    var values: [URL: String] = [:]
    for url in urls { values[url] = try await store.key(for: url) }
    return values
  }
}

struct PhotoTrashTests {
  @Test func movesOnlyExplicitPhotosAndExclusiveCompanionsWithBytesRecoverable() async throws {
    let f = try TrashFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let raw = try f.file("A.ARW")
    let jpeg = try f.file("B.jpg")
    let companions = try ["A.xmp", "A.ACR", "B.jpg.xmp"].map(f.file)
    let keeper = try f.file("Keeper.jpg")
    let keeperSidecar = try f.file("Keeper.jpg.xmp")
    let engine = f.engine()
    let plan = try await engine.prepare(images: f.identities([raw, jpeg]), folder: f.folder)
    #expect(
      Set(plan.companions.map(PhotoPath.canonical)) == Set(companions.map(PhotoPath.canonical)))
    let result = await engine.execute(plan)
    #expect(result.error == nil)
    #expect(
      Set(result.moved.map(PhotoPath.canonical))
        == Set(([raw, jpeg] + companions).map(PhotoPath.canonical)))
    for file in result.moved {
      #expect(!FileManager.default.fileExists(atPath: file.path))
      #expect(
        try Data(contentsOf: f.trash.appendingPathComponent(file.lastPathComponent))
          == Data(file.lastPathComponent.utf8))
    }
    #expect(try Data(contentsOf: keeper) == Data("Keeper.jpg".utf8))
    #expect(try Data(contentsOf: keeperSidecar) == Data("Keeper.jpg.xmp".utf8))
  }

  @Test func foreignFoldersAndSymbolicLinksCannotExpandTheTrashScope() async throws {
    let f = try TrashFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let outside = f.root.appendingPathComponent("Outside.jpg")
    try Data("not selected".utf8).write(to: outside)
    let engine = f.engine()
    let ids = try await f.identities([outside])
    await #expect(throws: (any Error).self) {
      try await engine.prepare(images: ids, folder: f.folder)
    }
    let link = f.folder.appendingPathComponent("Alias.jpg")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    await #expect(throws: (any Error).self) {
      try await engine.prepare(images: [link: "untrusted link"], folder: f.folder)
    }
    #expect(try Data(contentsOf: outside) == Data("not selected".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.trash.path).isEmpty)
  }

  @Test func sharedSidecarsStayWithUnselectedRawOwners() async throws {
    let f = try TrashFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let raw = try f.file("A.ARW")
    let peer = try f.file("A.CR3")
    let xmp = try f.file("A.xmp")
    let acr = try f.file("A.acr")
    let engine = f.engine()
    let plan = try await engine.prepare(images: f.identities([raw]), folder: f.folder)
    #expect(plan.companions.isEmpty)
    #expect(plan.retainedSharedCompanions == 2)
    let result = await engine.execute(plan)
    #expect(result.error == nil)
    #expect(result.moved == [raw])
    for file in [peer, xmp, acr] { #expect(FileManager.default.fileExists(atPath: file.path)) }
  }

  @Test func staleImagesSidecarsAndArrivalsStopBeforeMovingAnything() async throws {
    for scenario in 0..<3 {
      let f = try TrashFixture()
      defer { try? FileManager.default.removeItem(at: f.root) }
      let image = try f.file("A.jpg")
      let sidecar = try f.file("A.jpg.xmp")
      let engine = f.engine()
      let plan = try await engine.prepare(images: f.identities([image]), folder: f.folder)
      if scenario == 0 { try Data("external metadata".utf8).write(to: sidecar) }
      if scenario == 1 {
        try FileManager.default.moveItem(at: image, to: f.root.appendingPathComponent("old.jpg"))
        _ = try f.file("A.jpg")
      }
      if scenario == 2 { _ = try f.file("New.jpg") }
      let result = await engine.execute(plan)
      #expect(result.moved.isEmpty)
      #expect(result.error != nil)
      #expect(FileManager.default.fileExists(atPath: image.path))
      #expect(FileManager.default.fileExists(atPath: sidecar.path))
    }
  }

  @Test func sourceProtectionActivatingAfterConfirmationPreparationBlocksTrash() async throws {
    let f = try TrashFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let image = try f.file("A.jpg")
    let ids = try await f.identities([image])
    let engine = f.engine()
    let plan = try await engine.prepare(images: ids, folder: f.folder)
    _ = try await f.store.beginSourceReview(f.folder)
    let result = await engine.execute(plan)
    #expect(result.moved.isEmpty)
    #expect(result.error != nil)
    await #expect(throws: SourceReviewError.self) {
      try await engine.prepare(images: ids, folder: f.folder)
    }
    #expect(try Data(contentsOf: image) == Data("A.jpg".utf8))
  }

  @Test func partialFailureReportsActualMovesAndLeavesRemainingFiles() async throws {
    let f = try TrashFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let a = try f.file("A.jpg")
    let b = try f.file("B.jpg")
    let sidecar = try f.file("A.jpg.xmp")
    let engine = PhotoTrash(store: f.store) { url in
      if url == b { throw CocoaError(.fileWriteNoPermission) }
      try FileManager.default.moveItem(
        at: url, to: f.trash.appendingPathComponent(url.lastPathComponent))
    }
    let plan = try await engine.prepare(images: f.identities([a, b]), folder: f.folder)
    let result = await engine.execute(plan)
    #expect(result.moved == [a])
    #expect(result.error != nil)
    #expect(FileManager.default.fileExists(atPath: b.path))
    #expect(FileManager.default.fileExists(atPath: sidecar.path))
    #expect(try Data(contentsOf: f.trash.appendingPathComponent("A.jpg")) == Data("A.jpg".utf8))
  }

  @Test func arrivalDuringMovesPreservesSidecarsForNewPhotos() async throws {
    let f = try TrashFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let raw = try f.file("A.ARW")
    let sidecar = try f.file("A.xmp")
    let engine = PhotoTrash(store: f.store) { url in
      try FileManager.default.moveItem(
        at: url, to: f.trash.appendingPathComponent(url.lastPathComponent))
      _ = try f.file("A.CR3")
    }
    let plan = try await engine.prepare(images: f.identities([raw]), folder: f.folder)
    let result = await engine.execute(plan)
    #expect(result.moved == [raw])
    #expect(result.error != nil)
    #expect(FileManager.default.fileExists(atPath: sidecar.path))
  }
}

@MainActor
struct TrashWorkspaceTests {
  @Test func rejectSelectionAndTrashKeepOtherDecisionsReviewMembershipAndSession() async throws {
    let f = try TrashFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    _ = try f.file("A.jpg")
    _ = try f.file("B.jpg")
    _ = try f.file("C.jpg")
    let state = WorkspaceState(decisionStore: f.store)
    await state.openFolder(f.folder)
    await state.loadDecisions()
    let session = state.sessionID
    let aID = try #require(state.filePhotos.first { $0.filename == "A.jpg" }?.id)
    let bID = try #require(state.filePhotos.first { $0.filename == "B.jpg" }?.id)
    let cID = try #require(state.filePhotos.first { $0.filename == "C.jpg" }?.id)
    state.select(aID)
    state.applyDecision(rating: 5, flag: .pick, allowAutoAdvance: false)
    state.select(bID)
    state.applyDecision(rating: 4, flag: .reject, allowAutoAdvance: false)
    state.selectRejects()
    #expect(state.operationPhotos.map(\.filename) == ["B.jpg"])
    state.selectAllVisible()
    state.reviewSelection()
    #expect(state.reviewIDs?.count == 3)
    #expect(state.selectedIDs.count == 1)
    state.selectGroup(
      Set([bID, cID]), focus: cID)
    await DecisionSaveQueue.shared.flush()
    let engine = f.engine()
    let plan = try await engine.prepare(images: state.selectedFileIdentities, folder: f.folder)
    let result = await engine.execute(plan)
    #expect(result.error == nil)
    state.removeTrashedPhotos(result.moved)
    #expect(state.sessionID == session)
    #expect(state.photos.map(\.filename) == ["A.jpg"])
    #expect(state.selectedPhoto?.id == aID)
    #expect(state.reviewIDs == [aID])
    #expect(state.decisions[aID] == CullingDecision(rating: 5, flag: .pick))
    #expect(!state.decisionsReady.contains(bID))
    #expect(!state.canUndo)
  }
}
