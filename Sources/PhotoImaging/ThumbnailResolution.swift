import Foundation

/// Stable physical-pixel classes. Never change size on every point of a drag.
public enum ThumbnailResolution {
  public static let levels = [160, 240, 320, 480]
  public static func edge(points: Double, displayScale: Double) -> Int {
    let points = points.isFinite ? max(1, points) : 480
    let scale = displayScale.isFinite ? max(1, displayScale) : 1
    let required = points * scale
    return levels.first { Double($0) >= required } ?? 480
  }
}

/// The cache's actual request class accompanies the pixels, so a temporary
/// lower-resolution stand-in cannot be mistaken for a completed larger load.
public struct CachedThumbnail: Sendable {
  public let preview: PhotoPreview
  public let requestedPixelSize: Int
}
