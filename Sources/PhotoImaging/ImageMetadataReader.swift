import Darwin
import Foundation
import ImageIO
import PhotoCore

/// Fixed counters only: no image names, paths, pixels or metadata values.
public struct MetadataReadStatistics: Codable, Sendable {
  public var sourceCreations = 0
  public var sourceReuses = 0
  public var propertyReads = 0
  public var xmpReads = 0
  public var exifHits = 0
  public var xmpHits = 0
  public var cachedEntries = 0
  public var cachedResultBytes = 0
  public var retainedSources = 0
}

public actor ImageMetadataReader: PhotoMetadataReading {
  private struct Stamp: Equatable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int
    static func read(_ url: URL) -> Self? {
      guard url.isFileURL else { return nil }
      var value = stat()
      guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT == S_IFREG else { return nil }
      return Self(
        device: value.st_dev, inode: value.st_ino, size: value.st_size,
        modifiedSeconds: value.st_mtimespec.tv_sec, modifiedNanoseconds: value.st_mtimespec.tv_nsec,
        changedSeconds: value.st_ctimespec.tv_sec, changedNanoseconds: value.st_ctimespec.tv_nsec)
    }
  }
  private struct Entry {
    let stamp: Stamp
    var metadata: PhotoMetadata?
    var xmp: Data?
    var xmpRead = false
    var accessed: UInt64 = 0
    var cost: Int {
      128 + (xmp?.count ?? 0) + (metadata?.camera?.utf8.count ?? 0)
        + (metadata?.lens?.utf8.count ?? 0) + (metadata?.captureTimeText?.utf8.count ?? 0)
    }
  }
  private struct Source {
    let path: String
    let stamp: Stamp
    let image: CGImageSource
  }
  private var entries: [String: Entry] = [:]
  private var bytes = 0
  private var access: UInt64 = 0
  private let entryLimit: Int
  private let byteLimit: Int
  private var lastSource: Source?
  private var sourceDeadline = ContinuousClock.now
  private var sourceLease: Task<Void, Never>?
  private var leaseEpoch: UInt64 = 0
  private var counters = MetadataReadStatistics()
  private var validationProbe: (@Sendable () throws -> Void)?
  private let wallClock = ImageMetadataReader.formatter("yyyy:MM:dd HH:mm:ss")
  private let offsetClock = ImageMetadataReader.formatter("yyyy:MM:dd HH:mm:ssXXXXX")
  private static func formatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter
  }
  public init(entryLimit: Int = 128, byteLimit: Int = 4 * 1024 * 1024) {
    self.entryLimit = max(0, entryLimit)
    self.byteLimit = max(0, byteLimit)
  }
  deinit { sourceLease?.cancel() }

  public var statistics: MetadataReadStatistics {
    var value = counters
    value.cachedEntries = entries.count
    value.cachedResultBytes = bytes
    value.retainedSources = lastSource == nil ? 0 : 1
    return value
  }
  public func clear() {
    entries.removeAll()
    bytes = 0
    lastSource = nil
    leaseEpoch &+= 1
    sourceLease?.cancel()
    sourceLease = nil
  }
  // Deterministic disposable-file race injection; not part of the public API.
  func setValidationProbe(_ action: (@Sendable () throws -> Void)?) { validationProbe = action }

  private func context(_ file: URL) throws -> (URL, String, Stamp?) {
    try Task.checkCancellation()
    let url = file.standardizedFileURL
    let path = url.path
    let stamp = Stamp.read(url)
    if let entry = entries[path], stamp != entry.stamp { remove(path) }
    if let source = lastSource, source.path == path && stamp != source.stamp { lastSource = nil }
    return (url, path, stamp)
  }
  private func validate(_ url: URL, _ path: String, _ stamp: Stamp?) throws {
    try validationProbe?()
    try Task.checkCancellation()
    if let stamp, Stamp.read(url) != stamp {
      remove(path)
      if lastSource?.path == path { lastSource = nil }
      throw DecisionStoreError.fileChanged
    }
  }
  private func source(_ url: URL, _ path: String, _ stamp: Stamp?) -> CGImageSource? {
    if let stamp, let source = lastSource, source.path == path, source.stamp == stamp,
      ContinuousClock.now < sourceDeadline
    {
      counters.sourceReuses += 1
      sourceDeadline = .now.advanced(by: .seconds(2))
      return source.image
    }
    lastSource = nil
    guard
      let image = CGImageSourceCreateWithURL(
        url as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    counters.sourceCreations += 1
    if let stamp, entryLimit > 0, byteLimit > 0 {
      lastSource = Source(path: path, stamp: stamp, image: image)
      sourceDeadline = .now.advanced(by: .seconds(2))
      startLease()
    }
    return image
  }
  private func startLease() {
    guard sourceLease == nil else { return }
    let epoch = leaseEpoch
    // One weak sleeper for a stream of reads, not one task per photo. Idle
    // release bounds the lifetime of ImageIO's opaque allocations/file handles.
    sourceLease = Task(priority: .background) { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        if await self?.expireSource(epoch) != false { return }
      }
    }
  }
  private func expireSource(_ epoch: UInt64) -> Bool {
    guard epoch == leaseEpoch else { return true }
    guard lastSource == nil || ContinuousClock.now >= sourceDeadline else { return false }
    lastSource = nil
    sourceLease = nil
    return true
  }
  private func remove(_ path: String) {
    if let old = entries.removeValue(forKey: path) { bytes -= old.cost }
  }
  private func store(_ path: String, _ value: Entry) {
    remove(path)
    guard entryLimit > 0, value.cost <= byteLimit else {
      if lastSource?.path == path { lastSource = nil }
      return
    }
    while entries.count >= entryLimit || value.cost > byteLimit - bytes {
      guard let victim = entries.min(by: { $0.value.accessed < $1.value.accessed })?.key else {
        break
      }
      remove(victim)
    }
    var value = value
    access &+= 1
    value.accessed = access
    entries[path] = value
    bytes += value.cost
    if lastSource?.path == path {
      if value.metadata != nil && value.xmpRead {
        lastSource = nil
      } else {
        sourceDeadline = .now.advanced(by: .seconds(2))
      }
    }
  }
  private func touch(_ path: String) {
    access &+= 1
    entries[path]?.accessed = access
  }
  public func embeddedXMP(for file: URL) throws -> Data? {
    let (url, path, stamp) = try context(file)
    if let entry = entries[path], entry.xmpRead {
      try validate(url, path, stamp)
      touch(path)
      counters.xmpHits += 1
      return entry.xmp
    }
    return try autoreleasepool {
      guard let source = source(url, path, stamp) else { return nil }
      counters.xmpReads += 1
      let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
      let data = metadata.flatMap { CGImageMetadataCreateXMPData($0, nil) }.map { $0 as Data }
      try validate(url, path, stamp)
      if let stamp {
        var entry = entries[path] ?? Entry(stamp: stamp)
        entry.xmp = data
        entry.xmpRead = true
        store(path, entry)
      }
      return data
    }
  }
  public func metadata(for file: URL) async throws -> PhotoMetadata {
    let trace = PhotoTrace.begin("ReadEXIF")
    defer { PhotoTrace.end(trace) }
    let (url, path, stamp) = try context(file)
    if let metadata = entries[path]?.metadata {
      try validate(url, path, stamp)
      touch(path)
      counters.exifHits += 1
      return metadata
    }
    return try autoreleasepool {
      guard let source = source(url, path, stamp) else { throw PreviewError.unreadable }
      counters.propertyReads += 1
      guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      else {
        lastSource = nil
        throw PreviewError.unreadable
      }
      let value = try parse(properties)
      try validate(url, path, stamp)
      if let stamp {
        var entry = entries[path] ?? Entry(stamp: stamp)
        entry.metadata = value
        store(path, entry)
      }
      return value
    }
  }
  private func parse(_ p: [CFString: Any]) throws -> PhotoMetadata {
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
