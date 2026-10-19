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

}
