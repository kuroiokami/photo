import Foundation
import Observation
import Testing

@testable import PhotoCore

private final class SelectionCostChange: @unchecked Sendable {
  private let lock = NSLock()
  private var changed = false
  var value: Bool { lock.withLock { changed } }
  func mark() { lock.withLock { changed = true } }
}

struct SelectionCostTests {
  @Test func preparedFileIDsPreserveExactUnicodeSpellingAndURLs() {
    for name in ["cafe\u{301}-0001.JPG", "café-0001.JPG", "日本語-📷 001.ORF", "Straße #1%.CR3"] {
      let url = URL(fileURLWithPath: "/tmp/\(name)")
      let path = url.standardizedFileURL.path
      let photo = PhotoItem(fileURL: url)
      #expect(photo.id.utf8.elementsEqual(path.utf8))
      #expect(photo.id == path && photo.fileURL == url)
      #expect(photo.filename.utf8.elementsEqual(url.lastPathComponent.utf8))
      let oldKeys = [path: 42]
      #expect(oldKeys[photo.id] == 42)
      #expect(Set([path]).contains(photo.id))
    }
  }

  @MainActor @Test func largeSelectionDeltasKeepReadinessTilesHistoryAndSnapshotsCorrect() async {
    let photos = (0..<1025).map {
      PhotoItem(id: "cafe\u{301}-\($0)", filename: "Frame\($0).jpg", resourceName: "")
    }
    let state = WorkspaceState(photos: photos)
    state.selectAllVisible()
    #expect(state.selectionSummary.fileCount == photos.count && !state.decisionSelectionReady)
    await state.loadDecisions()
    #expect(state.decisionSelectionReady && state.selectionSummary.rating == 0)
    let oldDecisions = state.decisions
    let oldReady = state.decisionsReady
    let subset = Set(
      photos.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { $0.element.id })
    let untouched = state.thumbnailState(for: photos[0].id)!
    let changed = SelectionCostChange()
    withObservationTracking {
      _ = untouched.selected
    } onChange: {
      changed.mark()
    }
    state.selectGroup(subset, focus: photos[0].id)
    #expect(!changed.value)
    #expect(Set(state.operationPhotos.map(\.id)) == subset)
    #expect(state.selectionSummary.fileCount == subset.count && state.decisionSelectionReady)
    for photo in photos {
      #expect(state.thumbnailState(for: photo.id)?.selected == subset.contains(photo.id))
    }
    let membership = state.selectionReadinessEvaluations
    state.selectGroup(subset, focus: photos[2].id)
    #expect(state.selectionReadinessEvaluations == membership)
    state.applyDecision(rating: 3, flag: .pick, allowAutoAdvance: false)
    #expect(state.selectionSummary.rating == 3 && state.selectionSummary.flag == .pick)
    #expect(oldDecisions.values.allSatisfy { $0 == CullingDecision() })
    #expect(oldReady.count == photos.count)
    state.undoDecision()
    #expect(state.selectionSummary.rating == 0 && state.selectionSummary.flag == .unflagged)
    state.redoDecision()
    #expect(state.selectionSummary.rating == 3 && state.selectionSummary.flag == .pick)
    await DecisionSaveQueue.shared.flush()
    state.invertSelection()
    #expect(state.selectedIDs == Set(photos.map(\.id)).subtracting(subset))
    state.deselectAll()
    #expect(state.operationPhotos.isEmpty && !state.decisionSelectionReady)
    #expect(photos.allSatisfy { state.thumbnailState(for: $0.id)?.selected == false })
  }

  @MainActor @Test func bulkFlagHistoryRetainsRatingOrderAndFilteredNeighborSelection() async {
    let photos = (0..<129).map {
      PhotoItem(id: "日本語-\($0)", filename: "Frame\($0).jpg", resourceName: "")
    }
    let state = WorkspaceState(photos: photos)
    await state.loadDecisions()
    let subset = Set(
      photos.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { $0.element.id })
    state.selectGroup(subset, focus: photos[0].id)
    state.applyDecision(rating: 4)
    await state.setSort(.rating)
    let ordered = state.photos.map(\.id)
    state.selectAllVisible()
    state.applyDecision(flag: .pick)
    #expect(state.photos.map(\.id) == ordered && state.selectedIDs.count == photos.count)
    state.undoDecision()
    #expect(state.photos.map(\.id) == ordered && state.selectionSummary.flag == .unflagged)
    state.redoDecision()
    #expect(state.photos.map(\.id) == ordered && state.selectionSummary.flag == .pick)
    state.setFilter(.pick, minimumRating: 4)
    #expect(Set(state.photos.map(\.id)) == subset && state.selectedIDs == subset)
    state.applyDecision(flag: .reject)
    #expect(state.photos.isEmpty && state.selectedIDs.isEmpty)
    state.undoDecision()
    #expect(Set(state.photos.map(\.id)) == subset && state.selectedID == photos[0].id)
    #expect(state.selectionSummary.rating == 4 && state.selectionSummary.flag == .pick)
    state.redoDecision()
    #expect(state.photos.isEmpty)
    state.setFilter(.all, minimumRating: 0)
    #expect(state.photos.map(\.id) == ordered)
  }

  @MainActor @Test func ungroupedSelectionDoesNotExpandCompanionsAndGroupingStillDeduplicates() {
    let photos = ["Frame.ARW", "Frame.jpeg", "Other.JPG"].map {
      PhotoItem(fileURL: URL(fileURLWithPath: "/selection-cost/" + $0))
    }
    let state = WorkspaceState(photos: photos)
    state.select(photos[0].id)
    #expect(Set(state.operationPhotos.map(\.id)) == [photos[0].id])
    state.setGrouping(true)
    #expect(Set(state.operationPhotos.map(\.id)) == Set(photos.prefix(2).map(\.id)))
    state.selectAllVisible()
    #expect(Set(state.operationPhotos.map(\.id)) == Set(photos.map(\.id)))
    #expect(state.selectionSummary.fileCount == 3)
    state.setGrouping(false)
    #expect(state.operationPhotos.count == state.selectedIDs.count)
    #expect(state.operationPhotos.count == 2)
  }
}
