import Foundation
import ImageIO
import PhotoCore

public actor ImageMetadataReader: PhotoMetadataReading {
  public init() {}
  public func metadata(for file: URL) async throws -> PhotoMetadata {
    try Task.checkCancellation()
    return try autoreleasepool {
      guard
        let source = CGImageSourceCreateWithURL(
          file as CFURL,
          [kCGImageSourceShouldCache: false] as CFDictionary),
        let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      else { throw PreviewError.unreadable }
      let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
      let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
      let orientation = (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
      let width = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
      let height = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
      var result = PhotoMetadata(
        pixelWidth: orientation >= 5 ? height : width,
        pixelHeight: orientation >= 5 ? width : height)
      result.camera = tiff[kCGImagePropertyTIFFModel] as? String
      result.lens = exif[kCGImagePropertyExifLensModel] as? String
      result.exposureTime = (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue
      result.aperture = (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue
      result.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.doubleValue
      result.focalLength = (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue
      result.captureTimeText = exif[kCGImagePropertyExifDateTimeOriginal] as? String
      if let text = result.captureTimeText {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // EXIF without an offset remains a wall-clock time; use UTC consistently
        // rather than making order depend on the Mac's current time zone.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
          formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
          result.captureTime = formatter.date(from: text + offset)
          result.captureTimeText = text + " " + offset
        } else {
          formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
          result.captureTime = formatter.date(from: text)
        }
      }
      try Task.checkCancellation()
      return result
    }
  }
}
