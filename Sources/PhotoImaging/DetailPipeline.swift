import CoreImage
import Foundation
import ImageIO

/// One serial on-demand lane. No full-detail cache or speculative RAW rendering.
public actor DetailPipeline {
  public static let byteLimit = 256 * 1024 * 1024
  public init() {}

  public func detail(for url: URL) async throws -> PhotoPreview {
    try Task.checkCancellation()
    return try autoreleasepool {
      guard
        let source = CGImageSourceCreateWithURL(
          url as CFURL,
          [kCGImageSourceShouldCache: false] as CFDictionary),
        let type = CGImageSourceGetType(source) as String?,
        SupportedImageTypes.supports(type),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
      else { throw PreviewError.unreadable }
      guard Self.fits(width: width, height: height) else { throw PreviewError.detailTooLarge }
      let image: CGImage
      let raw = SupportedImageTypes.raw.contains(type)
      if raw {
        guard let filter = CIRAWFilter(imageURL: url), let output = filter.outputImage,
          output.extent.width.isFinite, output.extent.height.isFinite,
          output.extent.width < Double(Int.max), output.extent.height < Double(Int.max),
          Self.fits(width: Int(output.extent.width), height: Int(output.extent.height))
        else { throw PreviewError.unreadable }
        try Task.checkCancellation()
        let context = CIContext(options: [.cacheIntermediates: false])
        guard
          let rendered = context.createCGImage(
            output, from: output.extent,
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        else { throw PreviewError.unreadable }
        image = rendered
      } else {
        guard
          let decoded = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: max(width, height),
              kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        else { throw PreviewError.unreadable }
        image = decoded
      }
      try Task.checkCancellation()
      guard image.bytesPerRow <= Self.byteLimit / max(1, image.height) else {
        throw PreviewError.detailTooLarge
      }
      return PhotoPreview(
        image: image, sourceKind: raw ? .raw : .image,
        originalWidth: image.width, originalHeight: image.height)
    }
  }

  public nonisolated static func fits(width: Int, height: Int) -> Bool {
    // Reserve row-alignment space and avoid overflow for corrupt dimensions.
    guard width > 0, height > 0, width <= byteLimit / 4 else { return false }
    let stride = ((width * 4 + 255) / 256) * 256
    return stride <= byteLimit / height
  }
}
