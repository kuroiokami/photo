import CoreImage
import Foundation
import ImageIO

/// Coordinates are normalized from the oriented image's top-left corner.
public struct DetailFocus: Sendable {
  public let point: CGPoint
  public let viewportPixels: CGSize
  public init(point: CGPoint, viewportPixels: CGSize) {
    self.point = point
    self.viewportPixels = viewportPixels
  }
}

public struct DetailRegion: Sendable {
  public let preview: PhotoPreview
  /// Top-left pixel coordinates in the full, oriented image.
  public let bounds: CGRect
}

public enum DetailUpdate: Sendable {
  case region(DetailRegion)
  case complete(PhotoPreview)
}

/// One serial, on-demand lane. Reuses its context, never caches decoded photos.
public actor DetailPipeline {
  public static let byteLimit = 256 * 1024 * 1024
  private var context: CIContext?
  public init() {}

  /// Cancellation terminates the producer too. Synchronous Apple decoding cannot
  /// be interrupted mid-call, but cancelled queued work and later stages are skipped.
  public nonisolated func updates(for url: URL, focus: DetailFocus) -> AsyncThrowingStream<
    DetailUpdate, Error
  > {
    AsyncThrowingStream { continuation in
      let job = Task {
        do {
          let image = try await self.render(for: url, focus: focus) {
            continuation.yield(.region($0))
          }
          try Task.checkCancellation()
          continuation.yield(.complete(image))
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { _ in job.cancel() }
    }
  }

  public func detail(for url: URL) throws -> PhotoPreview {
    try render(for: url, focus: nil, regionReady: { _ in })
  }

  private func render(
    for url: URL, focus: DetailFocus?, regionReady: (DetailRegion) -> Void
  ) throws -> PhotoPreview {
    try Task.checkCancellation()
    return try autoreleasepool {
      guard
        let source = CGImageSourceCreateWithURL(
          url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
        let type = CGImageSourceGetType(source) as String?, SupportedImageTypes.supports(type),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
      else { throw PreviewError.unreadable }
      try Task.checkCancellation()
      guard Self.fits(width: width, height: height) else { throw PreviewError.detailTooLarge }
      let image: CGImage
      let raw = SupportedImageTypes.raw.contains(type)
      if raw {
        guard let filter = CIRAWFilter(imageURL: url) else { throw PreviewError.unreadable }
        try Task.checkCancellation()
        guard let output = filter.outputImage else { throw PreviewError.unreadable }
        let extent = output.extent.integral
        guard !extent.isEmpty, !extent.isInfinite, !extent.isNull,
          extent.width.isFinite, extent.height.isFinite,
          extent.width < Double(Int.max), extent.height < Double(Int.max)
        else { throw PreviewError.unreadable }
        let fullWidth = Int(extent.width)
        let fullHeight = Int(extent.height)
        guard Self.fits(width: fullWidth, height: fullHeight) else {
          throw PreviewError.detailTooLarge
        }
        try Task.checkCancellation()
        let context = renderingContext()
        defer { context.clearCaches() }
        // Reserve room for both the temporary focus patch and the full image.
        // This bounds retained decoded images, not transient RAW/GPU allocations.
        if let focus,
          let topLeft = Self.focusBounds(
            width: fullWidth, height: fullHeight, focus: focus)
        {
          let crop = CGRect(
            x: extent.minX + topLeft.minX, y: extent.maxY - topLeft.maxY,
            width: topLeft.width, height: topLeft.height)
          if let patch = try? Self.renderBitmap(output, extent: crop, context: context) {
            try Task.checkCancellation()
            regionReady(
              DetailRegion(
                preview: PhotoPreview(
                  image: patch, sourceKind: .raw,
                  originalWidth: fullWidth, originalHeight: fullHeight), bounds: topLeft))
          }
        }
        try Task.checkCancellation()
        context.clearCaches()
        image = try Self.renderBitmap(output, extent: extent, context: context)
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

  /// Own one eager bitmap instead of retaining a full-size Core Image surface
  /// behind a CGImage. Wait for GPU completion here, never on first UI draw.
  static func renderBitmap(_ output: CIImage, extent: CGRect, context: CIContext) throws
    -> CGImage
  {
    let width = Int(extent.width)
    let height = Int(extent.height)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let bitmap = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: alignedStride(width), space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = bitmap.data
    else { throw PreviewError.unreadable }
    let destination = CIRenderDestination(
      bitmapData: data, width: width, height: height,
      bytesPerRow: bitmap.bytesPerRow, format: .RGBA8)
    destination.colorSpace = colorSpace
    destination.isFlipped = true
    // Bound temporary GPU surfaces and check cancellation between strips.
    // RAW processing may still read the full source; this is not region decoding.
    let stripHeight = width <= 2048 && height <= 2048 ? height : 1024
    for row in stride(from: 0, to: height, by: stripHeight) {
      try Task.checkCancellation()
      let strip = CGRect(
        x: extent.minX, y: extent.minY + Double(row),
        width: extent.width, height: Double(min(stripHeight, height - row)))
      let task = try context.startTask(
        toRender: output, from: strip,
        to: destination, at: CGPoint(x: 0, y: row))
      _ = try task.waitUntilCompleted()
      context.clearCaches()
    }
    try Task.checkCancellation()
    guard let image = bitmap.makeImage() else { throw PreviewError.unreadable }
    return image
  }

  private func renderingContext() -> CIContext {
    if let context { return context }
    let created = CIContext(options: [.cacheIntermediates: false])
    context = created
    return created
  }

  /// A small full-quality region centered on the pointer, clamped to image edges.
  /// Nil means there is no useful region or no remaining decoded-image budget.
  public nonisolated static func focusBounds(width: Int, height: Int, focus: DetailFocus) -> CGRect?
  {
    guard fits(width: width, height: height),
      focus.point.x.isFinite, focus.point.y.isFinite,
      focus.viewportPixels.width.isFinite, focus.viewportPixels.height.isFinite,
      focus.viewportPixels.width > 0, focus.viewportPixels.height > 0
    else { return nil }
    let fullBytes = alignedStride(width) * height
    let available = min(32 * 1024 * 1024, byteLimit - fullBytes)
    let w = min(width, Int(min(2048, focus.viewportPixels.width + 256)))
    let h = min(height, Int(min(2048, focus.viewportPixels.height + 256)))
    guard w > 0, h > 0, alignedStride(w) <= available / h,
      w < width || h < height
    else { return nil }
    let x = min(
      width - w,
      max(0, Int((Double(width) * min(1, max(0, focus.point.x)) - Double(w) / 2).rounded())))
    let y = min(
      height - h,
      max(0, Int((Double(height) * min(1, max(0, focus.point.y)) - Double(h) / 2).rounded())))
    return CGRect(x: x, y: y, width: w, height: h)
  }

  private nonisolated static func alignedStride(_ width: Int) -> Int {
    ((width * 4 + 255) / 256) * 256
  }
  public nonisolated static func fits(width: Int, height: Int) -> Bool {
    guard width > 0, height > 0, width <= byteLimit / 4 else { return false }
    return alignedStride(width) <= byteLimit / height
  }
}
