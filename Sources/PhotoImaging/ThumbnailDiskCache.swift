import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import PhotoCore
import UniformTypeIdentifiers

/// Experimental JPEG is opt-in for benchmarks. The app keeps lossless PNG.
public enum ThumbnailDiskEncoding: String, Sendable { case png, jpeg }

/// Best-effort derived data. Publication may block on filesystem work, but
/// reads only take the short admission lock to record bounded recency hints.
public final class ThumbnailDiskCache: @unchecked Sendable {
  public static let standard = ThumbnailDiskCache(
    directory:
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Photo/Thumbnails-v1", isDirectory: true))
  private struct Record: Codable {
    let version: Int
    let source: String
    let width: Int
    let height: Int
    let pixels: Data
    var encoding: String? = nil
  }
  private struct Entry {
    let url: URL
    let size: Int
    var accessed: Date
  }
  private let format: ThumbnailDiskEncoding
  private let directory: URL
  private let limit: Int
  private let lock = NSLock()
  // Separate admission lock: enqueue never waits for disk I/O or PNG encoding.
  private let admission = NSLock()
  let writeQueue = DispatchQueue(label: "Photo.ThumbnailCacheWriter", qos: .utility)
  private let encoder: PropertyListEncoder = {
    let value = PropertyListEncoder()
    value.outputFormat = .binary
    return value
  }()
  private var generation = 0
  private var pending: Set<String> = []
  private var pendingBytes = 0
  private var recentReads: [String: Date] = [:]
  private let recentReadLimit = 512
  private let pendingLimit: Int
  private let encoding = NSLock()
  private var indexed = false
  private var entries: [String: Entry] = [:]
  private var bytes = 0
  public init(
    directory: URL, byteLimit: Int = 512 * 1024 * 1024,
    pendingByteLimit: Int = 32 * 1024 * 1024, encoding: ThumbnailDiskEncoding = .png
  ) {
    self.directory = directory
    format = encoding
    limit = max(0, byteLimit)
    pendingLimit = max(0, pendingByteLimit)
  }

  struct SourceStamp: Sendable {
    let values: [String]
    let key: String
  }
  private func stampValues(for url: URL, size: Int) -> [String]? {
    guard size <= 480 else { return nil }
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
    return [
      format == .png ? "v1" : "v2jpeg", url.standardizedFileURL.path, String(size),
      String(info.st_dev),
      String(info.st_ino), String(info.st_size), String(info.st_mtimespec.tv_sec),
      String(info.st_mtimespec.tv_nsec), String(info.st_ctimespec.tv_sec),
      String(info.st_ctimespec.tv_nsec),
    ]
  }
  func stamp(for url: URL, size: Int) -> SourceStamp? {
    guard let values = stampValues(for: url, size: size) else { return nil }
    let digest = SHA256.hash(data: Data(values.joined(separator: "\u{0}").utf8))
    let hex = Array("0123456789abcdef".utf8)
    let key = String(
      decoding: digest.flatMap { [hex[Int($0 >> 4)], hex[Int($0 & 15)]] }, as: UTF8.self)
    return SourceStamp(values: values, key: key)
  }
  func matches(_ stamp: SourceStamp, file: URL, size: Int) -> Bool {
    stampValues(for: file, size: size) == stamp.values
  }
  func key(for url: URL, size: Int) -> String? { stamp(for: url, size: size)?.key }

  /// Best effort, bounded admission including the active image. No task per rejected write.
  @discardableResult
  func enqueue(_ preview: PhotoPreview, file: URL, size: Int, stamp: SourceStamp) -> Bool {
    let cost = preview.byteCost
    return admission.withLock {
      guard cost <= pendingLimit - pendingBytes, pending.count < 64,
        pending.insert(stamp.key).inserted
      else { return false }
      pendingBytes += cost
      let epoch = generation
      writeQueue.async { [self] in
        defer {
          admission.withLock {
            pending.remove(stamp.key)
            pendingBytes -= cost
          }
        }
        guard admission.withLock({ generation == epoch }), matches(stamp, file: file, size: size)
        else { return }
        store(preview, key: stamp.key, generation: epoch) {
          self.matches(stamp, file: file, size: size)
        }
      }
      return true
    }
  }
  /// Diagnostic/test barrier; browsing and normal termination never wait for derived data.
  public func waitForPendingWrites() async {
    await withCheckedContinuation { continuation in
      writeQueue.async { continuation.resume() }
    }
  }
  func read(_ key: String) -> PhotoPreview? {
    let epoch = admission.withLock { generation }
    let url = directory.appendingPathComponent(key + ".thumb")
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let count = attributes[.size] as? Int, count <= 4 * 1024 * 1024,
      let data = try? Data(contentsOf: url),
      let record = try? PropertyListDecoder().decode(Record.self, from: data),
      record.version == 1 || record.version == 2, record.width > 0, record.height > 0,
      let kind = PreviewSource(rawValue: record.source), kind != .raw,
      let source = CGImageSourceCreateWithData(record.pixels as CFData, nil),
      let type = CGImageSourceGetType(source) as String?,
      (record.version == 1 && record.encoding == nil && type == UTType.png.identifier)
        || (record.version == 2 && record.encoding == "jpeg" && type == UTType.jpeg.identifier),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= 480, height <= 480,
      let image = CGImageSourceCreateImageAtIndex(
        source, 0,
        [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    else { return nil }
    return admission.withLock {
      guard generation == epoch else { return nil }
      if recentReads.count >= recentReadLimit, recentReads[key] == nil,
        let dropped = recentReads.keys.first
      {
        // Hints are approximate, but a full buffer must still admit new reads
        // rather than permanently favoring the first folder visited.
        recentReads.removeValue(forKey: dropped)
      }
      recentReads[key] = .now
      return PhotoPreview(
        image: image, sourceKind: kind,
        originalWidth: record.width, originalHeight: record.height)
    }
  }
  func store(
    _ preview: PhotoPreview, key: String, generation epoch: Int? = nil,
    valid: () -> Bool = { true }
  ) {
    guard preview.sourceKind != .raw, preview.decodedWidth <= 480, preview.decodedHeight <= 480
    else { return }
    let trace = PhotoTrace.begin("ThumbnailCacheWrite")
    defer { PhotoTrace.end(trace) }
    // JPEG is an opt-in experiment for opaque 8-bit RGB thumbnails only.
    // Preserve alpha/high-depth/other color models through the PNG path.
    let opaque = [CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(
      preview.image.alphaInfo)
    let jpeg =
      format == .jpeg && opaque && preview.image.bitsPerComponent == 8
      && preview.image.colorSpace?.model == .rgb
    let pixels = NSMutableData()
    guard
      let writer = CGImageDestinationCreateWithData(
        pixels, (jpeg ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(
      writer, preview.image,
      jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.90] as CFDictionary : nil)
    guard CGImageDestinationFinalize(writer),
      let data = try? encoding.withLock({
        try encoder.encode(
          Record(
            version: jpeg ? 2 : 1,
            source: preview.sourceKind.rawValue, width: preview.originalWidth,
            height: preview.originalHeight, pixels: pixels as Data, encoding: jpeg ? "jpeg" : nil))
      }), data.count <= limit,
      data.count <= 4 * 1024 * 1024
    else { return }
    lock.withLock {
      guard epoch.map({ expected in admission.withLock { generation == expected } }) ?? true,
        valid()
      else { return }
      let files = FileManager.default
      do {
        try files.createDirectory(
          at: directory, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        if !indexed {
          entries.removeAll(keepingCapacity: true)
          bytes = 0
          for url in try files.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
          where owns(url) {
            let values = try url.resourceValues(forKeys: [
              .fileSizeKey, .contentModificationDateKey,
            ])
            let size = values.fileSize ?? 0
            entries[url.deletingPathExtension().lastPathComponent] = Entry(
              url: url, size: size, accessed: values.contentModificationDate ?? .distantPast)
            bytes += size
          }
          indexed = true
        }
        let url = directory.appendingPathComponent(key + ".thumb")
        guard valid() else { return }
        try data.write(to: url, options: .atomic)
        if let old = entries[key] { bytes -= old.size }
        entries[key] = Entry(url: url, size: data.count, accessed: .now)
        bytes += data.count
        // Merge bounded read hints before choosing eviction victims. No reader
        // waits for directory enumeration, atomic publication or deletion.
        let touched = admission.withLock {
          let values = recentReads
          recentReads.removeAll(keepingCapacity: true)
          return values
        }
        for (id, accessed) in touched {
          if let previous = entries[id]?.accessed, accessed > previous {
            entries[id]?.accessed = accessed
          }
        }
        if bytes > limit {
          // Hysteresis avoids rescanning/sorting the entire disk cache per image.
          for (id, entry) in entries.sorted(by: { $0.value.accessed < $1.value.accessed }) {
            do { try files.removeItem(at: entry.url) } catch {
              if files.fileExists(atPath: entry.url.path) { continue }
            }
            entries.removeValue(forKey: id)
            bytes -= entry.size
            if bytes <= limit * 9 / 10 { break }
          }
        }
      } catch {
        // Cache failure must never prevent viewing the original.
      }
    }
  }
  public func clear() {
    lock.withLock {
      admission.withLock {
        generation &+= 1
        recentReads.removeAll(keepingCapacity: true)
      }
      let files = FileManager.default
      for url in (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
        ?? [] where owns(url)
      {
        try? files.removeItem(at: url)
      }
      entries = [:]
      bytes = 0
      indexed = false
    }
  }
  var pendingReadTouchCount: Int { admission.withLock { recentReads.count } }

  private func owns(_ url: URL) -> Bool {
    let name = url.deletingPathExtension().lastPathComponent
    return url.pathExtension == "thumb" && name.count == 64 && name.allSatisfy { $0.isHexDigit }
  }
}
