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
  @Test func completeReviewedWorkflowRetainsSourceUntilExplicitDestinationNavigation() async throws
  {
    await WorkflowOperationBarrier.shared.flush()
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let card = root.appendingPathComponent("Card")
    try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
    let bytes = try Data(contentsOf: #require(SampleResources.url(for: SampleLibrary.photos[0])))
    let image = card.appendingPathComponent("a.png")
    try bytes.write(to: image)
    try bytes.write(to: card.appendingPathComponent("b.png"))
    let policy = SourceProtection(registryURL: root.appendingPathComponent("Local/sources.json"))
    let store = DecisionStore(
      databaseURL: root.appendingPathComponent("Local/state.sqlite"), sourceProtection: policy)
    let operations = MediaOperations(
      journalDirectory: root.appendingPathComponent("Local/Operations"), sourceProtection: policy)
    _ = try await store.beginSourceReview(card)
    let workspace = WorkspaceState(decisionStore: store)
    await workspace.openFolder(card)
    await workspace.loadDecisions()
    workspace.applyDecision(flag: .unflagged)
    await DecisionSaveQueue.shared.flush()
    #expect(try await store.load(for: image).reviewFields == .flag)
    workspace.applyDecision(rating: 4)
    await DecisionSaveQueue.shared.flush()
    #expect(try await store.load(for: image).reviewFields == .all)
    workspace.undoDecision()
    await DecisionSaveQueue.shared.flush()
    #expect(try await store.load(for: image).reviewFields == .flag)
    workspace.redoDecision()
    workspace.applyDecision(flag: .pick)
    await DecisionSaveQueue.shared.flush()
    let selected = workspace.selectedIDs
    let model = WorkflowModel(workspace: workspace, mediaOperations: operations)
    model.prepareReviewedCopy(
      source: card.path, scope: .picks,
      primary: root.appendingPathComponent("Photos").path,
      backup: root.appendingPathComponent("Backup").path, job: "Test",
      keepPairs: true, acceptMetadataChanges: false)
    await model.worker?.value
    let plan = try #require(model.reviewedCopyPlan)
    #expect(plan.images.count == 1 && plan.sourcePhotoCount == 2)
    model.copyReviewed(plan, includeOpposingPairs: false)
    await model.worker?.value
    #expect(!model.busy && model.reviewMetadataPending == 0)
    #expect(workspace.isSourceReview && workspace.selectedIDs == selected)
    #expect(model.copiedReviewFolder != nil && model.savedReviewCopies.count == 1)
    #expect(model.status.contains("Review metadata is ready on both copies"))
    model.reviewCopiedPhotos()
    await WorkflowOperationBarrier.shared.flush()
    await workspace.loadDecisions()
    #expect(!workspace.isSourceReview && workspace.firstSelectedPhoto?.filename == "a.png")
    #expect(workspace.decisions.values.contains(CullingDecision(rating: 4, flag: .pick)))
    #expect(try await store.sourceReview(for: card) != nil)
    #expect(try Data(contentsOf: image) == bytes)
    #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: image).path))
  }

}
