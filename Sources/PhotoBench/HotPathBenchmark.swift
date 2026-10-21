import CoreGraphics
import Foundation
import ImageIO
import PhotoCore
import PhotoImaging
import UniformTypeIdentifiers

/// Synthetic service microbenchmarks; no user library or shared decision database.
struct HotPathBenchmark {
  struct CacheTiming: Encodable {
    let entries: Int
    let hits: Int
    let milliseconds: Double
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let cacheHits: [CacheTiming]
    let metadataReads: Int
    let metadataMilliseconds: Double
    let decisionReads: Int
    let decisionMilliseconds: Double
    let operatingSystem: String
    let logicalCPUCount: Int
    let notes: [String]
  }
  static func run() async throws -> Report {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let context = CGContext(
      data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let image = context.makeImage()!
    let source = scratch.appendingPathComponent("source.jpg")
    let destination = CGImageDestinationCreateWithURL(
      source as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(
      destination, image,
      [
        kCGImagePropertyExifDictionary: [
          kCGImagePropertyExifDateTimeOriginal: "2026:10:20 12:34:56",
          kCGImagePropertyExifOffsetTimeOriginal: "+02:00",
        ]
      ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw PreviewError.unreadable }
    var urls: [URL] = []
    for i in 0..<4096 {
      let url = scratch.appendingPathComponent("Frame\(i).jpg")
      try FileManager.default.copyItem(at: source, to: url)
      urls.append(url)
    }
    var caches: [CacheTiming] = []
    for count in [64, 1024, 4096] {
      let pipeline = ImagePipeline(byteLimit: 24 * 1024 * 1024)
      for url in urls.prefix(count) {
        _ = try await pipeline.preview(for: url, maximumPixelSize: 8)
      }
      let start = ContinuousClock.now
      for i in 0..<10_000 {
        guard await pipeline.cachedPreview(for: urls[i % count], maximumPixelSize: 8) != nil else {
          throw PreviewError.unreadable
        }
      }
      caches.append(CacheTiming(entries: count, hits: 10_000, milliseconds: elapsed(start)))
    }
    let reader = ImageMetadataReader()
    _ = try await reader.metadata(for: source)
    let metadataStart = ContinuousClock.now
    for _ in 0..<1000 { _ = try await reader.metadata(for: source) }
    let metadataTime = elapsed(metadataStart)
    let store = DecisionStore(databaseURL: scratch.appendingPathComponent("decisions.sqlite"))
    _ = try await store.load(for: source)
    let decisionStart = ContinuousClock.now
    for _ in 0..<1000 { _ = try await store.load(for: source) }
    return Report(
      cacheHits: caches, metadataReads: 1000, metadataMilliseconds: metadataTime,
      decisionReads: 1000, decisionMilliseconds: elapsed(decisionStart),
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount,
      notes: [
        "Disposable synthetic 8x8 JPEGs; cache warmed before timing; no user photos or shared database.",
        "Cache loop includes actor calls and URL hashing. Cache population is excluded.",
        "Metadata loop reads one warm JPEG with an offset-bearing EXIF date; not RAW decoder startup.",
        "Decision loop reads one warm JPEG without XMP after its initial durable cache seed.",
        "Single-process microbenchmarks, uncontrolled OS caches; not UI latency or large-shoot acceptance.",
      ])
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    return Double(duration.components.seconds) * 1000
      + Double(duration.components.attoseconds) / 1e15
  }
}
