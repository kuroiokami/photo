import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Best-effort derived data. This lock protects index/accounting and atomic file
/// operations across thumbnail workers/windows. Called only off the main actor.
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
  }
  private struct Entry {
    let url: URL
    let size: Int
    var accessed: Date
  }
  private let directory: URL
  private let limit: Int
  private let lock = NSLock()
  private var indexed = false
  private var entries: [String: Entry] = [:]
  private var bytes = 0
  public init(directory: URL, byteLimit: Int = 512 * 1024 * 1024) {
    self.directory = directory
    limit = max(0, byteLimit)
  }

  func key(for url: URL, size: Int) -> String? {
    guard size <= 480 else { return nil }  // Never persist Fit or full-detail images.
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
    let stamp = [
      "v1", url.standardizedFileURL.path, String(size), String(info.st_dev),
      String(info.st_ino), String(info.st_size), String(info.st_mtimespec.tv_sec),
      String(info.st_mtimespec.tv_nsec), String(info.st_ctimespec.tv_sec),
      String(info.st_ctimespec.tv_nsec),
    ]
    .joined(separator: "\u{0}")
    return SHA256.hash(data: Data(stamp.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  func read(_ key: String) -> PhotoPreview? {
    lock.withLock {
      let url = directory.appendingPathComponent(key + ".thumb")
      guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
        let count = attributes[.size] as? Int, count <= 4 * 1024 * 1024,
        let data = try? Data(contentsOf: url),
        let record = try? PropertyListDecoder().decode(Record.self, from: data),
        record.version == 1, record.width > 0, record.height > 0,
        let kind = PreviewSource(rawValue: record.source), kind != .raw,
        let source = CGImageSourceCreateWithData(record.pixels as CFData, nil),
        CGImageSourceGetType(source) as String? == UTType.png.identifier,
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int,
        width > 0, height > 0, width <= 480, height <= 480,
        let image = CGImageSourceCreateImageAtIndex(
          source, 0,
          [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
      else { return nil }
      entries[key]?.accessed = .now
      return PhotoPreview(
        image: image, sourceKind: kind,
        originalWidth: record.width, originalHeight: record.height)
    }
  }
  func store(_ preview: PhotoPreview, key: String) {
    guard preview.sourceKind != .raw, preview.decodedWidth <= 480, preview.decodedHeight <= 480
    else { return }
    // Lossless pixels retain alpha and color profiles; no edits or source EXIF
    // are baked into the cache. This is deliberately thumbnail-sized only.
    let pixels = NSMutableData()
    guard
      let writer = CGImageDestinationCreateWithData(
        pixels, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(writer, preview.image, nil)
    guard CGImageDestinationFinalize(writer),
      let data = try? PropertyListEncoder.binary.encode(
        Record(
          version: 1,
          source: preview.sourceKind.rawValue, width: preview.originalWidth,
          height: preview.originalHeight, pixels: pixels as Data)), data.count <= limit,
      data.count <= 4 * 1024 * 1024
    else { return }
    lock.withLock {
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
        try data.write(to: url, options: .atomic)
        if let old = entries[key] { bytes -= old.size }
        entries[key] = Entry(url: url, size: data.count, accessed: .now)
        bytes += data.count
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
  private func owns(_ url: URL) -> Bool {
    let name = url.deletingPathExtension().lastPathComponent
    return url.pathExtension == "thumb" && name.count == 64 && name.allSatisfy { $0.isHexDigit }
  }
}

extension PropertyListEncoder {
  fileprivate static var binary: PropertyListEncoder {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    return encoder
  }
}
