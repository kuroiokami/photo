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
}
