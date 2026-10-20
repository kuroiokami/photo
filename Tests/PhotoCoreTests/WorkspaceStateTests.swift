import Foundation
import PhotoCore
import Testing

@MainActor
struct WorkspaceStateTests {
  @Test func initialSelectionAndNavigation() {
    let state = WorkspaceState()
    #expect(state.selectedPhoto == SampleLibrary.photos.first)
    state.moveSelection(by: 1)
    #expect(state.selectedPhoto == SampleLibrary.photos[1])
    state.moveSelection(by: Int.max)
    #expect(state.selectedPhoto == SampleLibrary.photos.last)
    state.moveSelection(by: Int.min)
    #expect(state.selectedPhoto == SampleLibrary.photos.first)
  }

  @Test func invalidSelectionDoesNotReplaceValidSelection() {
    let state = WorkspaceState()
    state.select("missing")
    #expect(state.selectedPhoto == SampleLibrary.photos.first)
    state.select(nil)
    #expect(state.selectedPhoto == nil)
    state.select(SampleLibrary.photos[1].id)
    #expect(state.selectedPhoto == SampleLibrary.photos[1])
  }

  @Test func emptyCollectionIsSafe() {
    let state = WorkspaceState(photos: [])
    state.moveSelection(by: 1)
    state.select("missing")
    #expect(state.selectedPhoto == nil)
  }
  @Test func largeCollectionSelectionAndBoundsRemainConsistent() {
    let photos = (0..<10_000).map {
      PhotoItem(fileURL: URL(fileURLWithPath: "/benchmark/Photo\($0).jpg"))
    }
    let state = WorkspaceState(photos: photos)
    state.select(photos[9_999].id)
    #expect(state.selectedIndex == 9_999)
    #expect(state.selectedPhoto == photos[9_999])
    state.moveSelection(by: Int.max)
    #expect(state.selectedIndex == 9_999)
    state.moveSelection(by: Int.min)
    #expect(state.selectedIndex == 0)
    state.select(nil)
    #expect(state.selectedIndex == nil)
    #expect(state.selectedPhoto == nil)
    state.select(photos[5_000].id)
    #expect(state.selectedIndex == 5_000)
    #expect(state.selectedID == photos[5_000].id)
  }

  @Test func rangeAnchorAndKeyboardExtensionAreStable() {
    let state = WorkspaceState()
    let photos = state.photos
    state.select(photos[0].id)
    state.selectMultiple(photos[2].id, extending: false, range: true)
    #expect(state.selectedIDs.count == 3)
    state.moveSelection(by: -1, extending: true)
    #expect(state.selectedIDs == Set(photos.prefix(2).map(\.id)))
    #expect(state.firstSelectedPhoto == photos[0])
    state.selectMultiple(photos[0].id, extending: true, range: false)
    #expect(state.selectedIDs == [photos[1].id])
    state.invertSelection()
    #expect(state.selectedIDs == [photos[0].id, photos[2].id])
    state.deselectAll()
    #expect(state.selectedPhoto == nil)
    state.selectAllVisible()
    #expect(state.selectedIDs.count == 3)
    #expect(state.selectedPhoto == photos[0])
  }
  @Test func togglingGroupFlagsPreservesIndependentStarsAndUndo() async {
    let state = WorkspaceState()
    state.autoAdvance = false
    await state.loadDecisions()
    let photos = state.photos
    state.applyDecision(rating: 4, flag: .pick)
    state.select(photos[1].id)
    state.applyDecision(rating: 2)
    state.selectGroup(Set(photos.prefix(2).map(\.id)))
    #expect(state.decisionSelectionReady)
    state.togglePicks()
    #expect(state.decisions[photos[0].id]?.rating == 4)
    #expect(state.decisions[photos[1].id]?.rating == 2)
    #expect(state.decisions[photos[1].id]?.flag == .pick)
    state.togglePicks()
    #expect(state.decisions[photos[0].id]?.flag == .unflagged)
    state.undoDecision()
    #expect(state.decisions[photos[1].id]?.flag == .pick)
    state.selectPicks()
    #expect(state.selectedIDs == Set(photos.prefix(2).map(\.id)))
  }

}
