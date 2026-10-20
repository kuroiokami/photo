import SwiftUI

struct PhotoTileFrames: PreferenceKey {
  static let defaultValue: [String: CGRect] = [:]
  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
struct SelectionMarquee {
  var start: CGPoint
  var end: CGPoint
  var base: Set<String>
  var rectangle: CGRect {
    CGRect(
      x: min(start.x, end.x), y: min(start.y, end.y),
      width: abs(start.x - end.x), height: abs(start.y - end.y))
  }
}
