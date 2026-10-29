import Foundation
import Testing

@testable import PhotoCore

private actor CollectionSortGate {
  private var first = true
  private var paused = false
  private var waiting: CheckedContinuation<Void, Never>?
  private var release: CheckedContinuation<Void, Never>?
  private(set) var attempts = 0
  func pauseFirst() async {
    attempts += 1
    guard first else { return }
    first = false
    await withCheckedContinuation { continuation in
      release = continuation
      paused = true
      waiting?.resume()
      waiting = nil
    }
  }
  func waitUntilPaused() async {
    if paused { return }
    await withCheckedContinuation { waiting = $0 }
  }
  func resume() {
    release?.resume()
    release = nil
  }
}
private struct CollectionISO: PhotoMetadataReading {
  let iso: Double
  func metadata(for file: URL) async throws -> PhotoMetadata {
    var result = PhotoMetadata(pixelWidth: 120, pixelHeight: 80)
    result.iso = iso
    return result
  }
}

@MainActor
struct CollectionUpdateTests {
  private func samples() -> [PhotoItem] {
    (0..<4).map { PhotoItem(id: "\($0)", filename: "Frame\($0).jpg", resourceName: "") }
  }
  @Test func filterChangedDuringSortCannotBeOverwrittenByPreparedMembership() async {
    let items = samples()
    let state = WorkspaceState(photos: items)
    await state.loadDecisions()
    state.select(items[1].id)
    state.applyDecision(rating: 4, flag: .pick, allowAutoAdvance: false)
    let gate = CollectionSortGate()
    state.setSortPreparationProbe { await gate.pauseFirst() }
    let sorting = Task { await state.setSort(.rating) }
    await gate.waitUntilPaused()
    state.setFilter(.pick, minimumRating: 3)
    state.select(items[1].id)
    await gate.resume()
    await sorting.value
    #expect(state.photos.map(\.id) == [items[1].id])
    #expect(state.selectedID == items[1].id && state.selectedIDs == [items[1].id])
    #expect(state.selectionSummary.rating == 4 && state.decisionSelectionReady)
    state.setFilter(.all, minimumRating: 0)
    #expect(state.photos.count == 4 && state.photos.first?.id == items[1].id)
    for item in items {
      state.select(item.id)
      #expect(state.selectedID == item.id)
    }
    await DecisionSaveQueue.shared.flush()
  }

  @Test func newerSameSortRequestWinsWithoutRestartingTheOlderRequest() async {
    let items = samples()
    let state = WorkspaceState(photos: items)
    await state.loadDecisions()
    let gate = CollectionSortGate()
    state.setSortPreparationProbe { await gate.pauseFirst() }
    let older = Task { await state.setSort(.rating) }
    await gate.waitUntilPaused()
    state.select(items[2].id)
    state.applyDecision(rating: 5, allowAutoAdvance: false)
    await state.setSort(.rating)
    #expect(state.photos.first?.id == items[2].id)
    await gate.resume()
    await older.value
    #expect(await gate.attempts == 2)
    #expect(state.photos.first?.id == items[2].id && state.selectedID == items[2].id)
    await DecisionSaveQueue.shared.flush()
  }

  @Test func metadataArrivingDuringPreparationReordersUsingTheNewValue() async {
    let items = (0..<3).map {
      PhotoItem(fileURL: URL(fileURLWithPath: "/collection-café/Frame\($0).jpg"))
    }
    let state = WorkspaceState(photos: items)
    await state.readMetadata(items[0], using: CollectionISO(iso: 800))
    await state.readMetadata(items[1], using: CollectionISO(iso: 400))
    let gate = CollectionSortGate()
    state.setSortPreparationProbe { await gate.pauseFirst() }
    let sorting = Task { await state.setSort(.iso) }
    await gate.waitUntilPaused()
    await state.readMetadata(items[2], using: CollectionISO(iso: 100))
    state.select(items[1].id)
    await gate.resume()
    await sorting.value
    #expect(state.photos.map(\.id) == [items[2].id, items[1].id, items[0].id])
    #expect(state.selectedID == items[1].id)
    #expect(await gate.attempts == 2)
  }

