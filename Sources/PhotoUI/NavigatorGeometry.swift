import Foundation

struct DetailNavigationRequest: Equatable {
  let id = UUID()
  let center: CGPoint
}

/// All coordinates are in the oriented image's top-left unit square.
enum NavigatorGeometry {
  static func center(_ point: CGPoint, visible: CGSize) -> CGPoint {
    func clamp(_ value: CGFloat, span: CGFloat) -> CGFloat {
      guard value.isFinite, span.isFinite else { return 0.5 }
      let half = min(1, max(0, span)) / 2
      return min(1 - half, max(half, value))
    }
    return CGPoint(x: clamp(point.x, span: visible.width), y: clamp(point.y, span: visible.height))
  }
  static func thumbnailSize(image: CGSize) -> CGSize {
    guard image.width.isFinite, image.height.isFinite, image.width > 0, image.height > 0 else {
      return CGSize(width: 156, height: 104)
    }
    let scale = min(156 / image.width, 112 / image.height)
    return CGSize(width: image.width * scale, height: image.height * scale)
  }
  static func target(location: CGPoint, thumbnail: CGSize, offset: CGPoint, visible: CGSize)
    -> CGPoint
  {
    guard thumbnail.width > 0, thumbnail.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
    return center(
      CGPoint(
        x: (location.x - offset.x) / thumbnail.width,
        y: (location.y - offset.y) / thumbnail.height), visible: visible)
  }
  static func origin(center: CGPoint, image: CGSize, viewport: CGSize) -> CGPoint {
    let span = CGSize(
      width: viewport.width / max(1, image.width), height: viewport.height / max(1, image.height))
    let point = self.center(center, visible: span)
    return CGPoint(
      x: image.width <= viewport.width
        ? (image.width - viewport.width) / 2 : image.width * point.x - viewport.width / 2,
      y: image.height <= viewport.height
        ? (image.height - viewport.height) / 2 : image.height * point.y - viewport.height / 2)
  }
}
