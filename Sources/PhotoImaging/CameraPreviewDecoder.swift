import CoreGraphics
import Darwin
import Foundation
import ImageIO
import PhotoCore

public enum DetailSource: Hashable, Sendable { case original, cameraPreview }
public enum CameraPreviewError: LocalizedError {
  case unavailable, tooLarge, changed
  public var errorDescription: String? {
    switch self {
    case .unavailable:
      "No usable camera preview was found. Choose 100% or press Z to inspect rendered RAW."
    case .tooLarge:
      "This camera preview exceeds the 256 MiB decoded-image limit. The Fit preview is still available."
    case .changed:
      "The photo changed while its preview was loading. Reload the folder and try again."
    }
  }
}

enum CameraPreviewDecoder {
  struct Stamp: Equatable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let modified: Int
    let nanos: Int
    let changed: Int
    let changedNanos: Int
    init?(_ url: URL) {
      var s = stat()
      guard lstat(url.path, &s) == 0, s.st_mode & S_IFMT == S_IFREG else { return nil }
      device = s.st_dev
      inode = s.st_ino
      size = s.st_size
      modified = s.st_mtimespec.tv_sec
      nanos = s.st_mtimespec.tv_nsec
      changed = s.st_ctimespec.tv_sec
      changedNanos = s.st_ctimespec.tv_nsec
    }
  }
  static func decode(_ url: URL) throws -> PhotoPreview {
    try Task.checkCancellation()
    guard PhotoFormats.isRaw(url), let before = Stamp(url) else {
      throw CameraPreviewError.unavailable
    }
    let result = try autoreleasepool {
      let reader = try BufferedContainerReader(url: url)
      var index = CameraJPEGIndex(reader: reader)
      let ext = url.pathExtension.lowercased()
      if ext == "cr3" {
        try index.cr3()
      } else if ["arw", "cr2", "orf"].contains(ext) {
        try index.tiff()
      }
      var frames: [CameraJPEGIndex.Frame] = []
      for range in index.ranges { if let frame = try index.frame(range) { frames.append(frame) } }
      if let frame = frames.max(by: {
        UInt64($0.width) * UInt64($0.height) < UInt64($1.width) * UInt64($1.height)
      }) {
        let orientation = index.orientation ?? 1
        guard DetailPipeline.fits(width: frame.width, height: frame.height),
          DetailPipeline.fits(
            width: orientation >= 5 ? frame.height : frame.width,
            height: orientation >= 5 ? frame.width : frame.height)
        else { throw CameraPreviewError.tooLarge }
        guard let bytes = try reader.read(frame.range.offset, frame.range.count),
          let source = CGImageSourceCreateWithData(
            bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetType(source) as String? == "public.jpeg",
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == frame.width,
          (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == frame.height
        else { throw CameraPreviewError.unavailable }
        defer { CGImageSourceRemoveCacheAtIndex(source, 0) }
        let jpegOrientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard jpegOrientation == 1 || jpegOrientation == orientation else {
          throw CameraPreviewError.unavailable
        }
        try Task.checkCancellation()
        guard
          let decoded = CGImageSourceCreateImageAtIndex(
            source, 0,
            [
              kCGImageSourceShouldCache: false, kCGImageSourceShouldCacheImmediately: false,
              kCGImageSourceShouldAllowFloat: false,
            ] as CFDictionary),
          decoded.width == frame.width, decoded.height == frame.height,
          let image = oriented(decoded, orientation: orientation)
        else { throw CameraPreviewError.unavailable }
        return PhotoPreview(
          image: image, sourceKind: .cameraJPEG, originalWidth: image.width,
          originalHeight: image.height)
      }
      // Embedded-only fallback: never ask ImageIO to generate from RAW pixels.
      // A conservative size cap bounds unknown embedded layouts before decoding.
      guard
        let source = CGImageSourceCreateWithURL(
          url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
        let type = CGImageSourceGetType(source) as String?, SupportedImageTypes.raw.contains(type),
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
          ] as CFDictionary)
      else { throw CameraPreviewError.unavailable }
      defer { CGImageSourceRemoveCacheAtIndex(source, 0) }
      guard let owned = oriented(image, orientation: 1) else {
        throw CameraPreviewError.unavailable
      }
      return PhotoPreview(
        image: owned, sourceKind: .embedded, originalWidth: owned.width,
        originalHeight: owned.height)
    }
    try Task.checkCancellation()
    guard Stamp(url) == before else { throw CameraPreviewError.changed }
    guard result.byteCost <= DetailPipeline.byteLimit else { throw CameraPreviewError.tooLarge }
    return result
  }
  static func oriented(_ image: CGImage, orientation: Int) -> CGImage? {
    guard (1...8).contains(orientation) else { return nil }
    // Export an owned eager bitmap, not an ImageIO decoder/cache-backed image.
    let w = CGFloat(image.width)
    let h = CGFloat(image.height)
    let transforms = [
      CGAffineTransform.identity,
      CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0),
      CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h),
      CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h),
      CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w),
      CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w),
      CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0),
      CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0),
    ]
    let width = orientation >= 5 ? image.height : image.width
    let height = orientation >= 5 ? image.width : image.height
    guard DetailPipeline.fits(width: width, height: height) else { return nil }
    let stride = ((width * 4 + 255) / 256) * 256
    let cost = stride * height
    guard let bytes = calloc(1, cost) else { return nil }
    var transferred = false
    defer { if !transferred { free(bytes) } }
    let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: bytes, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: stride, space: space, bitmapInfo: info.rawValue)
    else { return nil }
    context.concatenate(transforms[orientation - 1])
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    context.flush()
    guard
      let provider = CGDataProvider(
        dataInfo: nil, data: bytes, size: cost,
        releaseData: { _, pointer, count in
          CameraBitmapAccounting.shared.change(-count)
          free(UnsafeMutableRawPointer(mutating: pointer))
        })
    else { return nil }
    CameraBitmapAccounting.shared.change(cost)
    transferred = true
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: stride, space: space, bitmapInfo: info, provider: provider, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent)
  }
}

/// Counts owned output buffers only, not SDK/allocator transient memory.
final class CameraBitmapAccounting: @unchecked Sendable {
  static let shared = CameraBitmapAccounting()
  private let lock = NSLock()
  private var live = 0
  func change(_ delta: Int) { lock.withLock { live += delta } }
  var bytes: Int { lock.withLock { live } }
}
