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
    model.ingest(
      source: root.appendingPathComponent("card").path,
      primary: root.appendingPathComponent("primary").path,
      backup: root.appendingPathComponent("backup").path, job: "Test")
    await model.worker?.value
    #expect(!model.busy)
    #expect(workspace.filePhotos.count == 2)
    #expect(workspace.directory?.lastPathComponent == "DCIM")
    #expect(model.status.hasPrefix("Processed 2 files"))
  }
}
