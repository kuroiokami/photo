import Foundation
import PhotoCore
import PhotoImaging
import Testing

@testable import PhotoUI

private actor WorkflowReviewGate {
  private var opened = false
  private var continuation: CheckedContinuation<Void, Never>?
  func wait() async {
    if opened { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func release() {
    opened = true
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
struct SourceReviewWorkflowTests {
  @Test func reviewEntryProtectsBeforeDrainingQueuedNormalSavesAndOpensTheSource() async throws {
    await WorkflowOperationBarrier.shared.flush()
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Card")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let image = source.appendingPathComponent("frame.jpg")
    let original = Data("fixture".utf8)
    try original.write(to: image)
    let policy = SourceProtection(registryURL: root.appendingPathComponent("Local/protection.json"))
    let store = DecisionStore(
      databaseURL: root.appendingPathComponent("Local/state.sqlite"), sourceProtection: policy)
    let workspace = WorkspaceState(decisionStore: store)
    let model = WorkflowModel(workspace: workspace)
    _ = try await store.load(for: image)
    // Other workflow tests run concurrently; finish their file operations before
    // enqueueing our intentionally suspended decision save (no barrier cycle).
    await WorkflowOperationBarrier.shared.flush()
    let gate = WorkflowReviewGate()
    var blocked = false
    DecisionSaveQueue.shared.enqueue {
      await gate.wait()
      do {
        _ = try await store.save(CullingDecision(rating: 5), for: image)
      } catch SourceReviewError.protectedSource { blocked = true } catch { Issue.record(error) }
    }
    model.startSourceReview(source: source.path)
    var protected = false
    for _ in 0..<100 {
      if try await store.sourceReview(for: source) != nil {
        protected = true
        break
      }
      await Task.yield()
    }
    await gate.release()
    await model.worker?.value
    #expect(protected && blocked)
    await WorkflowOperationBarrier.shared.flush()
    #expect(model.sourceReviewLaunch != nil && !model.busy)
    #expect(workspace.isSourceReview && workspace.directory?.path == source.path)
    await workspace.loadDecisions()
    workspace.applyDecision(rating: 3, flag: .pick)
    await DecisionSaveQueue.shared.flush()
    #expect(workspace.saveStatus.values.allSatisfy { $0 == "Review saved on this Mac" })
    #expect(try Data(contentsOf: image) == original)
    #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: image).path))
  }
  @Test func derivedMetadataWriterCannotWriteInsideAProtectedSource() async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Card")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let image = source.appendingPathComponent("frame.jpg")
    try Data("fixture".utf8).write(to: image)
    let policy = SourceProtection(registryURL: root.appendingPathComponent("Local/protection.json"))
    _ = try policy.protect(source)
    let writer = HandoffMetadataWriter(sourceProtection: policy)
    await #expect(throws: SourceReviewError.protectedSource) {
      _ = try await writer.embed(in: image, sidecar: XMPSidecar.url(for: image))
    }
    #expect(try Data(contentsOf: image) == Data("fixture".utf8))
  }
}
