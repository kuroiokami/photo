import Foundation
import Observation
import Testing

@testable import PhotoCore

private final class PresentationChanges: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func record() { lock.withLock { count += 1 } }
}
private struct PresentationMetadata: PhotoMetadataReading {
  func metadata(for file: URL) async throws -> PhotoMetadata {
    var value = PhotoMetadata(pixelWidth: 120, pixelHeight: 80)
    value.iso = 320
    return value
  }
}

@MainActor
struct WorkspacePresentationTests {
  private func observe(_ tile: PhotoThumbnailState) -> PresentationChanges {
    let changes = PresentationChanges()
    withObservationTracking {
      _ = tile.selected
      _ = tile.ready
      _ = tile.decision
      _ = tile.edit
      _ = tile.metadata
      _ = tile.pairedCount
    } onChange: {
      changes.record()
    }
    return changes
  }

  @Test func unrelatedTilesAndReadinessIgnoreOtherDecisionsEditsAndMetadata() async throws {
    let items = (0..<3).map {
      PhotoItem(id: String($0), filename: "Frame\($0).jpg", resourceName: "")
    }
    let state = WorkspaceState(photos: items)
    state.autoAdvance = false
    await state.loadDecisions()
    let untouched = try #require(state.thumbnailState(for: items[2].id))
    let changes = observe(untouched)
    let ready = PresentationChanges()
    withObservationTracking {
      _ = state.decisionSelectionReady
    } onChange: {
      ready.record()
    }
    state.applyDecision(rating: 4, flag: .pick)
    state.editSelection(.clockwise)
    state.select(items[1].id)
    state.applyDecision(flag: .reject)
    #expect(changes.value == 0)
    #expect(ready.value == 0)
    let first = try #require(state.thumbnailState(for: items[0].id))
    #expect(!first.selected && first.ready)
    #expect(first.decision == CullingDecision(rating: 4, flag: .pick))
    #expect(first.edit == PhotoEdit().applying(.clockwise))

    let files = ["a.jpg", "b.jpg"].map {
      PhotoItem(fileURL: URL(fileURLWithPath: "/display/" + $0))
    }
    let metadataState = WorkspaceState(photos: files)
    let a = try #require(metadataState.thumbnailState(for: files[0].id))
    let b = try #require(metadataState.thumbnailState(for: files[1].id))
    let aChanges = observe(a)
    let bChanges = observe(b)
    await metadataState.readMetadata(files[0], using: PresentationMetadata())
    #expect(aChanges.value == 1 && bChanges.value == 0)
    #expect(a.metadata?.iso == 320 && b.metadata == nil)
  }

