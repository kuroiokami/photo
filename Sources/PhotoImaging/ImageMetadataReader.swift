import Foundation
import ImageIO
import PhotoCore

public actor ImageMetadataReader: PhotoMetadataReading {
  private let wallClock = ImageMetadataReader.formatter("yyyy:MM:dd HH:mm:ss")
  private let offsetClock = ImageMetadataReader.formatter("yyyy:MM:dd HH:mm:ssXXXXX")
  private static func formatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter
  }
  public init() {}
  public func embeddedXMP(for file: URL) throws -> Data? {
    try Task.checkCancellation()
    return autoreleasepool {
      guard
        let source = CGImageSourceCreateWithURL(
          file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
        let data = CGImageMetadataCreateXMPData(metadata, nil)
      else { return nil }
      return data as Data
    }
  }
  public func metadata(for file: URL) async throws -> PhotoMetadata {
    let trace = PhotoTrace.begin("ReadEXIF")
    defer { PhotoTrace.end(trace) }
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
        // Reuse actor-owned formatters; EXIF without an offset stays in UTC.
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
          result.captureTime = offsetClock.date(from: text + offset)
          result.captureTimeText = text + " " + offset
        } else {
          result.captureTime = wallClock.date(from: text)
        }
      }
      if let fraction = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String,
        fraction.allSatisfy(\.isNumber), let seconds = Double("0." + fraction), seconds.isFinite
      {
        result.captureTime = result.captureTime?.addingTimeInterval(seconds)
      }
      if let value = result.exposureTime, !value.isFinite || value <= 0 {
        result.exposureTime = nil
      }
      if let value = result.aperture, !value.isFinite || value <= 0 { result.aperture = nil }
      if let value = result.iso, !value.isFinite || value <= 0 { result.iso = nil }
      if let value = result.focalLength, !value.isFinite || value <= 0 { result.focalLength = nil }
      try Task.checkCancellation()
      return result
    }
  }
}