  @Test func cancelledSortDoesNotPublishAndTheNextRequestStillWorks() async {
    let state = WorkspaceState(photos: samples())
    let original = state.photos
    let gate = CollectionSortGate()
    state.setSortPreparationProbe { await gate.pauseFirst() }
    let sorting = Task { await state.setSort(.rating) }
    await gate.waitUntilPaused()
    sorting.cancel()
    await gate.resume()
    await sorting.value
    #expect(state.photos == original)
    state.setSortPreparationProbe(nil)
    await state.setSort(.filename)
    #expect(state.photos == original)
    for item in state.photos {
      state.select(item.id)
      #expect(state.selectedPhoto == item)
    }
  }

  @Test func decisionIndexFinishesRatingOrderThroughTheBackgroundPreparationLane() async {
    let items = samples()
    let state = WorkspaceState(photos: items)
    await state.setSort(.rating)
    let gate = CollectionSortGate()
    state.setSortPreparationProbe { await gate.pauseFirst() }
    let loading = Task { await state.loadDecisions() }
    await gate.waitUntilPaused()
    #expect(!state.decisionsLoading && state.decisionSelectionReady)
    state.select(items[2].id)
    await gate.resume()
    await loading.value
    #expect(state.selectedID == items[2].id && state.photos == items)
    #expect(state.decisionsReady.count == items.count)
  }

  @Test func oldSessionSortCannotRestoreItsInventoryOrIndex() async {
    let state = WorkspaceState(photos: samples())
    let gate = CollectionSortGate()
    state.setSortPreparationProbe { await gate.pauseFirst() }
    let sorting = Task { await state.setSort(.filename) }
    await gate.waitUntilPaused()
    state.showSamples()
    let session = state.sessionID
    let ids = state.photos.map(\.id)
    await gate.resume()
    await sorting.value
    #expect(state.sessionID == session && state.photos.map(\.id) == ids)
    for item in state.photos {
      state.select(item.id)
      #expect(state.selectedID == item.id)
    }
  }

  @Test func ratingRepositionAndUndoInvalidateTheReusableUnfilteredIndex() async {
    let items = samples()
    let state = WorkspaceState(photos: items)
    await state.loadDecisions()
    state.select(items[1].id)
    state.applyDecision(rating: 2, allowAutoAdvance: false)
    await state.setSort(.rating)
    #expect(state.photos.first?.id == items[1].id)
    state.select(items[3].id)
    state.applyDecision(rating: 5, allowAutoAdvance: false)
    #expect(state.photos.first?.id == items[3].id)
    state.setFilter(.reject, minimumRating: 0)
    #expect(state.photos.isEmpty && state.selectedID == nil)
    state.setFilter(.all, minimumRating: 0)
    for item in items {
      state.select(item.id)
      #expect(state.selectedPhoto == item)
    }
    state.undoDecision()
    #expect(state.photos.first?.id == items[1].id)
    state.redoDecision()
    #expect(state.photos.first?.id == items[3].id)
    for item in items {
      state.select(item.id)
      #expect(state.selectedPhoto == item)
    }
    await DecisionSaveQueue.shared.flush()
  }

  @Test func groupedReviewKeepsACompanionOnlySelectionThroughBackgroundOrdering() async {
    let items = ["Frame.ARW", "Frame.jpeg", "Other.JPG"].map {
      PhotoItem(fileURL: URL(fileURLWithPath: "/collection-café/" + $0))
    }
    let state = WorkspaceState(photos: items)
    state.select(items[1].id)
    state.reviewSelection()
    let gate = CollectionSortGate()
    state.setSortPreparationProbe { await gate.pauseFirst() }
    let sorting = Task { await state.setSort(.filename) }
    await gate.waitUntilPaused()
    state.setGrouping(true)
    await gate.resume()
    await sorting.value
    #expect(state.photos.count == 1)
    #expect(Set(state.operationPhotos.map(\.id)) == Set(items.prefix(2).map(\.id)))
    state.endReview()
    #expect(state.photos.count == 2)
    state.setGrouping(false)
    #expect(state.photos.count == 3)
    for item in items {
      state.select(item.id)
      #expect(state.selectedPhoto == item)
    }
  }
}
