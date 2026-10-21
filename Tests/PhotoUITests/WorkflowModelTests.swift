import Foundation
import PhotoCore
import PhotoImaging
import Testing

@testable import PhotoUI

@MainActor
struct WorkflowModelTests {
  @Test func completedIngestOpensPublishedImageFolder() async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("card/DCIM"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sample = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    for name in ["a.png", "b.png"] {
      try FileManager.default.copyItem(
        at: sample, to: root.appendingPathComponent("card/DCIM/" + name))
    }
    let workspace = WorkspaceState()
    let model = WorkflowModel(workspace: workspace)
    let previousCopy = root.appendingPathComponent("Previous/Originals")
    model.copiedReviewFolder = previousCopy
    model.handoffFolder = previousCopy
    model.reviewMetadataPending = 1
    model.reviewMetadataPendingImages = [previousCopy.appendingPathComponent("old.png")]
    model.ingest(
      source: root.appendingPathComponent("card").path,
      primary: root.appendingPathComponent("primary").path,
      backup: root.appendingPathComponent("backup").path, job: "Test")
    await model.worker?.value
    #expect(!model.busy)
    #expect(workspace.filePhotos.count == 2)
    #expect(workspace.directory?.lastPathComponent == "DCIM")
    #expect(model.status.hasPrefix("Processed 2 files"))
    #expect(model.copiedReviewFolder == nil)
    #expect(model.reviewMetadataPending == 0 && model.reviewMetadataPendingImages.isEmpty)
    #expect(model.handoffFolder != nil && model.handoffFolder != previousCopy)
  }
  @Test func oneFieldCanBeCopiedToFiftyPhotosWithoutChangingOtherFieldsOrSelection() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sample = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let bytes = try Data(contentsOf: sample)
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db.sqlite"))
    for index in 0..<51 {
      let image = root.appendingPathComponent(String(format: "%03d.png", index))
      try bytes.write(to: image)
      _ = try await store.load(for: image)
      _ = try await store.save(CullingDecision(rating: index % 6), for: image)
      var patch = MetadataPatch()
      patch.fields = [.caption: "Unique caption \(index)", .copyright: "Original \(index)"]
      for plan in try await store.prepareMetadata(patch, images: [image]) {
        _ = try await store.saveMetadata(plan)
      }
    }
    let workspace = WorkspaceState(decisionStore: store)
    await workspace.openFolder(root)
    await workspace.loadDecisions()
    let selected = Set(workspace.photos.prefix(50).map(\.id))
    workspace.selectGroup(selected, focus: workspace.photos[49].id)
    let model = WorkflowModel(workspace: workspace)
    await model.refresh()
    #expect(model.currentMetadata.fields[.caption] == "Unique caption 0")
    model.previewField(.copyright, value: "Shared copyright", clear: false, scope: "Selection")
    await model.worker?.value
    #expect(model.metadataPlan.count == 50)
    #expect(model.metadataPlan.allSatisfy { $0.fields == [.copyright] && !$0.changesKeywords })
    model.applyMetadata()
    await model.worker?.value
    #expect(workspace.selectedIDs == selected)
    #expect(workspace.selectedPhoto?.filename == "049.png")
    #expect(model.metadataResults.values.allSatisfy { $0 == "Saved" })
    #expect(model.metadataUndoCount == 50)
    model.replayMetadata(undo: true)
    await model.worker?.value
    for index in 0..<50 {
      let image = root.appendingPathComponent(String(format: "%03d.png", index))
      #expect(
        try await store.loadMetadata(for: image).value.fields[.copyright] == "Original \(index)")
    }
    model.replayMetadata(undo: false)
    await model.worker?.value
    for index in 0..<51 {
      let image = root.appendingPathComponent(String(format: "%03d.png", index))
      let metadata = try await store.loadMetadata(for: image).value
      #expect(metadata.fields[.caption] == "Unique caption \(index)")
      #expect(metadata.fields[.copyright] == (index < 50 ? "Shared copyright" : "Original 50"))
      #expect(try await store.load(for: image).decision.rating == index % 6)
      #expect(try Data(contentsOf: image) == bytes)
    }
  }

}
