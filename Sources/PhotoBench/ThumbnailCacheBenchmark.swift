import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PhotoImaging
import UniformTypeIdentifiers

/// One synthetic 24MP JPEG copied to 115 distinct paths; no personal photos.
struct ThumbnailCacheBenchmark {
  struct Pass: Encodable {
    let label: String
    let budgetMiB: Int
    let firstMilliseconds: Double
    let cacheDrainMilliseconds: Double
    let returnMilliseconds: Double
    let returnSourceDecodes: Int
    let diskHits: Int
    let memoryMiB: Double
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let logicalCPUCount = ProcessInfo.processInfo.activeProcessorCount
    let physicalMemoryGiB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
    let fileCount = 115
    let thumbnailLongEdge = 480
    let passes: [Pass]
    let originalsUnchanged: Bool
    let notes: [String]
  }
  static func run() async throws -> Report {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let context = CGContext(
      data: nil, width: 6000, height: 4000, bitsPerComponent: 8,
      bytesPerRow: 24000, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    for y in stride(from: 0, to: 4000, by: 20) {
      context.setFillColor(CGColor(red: CGFloat(y % 237) / 237, green: 0.4, blue: 0.7, alpha: 1))
      context.fill(CGRect(x: 0, y: y, width: 6000, height: 20))
    }
    let master = root.appendingPathComponent("master.jpg")
    let writer = CGImageDestinationCreateWithURL(
      master as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(writer) else { throw PreviewError.unreadable }
    let hash = SHA256.hash(data: try Data(contentsOf: master))
    var files: [URL] = []
    for i in 0..<115 {
      let file = root.appendingPathComponent("Frame\(i).jpg")
      try FileManager.default.copyItem(at: master, to: file)
      files.append(file)
    }
    var passes: [Pass] = []
    for (label, budget, disk) in [
      ("previous-24MiB-policy", 24 * 1024 * 1024, nil),
      ("adaptive-RAM", ThumbnailCachePolicy.memoryByteLimit(), nil),
      (
        "RAM-and-disk-population", ThumbnailCachePolicy.memoryByteLimit(),
        ThumbnailDiskCache(directory: root.appendingPathComponent("cache"))
      ),
    ] as [(String, Int, ThumbnailDiskCache?)] {
      let pipeline = ImagePipeline(byteLimit: budget, thumbnailDiskCache: disk)
      let start = ContinuousClock.now
      for file in files { _ = try await pipeline.preview(for: file, maximumPixelSize: 480) }
      let first = elapsed(start)
      let drain = ContinuousClock.now
      await disk?.waitForPendingWrites()
      let drainTime = elapsed(drain)
      let before = await pipeline.cacheStatistics()
      let again = ContinuousClock.now
      for file in files { _ = try await pipeline.preview(for: file, maximumPixelSize: 480) }
      let after = await pipeline.cacheStatistics()
      passes.append(
        Pass(
          label: label, budgetMiB: budget / 1024 / 1024, firstMilliseconds: first,
          cacheDrainMilliseconds: drainTime,
          returnMilliseconds: elapsed(again),
          returnSourceDecodes: after.sourceDecodes - before.sourceDecodes,
          diskHits: after.diskHits, memoryMiB: Double(after.memoryBytes) / 1024 / 1024))
    }
    let reopened = ImagePipeline(
      byteLimit: 1,
      thumbnailDiskCache: ThumbnailDiskCache(directory: root.appendingPathComponent("cache")))
    let start = ContinuousClock.now
    for file in files { _ = try await reopened.preview(for: file, maximumPixelSize: 480) }
    let stats = await reopened.cacheStatistics()
    passes.append(
      Pass(
        label: "new-worker-disk-reuse", budgetMiB: 0, firstMilliseconds: elapsed(start),
        cacheDrainMilliseconds: 0,
        returnMilliseconds: 0, returnSourceDecodes: stats.sourceDecodes, diskHits: stats.diskHits,
        memoryMiB: Double(stats.memoryBytes) / 1024 / 1024))
    let unchanged = try files.allSatisfy { SHA256.hash(data: try Data(contentsOf: $0)) == hash }
    return Report(
      passes: passes, originalsUnchanged: unchanged,
      notes: [
        "Synthetic 24MP gradient JPEG copies, 115 unique paths, 480-pixel thumbnails; not real-camera/RAW/UI timing.",
        "Previous policy uses the current implementation with its former 24MiB budget; not a historic binary comparison.",
        "Application caches cold initially; OS caches uncontrolled. Sequential one-process passes. RAM figures are cache bytes, not RSS.",
        "New worker uses a 1-byte RAM budget to force disk reuse. It is not a full application restart. No speculative prefetch.",
      ])
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let d = start.duration(to: .now)
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
  }
}
