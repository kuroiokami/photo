import AppKit
import PhotoCore
import Testing

@testable import PhotoUI

@MainActor
struct ImageEditDrawingTests {
  private func fixture() throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil, width: 6, height: 4, bitsPerComponent: 8, bytesPerRow: 24,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for y in 0..<4 {
      for x in 0..<6 {
        context.setFillColor(
          CGColor(red: CGFloat(x + 1) / 7, green: CGFloat(y + 1) / 5, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: x, y: y, width: 1, height: 1))
      }
    }
    return try #require(context.makeImage())
  }
  private func rendered(_ image: CGImage, edit: PhotoEdit) throws -> NSBitmapImageRep {
    let size = edit.cropBounds(CGSize(width: image.width, height: image.height)).size
    let view = EditedBitmapView(frame: CGRect(origin: .zero, size: size))
    view.set(image, edit: edit)
    return try snapshot(view)
  }
  private func snapshot(_ view: NSView) throws -> NSBitmapImageRep {
    // Pin this pixel oracle to 1 pixel per point; NSView's automatic snapshot
    // follows the screen's Retina backing scale and would change sample coordinates.
    let rep = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width),
        pixelsHigh: Int(view.bounds.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: Int(view.bounds.width) * 4, bitsPerPixel: 32))
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
  }
  @Test func allOrientationsAndCropDrawTheSameSourcePixels() throws {
    let image = try fixture()
    let baseline = try rendered(image, edit: PhotoEdit())
    for turns in 0..<4 {
      for mirrored in [false, true] {
        for crop in [nil, PhotoCrop(x: 0.25, y: 0.25, width: 0.5, height: 0.5)] {
          let edit = PhotoEdit(quarterTurns: turns, mirrored: mirrored, crop: crop)
          let result = try rendered(image, edit: edit)
          let size = edit.cropBounds(CGSize(width: 6, height: 4)).size
          #expect(result.pixelsWide == Int(size.width) && result.pixelsHigh == Int(size.height))
          for y in 0..<result.pixelsHigh {
            for x in 0..<result.pixelsWide {
              let source = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5).applying(
                edit.transform(CGSize(width: 6, height: 4)).inverted())
              let expected = try #require(
                baseline.colorAt(x: Int(source.x), y: Int(source.y))?.usingColorSpace(.deviceRGB))
              let actual = try #require(result.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
              #expect(
                abs(actual.redComponent - expected.redComponent) < 0.02,
                "turns \(turns), mirror \(mirrored), crop \(String(describing: crop)), output \(x),\(y), source \(source)"
              )
              #expect(
                abs(actual.greenComponent - expected.greenComponent) < 0.02,
                "turns \(turns), mirror \(mirrored), crop \(String(describing: crop)), output \(x),\(y), source \(source)"
              )
            }
          }
        }
      }
    }
  }
  @Test func croppedPixelScrollerUsesPhysicalPixelsAndZoomReusesImage() throws {
    let image = try fixture()
    let scroller = PixelScroller(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
    scroller.pixelImage = image
    scroller.pixelSize = CGSize(width: 6, height: 4)
    scroller.imageBounds = CGRect(x: 0, y: 0, width: 6, height: 4)
    scroller.edit = PhotoEdit(quarterTurns: 1, crop: PhotoCrop(x: 0, y: 0, width: 0.5, height: 1))
    scroller.inspectionScale = 2
    scroller.updateScale()
    #expect(scroller.documentView?.frame.size == CGSize(width: 4, height: 12))
    #expect(scroller.pixelImage === image)
    #expect(InspectionZoom.changed(1, delta: 0.5) == 1.5)
    #expect(InspectionZoom.changed(1, delta: -.infinity) == 1)
    #expect(InspectionZoom.changed(8, delta: 10) == 8)
  }
  @Test func cropMovementRatiosAndLinkedMagnificationStayBounded() {
    let moved = CropGeometry.moved(
      PhotoCrop(x: 0.2, y: 0.3, width: 0.4, height: 0.5), delta: CGSize(width: 2, height: -2))
    #expect(moved.x == 0.6 && moved.y == 0)
    let square = CropGeometry.ratio(1, image: CGSize(width: 600, height: 400))
    #expect(abs(square.width * 600 - square.height * 400) < 0.001)
    let session = ComparisonSession()
    session.pin(SampleLibrary.photos[0])
    session.zoom(true, center: CGPoint(x: 0.4, y: 0.6), scale: 2.5, from: .active)
    #expect(session.request(for: .reference)?.action == .zoom(CGPoint(x: 0.4, y: 0.6), scale: 2.5))
    session.setLinked(false)
    session.zoom(true, center: .zero, scale: 0.5, from: .active)
    session.setLinked(true)
    #expect(session.request(for: .reference)?.action == .zoom(.zero, scale: 0.5))
  }
  @Test func editedFitDoesNotPaintIntoLetterboxing() throws {
    let image = try fixture()
    let view = EditedBitmapView(frame: CGRect(x: 0, y: 0, width: 40, height: 16))
    let edit = PhotoEdit(crop: PhotoCrop(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    view.set(image, edit: edit)
    let rep = try snapshot(view)
    #expect(try #require(rep.colorAt(x: 0, y: 8)).alphaComponent == 0)
    #expect(try #require(rep.colorAt(x: 39, y: 8)).alphaComponent == 0)
    #expect(try #require(rep.colorAt(x: 20, y: 8)).alphaComponent > 0.99)
  }
  @Test func transformedProgressiveRegionMatchesFinishedPixels() throws {
    let image = try fixture()
    let region = CGRect(x: 2, y: 1, width: 2, height: 2)
    let patch = try #require(image.cropping(to: region))
    for turns in 0..<4 {
      for mirrored in [false, true] {
        let edit = PhotoEdit(
          quarterTurns: turns, mirrored: mirrored,
          crop: PhotoCrop(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let finished = try rendered(image, edit: edit)
        let scroll = PixelScroller(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scroll.pixelImage = patch
        scroll.pixelSize = CGSize(width: 6, height: 4)
        scroll.imageBounds = region
        scroll.edit = edit
        scroll.updateScale()
        let document = try #require(scroll.documentView)
        let partial = try snapshot(document)
        for y in 0..<partial.pixelsHigh {
          for x in 0..<partial.pixelsWide {
            let source = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5).applying(
              edit.transform(CGSize(width: 6, height: 4)).inverted())
            let actual = try #require(partial.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            if region.contains(source) {
              let expected = try #require(finished.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
              #expect(abs(actual.redComponent - expected.redComponent) < 0.02)
              #expect(abs(actual.greenComponent - expected.greenComponent) < 0.02)
            } else {
              #expect(actual.redComponent < 0.01 && actual.greenComponent < 0.01)
            }
          }
        }
      }
    }
    let anchored = NavigatorGeometry.origin(
      center: CGPoint(x: 0.6, y: 0.5), image: CGSize(width: 1000, height: 800),
      viewport: CGSize(width: 200, height: 100), anchor: CGPoint(x: 0.2, y: 0.7))
    #expect(anchored == CGPoint(x: 560, y: 330))
  }

}
