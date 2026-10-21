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

/// Pointer hit-testing data is not UI state. Scroll-position updates must not
/// invalidate WorkspaceView and rebuild every thumbnail/control on each frame.
@MainActor
final class PhotoTileGeometry {
  private var frames: [String: CGRect] = [:]

  func replace(with frames: [String: CGRect]) { self.frames = frames }
  func clear() { frames.removeAll(keepingCapacity: true) }

  func hits(in rectangle: CGRect, viewportSize: CGSize) -> Set<String> {
    let viewport = CGRect(origin: .zero, size: viewportSize)
    return Set(
      frames.filter {
        viewport.intersects($0.value) && rectangle.intersects($0.value)
      }.keys)
  }
}
