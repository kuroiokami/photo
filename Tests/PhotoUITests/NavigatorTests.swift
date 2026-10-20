import AppKit
import Foundation
import PhotoCore
import Testing

@testable import PhotoUI

struct NavigatorGeometryTests {
  @Test func clickingEdgesKeepsViewportInsideTheImage() {
    let visible = CGSize(width: 0.2, height: 0.4)
    let size = CGSize(width: 156, height: 104)
    #expect(
      NavigatorGeometry.target(location: .zero, thumbnail: size, offset: .zero, visible: visible)
        == CGPoint(x: 0.1, y: 0.2))
    #expect(
      NavigatorGeometry.target(
        location: CGPoint(x: 999, y: 999), thumbnail: size, offset: .zero, visible: visible)
        == CGPoint(x: 0.9, y: 0.8))
    #expect(
      NavigatorGeometry.center(CGPoint(x: 0, y: 1), visible: CGSize(width: 2, height: 1))
        == CGPoint(x: 0.5, y: 0.5))
  }
  @Test func draggingFramePreservesTheGrabOffset() {
    let target = NavigatorGeometry.target(
      location: CGPoint(x: 90, y: 70), thumbnail: CGSize(width: 100, height: 100),
      offset: CGPoint(x: 10, y: 20), visible: CGSize(width: 0.2, height: 0.2))
    #expect(target == CGPoint(x: 0.8, y: 0.5))
    #expect(
      NavigatorGeometry.target(
        location: CGPoint(x: 40, y: 70), thumbnail: CGSize(width: 100, height: 100),
        offset: CGPoint(x: 10, y: 20), visible: CGSize(width: 0.2, height: 0.2))
        == CGPoint(x: 0.3, y: 0.5))
  }
  @Test func portraitAndPanoramaNavigatorsStayBounded() {
    let portrait = NavigatorGeometry.thumbnailSize(image: CGSize(width: 400, height: 800))
    #expect(abs(portrait.width - 56) < 0.001 && abs(portrait.height - 112) < 0.001)
    let panorama = NavigatorGeometry.thumbnailSize(image: CGSize(width: 10_000, height: 1000))
    #expect(panorama.width == 156)
    #expect(abs(panorama.height - 15.6) < 0.001)
    #expect(
      NavigatorGeometry.center(CGPoint(x: Double.nan, y: Double.infinity), visible: .zero)
        == CGPoint(x: 0.5, y: 0.5))
  }
}

@MainActor
struct NavigatorScrollTests {
  @Test func smallImagesRemainCenteredAtActualPixelScale() throws {
    let bitmap = try #require(
      CGContext(
        data: nil, width: 100, height: 80, bitsPerComponent: 8,
        bytesPerRow: 400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let scroller = PixelScroller(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    let image = try #require(bitmap.makeImage())
    scroller.pixelImage = image
    scroller.pixelSize = CGSize(width: 100, height: 80)
    scroller.imageBounds = CGRect(x: 0, y: 0, width: 100, height: 80)
    scroller.updateScale()
    scroller.navigate(DetailNavigationRequest(center: .zero))
    #expect(abs(scroller.contentView.bounds.midX - 50) < 0.001)
    #expect(abs(scroller.contentView.bounds.midY - 40) < 0.001)
  }
  @Test func repeatedClicksAndProgressiveReplacementKeepTheRequestedPosition() throws {
    let bitmap = try #require(
      CGContext(
        data: nil, width: 1200, height: 900, bitsPerComponent: 8,
        bytesPerRow: 4800, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(bitmap.makeImage())
    let scroller = PixelScroller(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    scroller.pixelImage = image
    scroller.pixelSize = CGSize(width: 1200, height: 900)
    scroller.imageBounds = CGRect(x: 0, y: 0, width: 600, height: 450)
    scroller.updateScale()
    let point = CGPoint(x: 0.8, y: 0.2)
    scroller.navigate(DetailNavigationRequest(center: point))
    let expected = NavigatorGeometry.origin(
      center: point, image: CGSize(width: 1200, height: 900), viewport: scroller.contentSize)
    #expect(scroller.contentView.bounds.origin == expected)
    scroller.imageBounds = CGRect(x: 0, y: 0, width: 1200, height: 900)
    scroller.updateScale()
    #expect(scroller.contentView.bounds.origin == expected)
    scroller.contentView.scroll(to: .zero)
    // Same target with a fresh request must work after manual panning.
    scroller.navigate(DetailNavigationRequest(center: point))
    #expect(scroller.contentView.bounds.origin == expected)
    scroller.navigate(DetailNavigationRequest(center: CGPoint(x: -1, y: 2)))
    #expect(scroller.contentView.bounds.minX == 0)
    #expect(scroller.contentView.bounds.maxY <= 900)
  }
}
