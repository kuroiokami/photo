import PhotoCore
import SwiftUI

enum CropAspect: String, CaseIterable {
  case free = "Free"
  case original = "Original"
  case square = "1:1"
  case threeTwo = "3:2"
  case fourThree = "4:3"
  case wide = "16:9"

  func title(swapped: Bool) -> String {
    guard swapped else { return rawValue }
    switch self {
    case .threeTwo: return "2:3"
    case .fourThree: return "3:4"
    case .wide: return "9:16"
    case .original: return "Original (swapped)"
    default: return rawValue
    }
  }
  func ratio(image: CGSize, swapped: Bool) -> Double? {
    let value: Double
    switch self {
    case .free: return nil
    case .original: value = image.width / max(1, image.height)
    case .square: value = 1
    case .threeTwo: value = 1.5
    case .fourThree: value = 4.0 / 3
    case .wide: value = 16.0 / 9
    }
    return swapped ? 1 / value : value
  }
}

extension CropGeometry {
  static func normalizedRatio(_ ratio: Double, image: CGSize) -> Double? {
    let value = ratio * image.height / max(1, image.width)
    // PhotoCrop stores at least one percent on each axis. Refuse an
    // unrepresentable shape rather than silently changing the chosen ratio.
    return value.isFinite && (0.01...100).contains(value) ? value : nil
  }
  static func fitting(_ crop: PhotoCrop, ratio: Double, image: CGSize) -> PhotoCrop? {
    guard let r = normalizedRatio(ratio, image: image) else { return nil }
    let minimum = max(0.01, 0.01 / r)
    let height = min(min(1, 1 / r), max(minimum, min(crop.height, crop.width / r)))
    let width = height * r
    return PhotoCrop(
      x: min(1 - width, max(0, crop.x + (crop.width - width) / 2)),
      y: min(1 - height, max(0, crop.y + (crop.height - height) / 2)),
      width: width, height: height)
  }
  static func constrainedRectangle(
    _ a: CGPoint, _ b: CGPoint, ratio: Double?, image: CGSize,
    directions: CGSize? = nil, drivingWidth: Bool? = nil
  ) -> PhotoCrop? {
    guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { return nil }
    guard let ratio else { return rectangle(a, b) }
    guard let r = normalizedRatio(ratio, image: image) else { return nil }
    let sx: Double = directions.map { Double($0.width) } ?? (b.x < a.x ? -1 : 1)
    let sy: Double = directions.map { Double($0.height) } ?? (b.y < a.y ? -1 : 1)
    let minimumH = max(0.01, 0.01 / r)
    let minimumW = minimumH * r
    let anchor = CGPoint(
      x: min(sx > 0 ? 1 - minimumW : 1, max(sx > 0 ? 0 : minimumW, a.x)),
      y: min(sy > 0 ? 1 - minimumH : 1, max(sy > 0 ? 0 : minimumH, a.y)))
    let dx = (b.x - anchor.x) * sx
    let dy = (b.y - anchor.y) * sy
    let desired = drivingWidth.map { $0 ? dx / r : dy } ?? max(dx / r, dy)
    let maximum = min(
      sy > 0 ? 1 - anchor.y : anchor.y,
      (sx > 0 ? 1 - anchor.x : anchor.x) / r)
    let height = min(maximum, max(minimumH, desired))
    let width = height * r
    return PhotoCrop(
      x: sx > 0 ? anchor.x : anchor.x - width,
      y: sy > 0 ? anchor.y : anchor.y - height, width: width, height: height)
  }
}
