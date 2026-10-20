import CSQLite
import CoreGraphics
import Foundation
import PhotoCore
import Testing

@MainActor
struct PhotoEditTests {
  @Test func orientationCompositionAndCropGeometry() {
    let size = CGSize(width: 600, height: 400)
    for turns in 0..<4 {
      for mirrored in [false, true] {
        let edit = PhotoEdit(quarterTurns: turns, mirrored: mirrored)
        let source = CGPoint(x: 120, y: 120)
        let output = source.applying(edit.transform(size))
        let oriented = edit.orientedSize(size)
        let unit = CGPoint(x: output.x / oriented.width, y: output.y / oriented.height)
        for action in [PhotoEditAction.clockwise, .counterclockwise, .horizontal, .vertical] {
          let changed = edit.applying(action)
          let actual = source.applying(changed.transform(size))
          let newSize = changed.orientedSize(size)
          let expected: CGPoint
          switch action {
          case .clockwise: expected = CGPoint(x: 1 - unit.y, y: unit.x)
          case .counterclockwise: expected = CGPoint(x: unit.y, y: 1 - unit.x)
          case .horizontal: expected = CGPoint(x: 1 - unit.x, y: unit.y)
          default: expected = CGPoint(x: unit.x, y: 1 - unit.y)
          }
          #expect(abs(actual.x / newSize.width - expected.x) < 0.000001)
          #expect(abs(actual.y / newSize.height - expected.y) < 0.000001)
        }
        let crop = PhotoCrop(x: 0.2, y: 0.1, width: 0.4, height: 0.5)
        let cropped = PhotoEdit(quarterTurns: turns, mirrored: mirrored, crop: crop)
        #expect(cropped.cropBounds(size).size.width > 0)
        let point = cropped.originalPoint(CGPoint(x: 0.5, y: 0.5), original: size)
        let restored = CGPoint(x: point.x * size.width, y: point.y * size.height).applying(
          cropped.transform(size))
        #expect(abs(restored.x - cropped.cropBounds(size).width / 2) < 0.000001)
        #expect(cropped.applying(.clockwise).applying(.counterclockwise).crop == cropped.crop)
      }
    }
    let safe = PhotoCrop(x: .nan, y: 2, width: -.infinity, height: -1)
    #expect(safe.x == 0 && safe.y == 0.99 && safe.width > 0 && safe.height > 0)
    #expect(PhotoEdit(quarterTurns: -1).turns == 3)
  }
  @Test func imageEditsPersistIndependentlyAndDoNotTransferToReplacements() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("image.jpg")
    let second = root.appendingPathComponent("second.jpg")
    try Data("original".utf8).write(to: file)
    try Data("second".utf8).write(to: second)
    let db = root.appendingPathComponent("state.sqlite")
    let store = DecisionStore(databaseURL: db)
    let firstIdentity = try #require(try await store.load(for: file).identity)
    let secondIdentity = try #require(try await store.load(for: second).identity)
    let edit = PhotoEdit(
      quarterTurns: 1, mirrored: true, crop: PhotoCrop(x: 0.1, y: 0.2, width: 0.4, height: 0.5))
    try await store.saveImageEdits([
      ImageEditWrite(image: file, identity: firstIdentity, edit: edit)
    ])
    #expect(try await DecisionStore(databaseURL: db).loadImageEdit(for: file) == edit)
    #expect(try Data(contentsOf: file) == Data("original".utf8))
    #expect(!FileManager.default.fileExists(atPath: file.path + ".xmp"))
    try FileManager.default.removeItem(at: second)
    try Data("replacement data".utf8).write(to: second)
    await #expect(throws: (any Error).self) {
      try await store.saveImageEdits([
        ImageEditWrite(image: file, identity: firstIdentity, edit: PhotoEdit()),
        ImageEditWrite(image: second, identity: secondIdentity, edit: edit),
      ])
    }
    #expect(try await store.loadImageEdit(for: file) == edit)
    #expect(try await store.loadImageEdit(for: second) == PhotoEdit())
  }
  @Test func directTileDecisionsAndImageEditsShareOrderedUndoWithoutAdvancing() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["a.jpg", "b.jpg", "c.jpg"] {
      try Data(name.utf8).write(to: root.appendingPathComponent(name))
    }
    let workspace = WorkspaceState(
      decisionStore: DecisionStore(databaseURL: root.appendingPathComponent("db.sqlite")))
    await workspace.openFolder(root)
    await workspace.loadDecisions()
    workspace.autoAdvance = true
    defer { workspace.autoAdvance = false }
    let items = workspace.photos
    workspace.selectGroup(Set(items.prefix(2).map(\.id)), focus: items[1].id)
    workspace.applyThumbnailDecision(to: items[0].id, rating: 3)
    #expect(workspace.selectedID == items[1].id && workspace.selectedIDs.count == 2)
    workspace.editSelection(.clockwise)
    #expect(workspace.undoTitle == "Image Edit")
    workspace.undoDecision()
    #expect(
      items.prefix(2).allSatisfy {
        workspace.imageEdits[$0.id] == PhotoEdit() && workspace.decisions[$0.id]?.rating == 3
      })
    workspace.undoDecision()
    #expect(items.prefix(2).allSatisfy { workspace.decisions[$0.id]?.rating == 0 })
    workspace.redoDecision()
    workspace.redoDecision()
    #expect(items.prefix(2).allSatisfy { workspace.imageEdits[$0.id]?.turns == 1 })
    workspace.applyThumbnailDecision(to: items[2].id, flag: .reject)
    #expect(workspace.selectedID == items[2].id && workspace.selectedIDs.count == 1)
    #expect(workspace.decisions[items[2].id]?.flag == .reject)
    await DecisionSaveQueue.shared.flush()
    #expect(workspace.editStatus == "Image edits saved in Photo")
  }
  @Test func aDamagedEditRecordDoesNotHideExistingStarsOrFlags() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("image.jpg")
    try Data("pixels".utf8).write(to: image)
    let database = root.appendingPathComponent("state.sqlite")
    let store = DecisionStore(databaseURL: database)
    _ = try await store.save(CullingDecision(rating: 4, flag: .pick), for: image)
    let entry = try await store.load(for: image)
    let identity = try #require(entry.identity)
    try await store.saveImageEdits([
      ImageEditWrite(image: image, identity: identity, edit: PhotoEdit(quarterTurns: 1))
    ])
    var handle: OpaquePointer?
    #expect(sqlite3_open(database.path, &handle) == SQLITE_OK)
    let connection = try #require(handle)
    defer { sqlite3_close(connection) }
    #expect(
      sqlite3_exec(connection, "UPDATE image_edits SET payload=X'00'", nil, nil, nil) == SQLITE_OK)
    let (loaded, edit) = try await store.loadImageState(for: image)
    #expect(loaded.decision == CullingDecision(rating: 4, flag: .pick))
    #expect(loaded.status.contains("image edits unavailable"))
    #expect(edit == PhotoEdit())
  }

  @Test func cropPasteClearResetAndReloadPreservePerFileStateAcrossGroupedPairs() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["a.ARW", "a.JPG", "b.jpg", "c.png"] {
      try Data(name.utf8).write(to: root.appendingPathComponent(name))
    }
    let workspace = WorkspaceState(
      decisionStore: DecisionStore(databaseURL: root.appendingPathComponent("db.sqlite")))
    await workspace.openFolder(root)
    await workspace.loadDecisions()
    let raw = try #require(workspace.filePhotos.first { $0.filename == "a.ARW" })
    let jpeg = try #require(workspace.filePhotos.first { $0.filename == "a.JPG" })
    let other = try #require(workspace.filePhotos.first { $0.filename == "b.jpg" })
    let excluded = try #require(workspace.filePhotos.first { $0.filename == "c.png" })
    workspace.applyThumbnailDecision(to: raw.id, rating: 4, flag: .pick)
    workspace.applyThumbnailDecision(to: other.id, rating: 2, flag: .reject)
    let decisions = workspace.decisions
    workspace.setGrouping(true)
    workspace.select(raw.id)
    workspace.editSelection(.horizontal)
    let firstCrop = PhotoCrop(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
    workspace.setCrop(firstCrop, for: raw)
    workspace.select(other.id)
    workspace.editSelection(.clockwise)
    workspace.selectGroup([raw.id, other.id], focus: raw.id)
    let pasted = PhotoCrop(x: 0.2, y: 0.3, width: 0.4, height: 0.4)
    workspace.pasteCrop(pasted)
    for photo in [raw, jpeg] {
      #expect(workspace.imageEdits[photo.id]?.mirrored == true)
      #expect(workspace.imageEdits[photo.id]?.crop == pasted)
    }
    #expect(workspace.imageEdits[other.id]?.turns == 1)
    #expect(workspace.imageEdits[excluded.id] == PhotoEdit())
    workspace.undoDecision()
    #expect(
      workspace.imageEdits[raw.id]?.crop == firstCrop
        && workspace.imageEdits[jpeg.id]?.crop == firstCrop)
    #expect(workspace.imageEdits[other.id]?.crop == nil)
    workspace.redoDecision()
    workspace.editSelection(.clearCrop)
    #expect(
      workspace.imageEdits[raw.id]?.crop == nil && workspace.imageEdits[other.id]?.crop == nil)
    workspace.undoDecision()
    workspace.editSelection(.reset)
    #expect([raw, jpeg, other].allSatisfy { workspace.imageEdits[$0.id] == PhotoEdit() })
    workspace.undoDecision()
    #expect(workspace.decisions == decisions)
    let edits = workspace.imageEdits
    await DecisionSaveQueue.shared.flush()
    await workspace.openFolder(root)
    await workspace.loadDecisions()
    #expect(!workspace.canUndo && workspace.imageEdits == edits)
    #expect(workspace.decisions == decisions)
    for name in ["a.ARW", "a.JPG", "b.jpg", "c.png"] {
      #expect(try Data(contentsOf: root.appendingPathComponent(name)) == Data(name.utf8))
    }
  }

}
