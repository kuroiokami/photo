import CoreGraphics
import Testing

@testable import PhotoUI

@MainActor
struct SelectionMarqueeTests {
  @Test func scrollingReplacesHitTargetsAndClipsOverscanToViewport() {
    let geometry = PhotoTileGeometry()
    let viewport = CGSize(width: 300, height: 200)
    geometry.replace(with: [
      "visible": CGRect(x: 10, y: 20, width: 80, height: 80),
      "overscan": CGRect(x: 10, y: 230, width: 80, height: 80),
    ])
    let drag = CGRect(x: 0, y: 0, width: 100, height: 350)
    #expect(geometry.hits(in: drag, viewportSize: viewport) == ["visible"])
    // A scroll publishes current viewport positions; removed lazy cells must
    // not remain selectable through stale geometry.
    geometry.replace(with: ["next": CGRect(x: 10, y: 30, width: 80, height: 80)])
    #expect(geometry.hits(in: drag, viewportSize: viewport) == ["next"])
    geometry.clear()
    #expect(geometry.hits(in: drag, viewportSize: viewport).isEmpty)
  }

  @Test func draggingOutsideViewportCannotSelectOnlyTheHiddenPartOfATile() {
    let geometry = PhotoTileGeometry()
    geometry.replace(with: ["partial": CGRect(x: 10, y: -40, width: 80, height: 80)])
    let viewport = CGSize(width: 300, height: 200)
    #expect(
      geometry.hits(in: CGRect(x: 0, y: -35, width: 100, height: 20), viewportSize: viewport)
        .isEmpty)
    #expect(
      geometry.hits(in: CGRect(x: 0, y: 0, width: 100, height: 20), viewportSize: viewport) == [
        "partial"
      ])
  }

  @Test func marqueeDirectionAndSelectionBaseStayIndependentOfScrolling() {
    let geometry = PhotoTileGeometry()
    geometry.replace(with: [
      "partial": CGRect(x: 10, y: -20, width: 80, height: 80),
      "outside": CGRect(x: 110, y: 10, width: 80, height: 80),
    ])
    let drag = SelectionMarquee(
      start: CGPoint(x: 90, y: 60), end: .zero, base: ["existing"])
    let hits = geometry.hits(in: drag.rectangle, viewportSize: CGSize(width: 300, height: 200))
    #expect(hits == ["partial"])
    #expect(drag.base.union(hits) == ["existing", "partial"])
  }
}
