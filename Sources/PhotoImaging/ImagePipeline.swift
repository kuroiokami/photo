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
      if let canon = try CanonEmbeddedPreview.decode(url, maximumPixelSize: maximumPixelSize) {
        return canon
      }
      let options = [kCGImageSourceShouldCache: false] as CFDictionary
      guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
        let type = CGImageSourceGetType(source) as String?,
        SupportedImageTypes.supports(type),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
      else { throw PreviewError.unreadable }
      let raw = SupportedImageTypes.raw.contains(type)
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
  private nonisolated let memory: PreviewMemoryCache
  private let disk: ThumbnailDiskCache?
  private(set) var decodedImageCount = 0
  private(set) var diskHitCount = 0
  public var cachedByteCount: Int { memory.byteCount }

  public init(byteLimit: Int, thumbnailDiskCache: ThumbnailDiskCache? = nil) {
    memory = PreviewMemoryCache(byteLimit: byteLimit)
    disk = thumbnailDiskCache
  }

  /// RAM only: safe for a view to use without waiting behind an image decode.
  public nonisolated func immediateCachedPreview(
    for file: URL, maximumPixelSize: Int, sessionID: UUID? = nil
  ) -> PhotoPreview? {
    guard !Task.isCancelled else { return nil }
    return memory.lookup(file, size: maximumPixelSize, session: sessionID)
  }

  public func preview(
    for file: URL, maximumPixelSize: Int, sessionID: UUID? = nil
  ) async throws -> PhotoPreview {
    try Task.checkCancellation()
    memory.startSession(sessionID)
    let size = min(max(maximumPixelSize, 1), 2560)
    if let cached = memory.lookup(file, size: size, session: sessionID) { return cached }
    let stamp = disk?.key(for: file, size: size)
    if let stamp, let cached = disk?.read(stamp), disk?.key(for: file, size: size) == stamp {
      try Task.checkCancellation()
      diskHitCount += 1
      memory.insert(cached, file: file, size: size)
      return cached
    }
    // No suspension between cache checks and decoding: queued callers reuse
    // the result. The selected-preview worker remains a separate actor.
    decodedImageCount += 1
    let result = try ImageDecoder.decode(file, maximumPixelSize: size)
    try Task.checkCancellation()
    memory.insert(result, file: file, size: size)
    if let stamp, disk?.key(for: file, size: size) == stamp {
      disk?.store(result, key: stamp)
    }
    return result
  }

  public func cachedPreview(
    for file: URL, maximumPixelSize: Int, sessionID: UUID? = nil
  ) -> PhotoPreview? {
    immediateCachedPreview(for: file, maximumPixelSize: maximumPixelSize, sessionID: sessionID)
  }

  public func startSession(_ sessionID: UUID?) {
    guard !Task.isCancelled else { return }
    memory.startSession(sessionID)
  }

  public func cacheStatistics() -> (sourceDecodes: Int, diskHits: Int, memoryBytes: Int) {
    (decodedImageCount, diskHitCount, memory.byteCount)
  }

  public func clearThumbnailCache() {
    memory.clear()
    disk?.clear()
  }
}
