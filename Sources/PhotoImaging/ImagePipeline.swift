import CoreGraphics
import Foundation
import ImageIO
import PhotoCore

/// CGImage is immutable. Sharing the decoded image never shares mutable drawing state.
public struct PhotoPreview: @unchecked Sendable {
  public let image: CGImage
  public let originalWidth: Int
  public let originalHeight: Int
  public var byteCost: Int { image.bytesPerRow * image.height }
}

public enum PreviewError: LocalizedError {
  case unreadable
  public var errorDescription: String? {
    "This image could not be read. It may be damaged, unsupported, or no longer available."
  }
}

/// One decoder per lane means at most one thumbnail and one preview decode run
/// concurrently. Cancelled requests check before entering expensive ImageIO work.
private actor ImageDecoder {
  func decode(_ url: URL, maximumPixelSize: Int) throws -> PhotoPreview {
    try Task.checkCancellation()
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
      let type = CGImageSourceGetType(source) as String?,
      ["public.jpeg", "public.png"].contains(type),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { throw PreviewError.unreadable }
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    else { throw PreviewError.unreadable }
    try Task.checkCancellation()
    return PhotoPreview(
      image: image, originalWidth: orientation >= 5 ? height : width,
      originalHeight: orientation >= 5 ? width : height)
  }
}

public actor ImagePipeline: PhotoPreviewLoading {
  private struct Key: Hashable {
    let url: URL
    let size: Int
  }
  private let decoder = ImageDecoder()
  private let byteLimit: Int
  private var cache: [Key: PhotoPreview] = [:]
  private var order: [Key] = []
  public private(set) var cachedByteCount = 0

  public init(byteLimit: Int) { self.byteLimit = max(0, byteLimit) }

  public func preview(for file: URL, maximumPixelSize: Int) async throws -> PhotoPreview {
    try Task.checkCancellation()
    let size = min(max(maximumPixelSize, 1), 2560)
    let key = Key(url: file, size: size)
    if let cached = cache[key] {
      touch(key)
      return cached
    }
    let result = try await decoder.decode(file, maximumPixelSize: size)
    try Task.checkCancellation()
    // Another request may have populated the same entry while awaiting decoding.
    if let existing = cache[key] {
      touch(key)
      return existing
    }
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

  private func touch(_ key: Key) {
    order.removeAll { $0 == key }
    order.append(key)
  }
}
