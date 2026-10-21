import AppKit
import PhotoCore
import Testing

@testable import PhotoUI

@MainActor
struct ComparisonTests {
  @Test func keyboardInspectionTogglesWithoutComparisonAndRoutesLinkedPanes() {
    let session = ComparisonSession()
    session.toggleInspection()
    #expect(!session.enabled)
    #expect(session.request(for: .active)?.action == .zoom(CGPoint(x: 0.5, y: 0.5)))
    session.zoom(true, center: CGPoint(x: 0.2, y: 0.8), from: .active)
    session.toggleInspection()
    #expect(session.request(for: .active)?.action == .fit)
    session.toggleInspection()
    #expect(session.request(for: .active)?.action == .zoom(CGPoint(x: 0.2, y: 0.8)))
    session.pin(SampleLibrary.photos[0])
    session.toggleInspection()
    #expect(session.request(for: .reference)?.action == session.request(for: .active)?.action)
    session.setLinked(false)
    let reference = session.request(for: .reference)
    session.toggleInspection()
    #expect(session.request(for: .active)?.action == .fit)
    #expect(session.request(for: .reference) == reference)
  }

  @Test func linkedCommandsRouteOnceAndUnlinkedViewsRemainIndependent() {
    let session = ComparisonSession()
    session.pin(SampleLibrary.photos[0])
    let active = session.request(for: .active)
    session.zoom(true, center: CGPoint(x: 0.2, y: 0.8), from: .active)
    #expect(session.request(for: .active) == active)
    #expect(session.request(for: .reference)?.action == .zoom(CGPoint(x: 0.2, y: 0.8)))
    let reference = session.request(for: .reference)
    session.pan(CGPoint(x: 0.3, y: 0.6), from: .reference)
    #expect(session.request(for: .reference) == reference)
    #expect(session.request(for: .active)?.action == .pan(CGPoint(x: 0.3, y: 0.6)))
    session.setLinked(false)
    let unchanged = session.request(for: .reference)
    session.pan(CGPoint(x: 0.9, y: 0.1), from: .active)
    #expect(session.request(for: .reference) == unchanged)
    session.setLinked(true)
    #expect(session.request(for: .reference)?.action == .zoom(CGPoint(x: 0.9, y: 0.1)))
    session.close()
    #expect(!session.enabled)
    #expect(session.request(for: .active)?.action == .fit)
  }
  @Test func selectionAndRepinningClearZoomAndOldCommands() {
    let session = ComparisonSession()
    session.pin(SampleLibrary.photos[0])
    session.zoom(true, center: CGPoint(x: 1, y: 1), from: .reference)
    session.resetViewports()
    #expect(session.request(for: .active)?.action == .fit)
    #expect(session.request(for: .reference)?.action == .fit)
    session.pin(SampleLibrary.photos[1])
    #expect(session.reference == SampleLibrary.photos[1])
    session.pan(CGPoint(x: Double.nan, y: 2), from: .active)
    #expect(session.request(for: .reference)?.action == .pan(CGPoint(x: 0.5, y: 1)))
    let previous = session.request(for: .reference)
    session.pan(CGPoint(x: 0.5, y: 1), from: .active)
    #expect(session.request(for: .reference)?.id != previous?.id)
  }
  @Test func programmaticClampingDoesNotEchoAsUserPanning() throws {
    let context = try #require(
      CGContext(
        data: nil, width: 1200, height: 900, bitsPerComponent: 8,
        bytesPerRow: 4800, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let scroller = PixelScroller(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    let image = try #require(context.makeImage())
    scroller.pixelImage = image
    scroller.pixelSize = CGSize(width: 1200, height: 900)
    scroller.imageBounds = CGRect(x: 0, y: 0, width: 1200, height: 900)
    var notifications = 0
    scroller.onUserPan = { _ in notifications += 1 }
    scroller.updateScale()
    scroller.navigate(DetailNavigationRequest(center: CGPoint(x: 1, y: 1)))
    #expect(notifications == 0)
    scroller.contentView.scroll(to: CGPoint(x: 100, y: 100))
    #expect(notifications == 1)
  }
}