  @Test func summaryCachesMixedValuesAndObservesUndoWithoutCouplingToReady() async {
    let state = WorkspaceState()
    state.autoAdvance = false
    await state.loadDecisions()
    state.applyDecision(rating: 4, flag: .pick)
    state.selectAllVisible()
    let summary = state.selectionSummary
    #expect(summary.fileCount == 3 && summary.rating == nil && summary.flag == nil)
    let evaluations = state.selectionPresentation.evaluations
    for _ in 0..<1000 { #expect(state.selectionSummary == summary) }
    #expect(state.selectionPresentation.evaluations == evaluations)
    let changes = PresentationChanges()
    let readiness = PresentationChanges()
    withObservationTracking {
      _ = state.selectionSummary
    } onChange: {
      changes.record()
    }
    withObservationTracking {
      _ = state.decisionSelectionReady
    } onChange: {
      readiness.record()
    }
    state.applyDecision(rating: 2)
    #expect(changes.value == 1 && readiness.value == 0)
    #expect(state.selectionSummary.rating == 2 && state.selectionSummary.flag == nil)
    state.undoDecision()
    #expect(state.selectionSummary == summary)
    state.redoDecision()
    #expect(state.selectionSummary.rating == 2)
    state.deselectAll()
    #expect(state.selectionSummary.fileCount == 0 && !state.decisionSelectionReady)
  }

  @Test func unknownFamilyMembersDisableSelectionUntilAllAreLoaded() {
    let raw = PhotoItem(id: "raw", filename: "Frame.ARW", resourceName: "")
    let jpg = PhotoItem(id: "jpeg", filename: "Frame.jpeg", resourceName: "")
    let other = PhotoItem(id: "other", filename: "Other.jpg", resourceName: "")
    let selection = WorkspaceSelectionState()
    selection.replace([raw, jpg], decisions: [:], ready: [raw.id])
    #expect(!selection.ready && selection.summary.fileCount == 2)
    let changes = PresentationChanges()
    withObservationTracking {
      _ = selection.ready
    } onChange: {
      changes.record()
    }
    selection.update(other.id, decision: CullingDecision(rating: 5), ready: true)
    #expect(changes.value == 0 && !selection.ready)
    selection.update(jpg.id, decision: CullingDecision(rating: 3), ready: true)
    #expect(changes.value == 1 && selection.ready)
    #expect(selection.summary.rating == nil)
    selection.replace([raw], decisions: [:], ready: [])
    #expect(!selection.ready && selection.summary.fileCount == 1)
  }

  @Test func selectionReadinessWithManyUnrelatedLoadedFilesPreservesUnknownAndMixedDecisions() {
    let selected = [
      PhotoItem(id: "one", filename: "é1.jpg", resourceName: ""),
      PhotoItem(id: "two", filename: "é2.jpg", resourceName: ""),
    ]
    var ready = Set((0..<40_000).map { "unrelated-\($0)" })
    ready.insert("one")
    let decisions = ["one": CullingDecision(rating: 4, flag: .pick)]
    let selection = WorkspaceSelectionState()
    selection.replace(selected, decisions: decisions, ready: ready)
    #expect(!selection.ready && selection.summary.fileCount == 2)
    #expect(selection.summary.rating == nil && selection.summary.flag == nil)
    ready.insert("two")
    selection.replace(selected, decisions: decisions, ready: ready)
    #expect(selection.ready && selection.summary.fileCount == 2)
    selection.replace([selected[0]], decisions: decisions, ready: ready)
    #expect(selection.ready && selection.summary.rating == 4 && selection.summary.flag == .pick)
    selection.replace([], decisions: decisions, ready: ready)
    #expect(!selection.ready && selection.summary.fileCount == 0)
  }

  @Test func orderingAndFocusRetainSelectionSnapshotUntilMembershipActuallyChanges() async {
    let items = (0..<2000).map {
      PhotoItem(id: "folder/é-\($0)", filename: "Frame\($0).jpg", resourceName: "")
    }
    let state = WorkspaceState(photos: items)
    await state.loadDecisions()
    state.selectAllVisible()
    let original = state.selectionSummary
    let evaluations = state.selectionReadinessEvaluations
    await state.setSort(.rating)
    state.selectGroup(state.selectedIDs, focus: items.last!.id)
    #expect(state.selectionReadinessEvaluations == evaluations)
    #expect(state.selectionSummary == original && state.decisionSelectionReady)
    state.setFilter(.pick, minimumRating: 0)
    #expect(state.selectionSummary.fileCount == 0 && !state.decisionSelectionReady)
    state.setFilter(.all, minimumRating: 0)
    #expect(state.selectionSummary.fileCount == 1 && state.decisionSelectionReady)
  }

  @Test func groupingArrivalsRemovalAndSessionResetKeepDisplayIdentityCorrect() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let raw = root.appendingPathComponent("Frame.ARW")
    let jpeg = root.appendingPathComponent("Frame.jpeg")
    let bytes = Data("disposable source".utf8)
    for file in [raw, jpeg] { try bytes.write(to: file) }
    let state = WorkspaceState(
      decisionStore: DecisionStore(databaseURL: root.appendingPathComponent("db")))
    await state.openFolder(root, verifiedImages: [raw])
    await state.loadDecisions()
    state.autoAdvance = false
    state.setGrouping(true)
    let rawID = PhotoItem(fileURL: raw).id
    let jpegID = PhotoItem(fileURL: jpeg).id
    let original = try #require(state.thumbnailState(for: rawID))
    #expect(original.pairedCount == 1 && original.selected && original.ready)
    await state.publishVerified([jpeg], in: root, using: PresentationMetadata())?.value
    #expect(state.thumbnailState(for: rawID) === original)
    #expect(original.pairedCount == 2)
    #expect(state.selectionSummary.fileCount == 2 && state.decisionSelectionReady)
    state.applyDecision(rating: 3, flag: .pick)
    let companion = try #require(state.thumbnailState(for: jpegID))
    #expect(original.decision == companion.decision && companion.ready)
    state.removeTrashedPhotos([jpeg])
    #expect(state.thumbnailState(for: jpegID) == nil && original.pairedCount == 1)
    #expect(state.selectionSummary.fileCount == 1)
    await DecisionSaveQueue.shared.flush()
    for file in [raw, jpeg] { #expect(try Data(contentsOf: file) == bytes) }
    await state.openFolder(root, verifiedImages: [raw])
    let reopened = try #require(state.thumbnailState(for: rawID))
    #expect(reopened !== original && !reopened.ready)
    await state.loadDecisions()
    #expect(reopened.ready && reopened.decision.rating == 3)
  }

  @Test func filtersRatingSortAndUndoKeepTilesAndSummaryInSync() async throws {
    let state = WorkspaceState()
    state.autoAdvance = false
    await state.loadDecisions()
    let firstID = try #require(state.selectedID)
    state.applyDecision(rating: 4, flag: .pick)
    state.moveSelection(by: 1)
    let secondID = try #require(state.selectedID)
    state.applyDecision(rating: 2, flag: .pick)
    await state.setSort(.rating)
    state.selectGroup([firstID, secondID])
    state.setFilter(.pick, minimumRating: 3)
    #expect(state.selectedIDs == [firstID])
    #expect(state.selectionSummary.rating == 4)
    #expect(state.thumbnailState(for: firstID)?.selected == true)
    #expect(state.thumbnailState(for: secondID)?.selected == false)
    state.applyDecision(flag: .reject)
    #expect(state.photos.isEmpty && state.selectionSummary.fileCount == 0)
    state.undoDecision()
    #expect(state.selectionSummary.rating == 4 && state.selectionSummary.flag == .pick)
    #expect(state.thumbnailState(for: firstID)?.decision.flag == .pick)
    state.redoDecision()
    #expect(state.selectionSummary.fileCount == 0)
  }
}
