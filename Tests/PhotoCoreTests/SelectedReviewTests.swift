import Foundation
import PhotoCore
import Testing

@MainActor
struct SelectedReviewTests {
  @Test func frozenReviewSurvivesNavigationFiltersRatingSortAndUndo() async {
    let state = WorkspaceState()
    state.autoAdvance = false
    await state.loadDecisions()
    let original = state.photos
    state.selectGroup(Set(original.prefix(2).map(\.id)))
    state.reviewSelection()
    #expect(state.photos == Array(original.prefix(2)))
    #expect(state.selectedIDs.count == 1)
    state.moveSelection(by: 1)
    #expect(state.reviewIDs == Set(original.prefix(2).map(\.id)))
    state.applyDecision(rating: 4, flag: .pick)
    await state.setSort(.rating)
    #expect(state.selectedID == original[1].id)
    #expect(state.photos.first?.id == original[1].id)
    state.setFilter(.pick, minimumRating: 0)
    #expect(state.photos.count == 1)
    state.applyDecision(flag: .reject, advance: true)
    #expect(state.photos.isEmpty)
    state.undoDecision()
    #expect(state.selectedID == original[1].id)
    state.setFilter(.all, minimumRating: 0)
    #expect(state.photos.count == 2)
    state.endReview()
    #expect(state.photos.count == 3)
    #expect(state.selectedID == original[1].id)
    state.showSamples()
    #expect(!state.reviewingSelection)
  }
  @Test func groupingIncludesTheFamilyOfAnUngroupedReviewedJPEG() {
    let raw = PhotoItem(fileURL: URL(fileURLWithPath: "/review/Pair.ARW"))
    let jpeg = PhotoItem(fileURL: URL(fileURLWithPath: "/review/Pair.JPG"))
    let other = PhotoItem(fileURL: URL(fileURLWithPath: "/review/Other.JPG"))
    let state = WorkspaceState(photos: [raw, jpeg, other])
    state.select(jpeg.id)
    state.reviewSelection()
    state.setGrouping(true)
    #expect(state.photos.count == 1)
    #expect(Set(state.operationPhotos.map(\.id)) == [raw.id, jpeg.id])
    state.setGrouping(false)
    #expect(state.photos == [jpeg])
    state.endReview()
    #expect(state.photos.count == 3)
  }
}
