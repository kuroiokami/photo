import CoreGraphics
import Foundation
import ImageIO
import PhotoCore

/// CGImage is immutable. Sharing the decoded image never shares mutable drawing state.
public struct PhotoPreview: @unchecked Sendable {
  public let image: CGImage
  public var sourceKind: PreviewSource = .image
  public var decodedWidth: Int { image.width }
  public var decodedHeight: Int { image.height }
  public let originalWidth: Int
  public let originalHeight: Int
  public var byteCost: Int { image.bytesPerRow * image.height }
}

public enum PreviewSource: String, Sendable {
  case image = "Image"
  case embedded = "Embedded preview"
  case raw = "Rendered RAW"
}

public enum PreviewError: LocalizedError {
  case unreadable
  case embeddedUnavailable
  case detailTooLarge
  public var errorDescription: String? {
    switch self {
    case .unreadable:
      "This image could not be read. It may be damaged, unsupported, or no longer available."
    case .embeddedUnavailable:
      "No readable embedded preview. RAW rendering is available through 100% inspection on supported cameras."
    case .detailTooLarge:
      "Full detail exceeds the 256 MiB decoded-image limit. Fit preview remains available."
    }
  }
}

/// Synchronous ImageIO work runs inside its owning pipeline actor. A local
/// autorelease pool releases temporary decoder objects after every image.
private enum ImageDecoder {
  static func decode(_ url: URL, maximumPixelSize: Int) throws -> PhotoPreview {
    try autoreleasepool {
      try Task.checkCancellation()
      let options = [kCGImageSourceShouldCache: false] as CFDictionary
      guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
        let type = CGImageSourceGetType(source) as String?,
        ["public.jpeg", "public.png", "com.sony.arw-raw-image"].contains(type),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
      else { throw PreviewError.unreadable }
      let raw = type == "com.sony.arw-raw-image"
      let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
      let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: !raw,
        kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        kCGImageSourceShouldCacheImmediately: true,
      ]
      guard
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
      else { throw raw ? PreviewError.embeddedUnavailable : PreviewError.unreadable }
      try Task.checkCancellation()
      return PhotoPreview(
        image: image, sourceKind: raw ? .embedded : .image,
        originalWidth: orientation >= 5 ? height : width,
        originalHeight: orientation >= 5 ? width : height)
    }
  }
}

public actor ImagePipeline: PhotoPreviewLoading {
  private struct Key: Hashable {
    let url: URL
    let size: Int
  }
  private var sessionID: UUID?
  private let byteLimit: Int
  private var cache: [Key: PhotoPreview] = [:]
  private var order: [Key] = []
  public private(set) var cachedByteCount = 0
  private(set) var decodedImageCount = 0

  public init(byteLimit: Int) { self.byteLimit = max(0, byteLimit) }

  public func preview(
    for file: URL, maximumPixelSize: Int, sessionID: UUID? = nil
  ) async throws -> PhotoPreview {
    try Task.checkCancellation()
    startSession(sessionID)
    let size = min(max(maximumPixelSize, 1), 2560)
    let key = Key(url: file, size: size)
    if let cached = cache[key] {
      touch(key)
      return cached
    }
    // Do not suspend between the cache check and decoding: queued requests
    // then reuse the completed entry instead of redundantly decoding it.
    decodedImageCount += 1
    let result = try ImageDecoder.decode(file, maximumPixelSize: size)
    try Task.checkCancellation()
    if result.byteCost <= byteLimit {
      while cachedByteCount + result.byteCost > byteLimit, let oldest = order.first {
        order.removeFirst()
        if let removed = cache.removeValue(forKey: oldest) { cachedByteCount -= removed.byteCost }
      }
      cache[key] = result
      order.append(key)
      cachedByteCount += result.byteCost
    }
    return result
  }

  /// A non-decoding lookup lets the UI bypass its cold-preview debounce on hits.
  public func cachedPreview(
    for file: URL, maximumPixelSize: Int, sessionID: UUID? = nil
  ) -> PhotoPreview? {
    guard !Task.isCancelled, self.sessionID == sessionID else { return nil }
    let key = Key(url: file, size: min(max(maximumPixelSize, 1), 2560))
    guard let result = cache[key] else { return nil }
    touch(key)
    return result
  }

  /// Keep the actor/worker stable across folders; changing a session only drops
  /// cached images. In-flight work cannot overlap a replacement worker.
  public func startSession(_ sessionID: UUID?) {
    guard !Task.isCancelled, self.sessionID != sessionID else { return }
    self.sessionID = sessionID
    cache.removeAll(keepingCapacity: true)
    order.removeAll(keepingCapacity: true)
    cachedByteCount = 0
  }

  private func touch(_ key: Key) {
    order.removeAll { $0 == key }
    order.append(key)
  }
}
