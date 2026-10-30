import PhotoCore
import SwiftUI
import Testing

@testable import PhotoUI

struct CropAspectTests {
  private func check(_ crop: PhotoCrop, ratio: Double, image: CGSize) {
    #expect(abs(crop.width * image.width / (crop.height * image.height) - ratio) < 0.000001)
    #expect(crop.x >= 0 && crop.y >= 0 && crop.width >= 0.01 && crop.height >= 0.01)
    #expect(crop.x + crop.width <= 1.000000000001 && crop.y + crop.height <= 1.000000000001)
  }
  @Test func lockedDrawingAndAllCornerResizeDirectionsKeepPixelProportionsAtBounds() throws {
    #expect(CropAspect.threeTwo.title(swapped: true) == "2:3")
    #expect(CropAspect.wide.title(swapped: true) == "9:16")
    #expect(CropAspect.square.title(swapped: true) == "1:1")
    for image in [CGSize(width: 6000, height: 4000), CGSize(width: 4000, height: 6000)] {
      for aspect in CropAspect.allCases where aspect != .free {
        for swapped in [false, true] {
          let ratio = try #require(aspect.ratio(image: image, swapped: swapped))
          let fitted = try #require(
            CropGeometry.fitting(
              PhotoCrop(x: 0.1, y: 0.2, width: 0.7, height: 0.6), ratio: ratio, image: image))
          check(fitted, ratio: ratio, image: image)
          for corner in 0..<4 {
            let directions = CGSize(width: corner % 2 == 0 ? -1 : 1, height: corner < 2 ? -1 : 1)
            let anchor = CGPoint(
              x: corner % 2 == 0 ? fitted.x + fitted.width : fitted.x,
              y: corner < 2 ? fitted.y + fitted.height : fitted.y)
            for target in [CGPoint.zero, CGPoint(x: 1, y: 1), CGPoint(x: 0.01, y: 0.99), anchor] {
              for axis in [false, true] {
                let result = try #require(
                  CropGeometry.constrainedRectangle(
                    anchor, target,
                    ratio: ratio, image: image, directions: directions, drivingWidth: axis))
                check(result, ratio: ratio, image: image)
              }
              let drawing = try #require(
                CropGeometry.constrainedRectangle(
                  anchor, target,
                  ratio: ratio, image: image))
              check(drawing, ratio: ratio, image: image)
            }
          }
        }
      }
    }
  }
  @Test func lockingUsesOrientedOriginalDimensionsAndFreeRemainsUnconstrained() throws {
    let source = CGSize(width: 6000, height: 4000)
    let oriented = PhotoEdit(quarterTurns: 1).orientedSize(source)
    #expect(CropAspect.original.ratio(image: oriented, swapped: false) == 2.0 / 3)
    let square = try #require(
      CropGeometry.constrainedRectangle(
        .zero,
        CGPoint(x: 0.3, y: 0.6), ratio: 1, image: oriented, drivingWidth: true))
    check(square, ratio: 1, image: oriented)
    let free = try #require(
      CropGeometry.constrainedRectangle(
        .zero,
        CGPoint(x: 0.3, y: 0.6), ratio: nil, image: oriented))
    #expect(free.width == 0.3 && free.height == 0.6)
    #expect(CropGeometry.fitting(free, ratio: 1, image: CGSize(width: 100000, height: 1)) == nil)
    #expect(
      CropGeometry.constrainedRectangle(
        .zero, CGPoint(x: Double.nan, y: 1),
        ratio: 1, image: source) == nil)
  }
}
