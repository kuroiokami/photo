import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import PhotoImaging
import UniformTypeIdentifiers

/// Synthetic cold index maintenance overlapping foreground disk hits.
enum CacheContentionBenchmark {
  struct Distribution: Encodable {
    let count: Int
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double
    init(_ values: [Double]) {
      let values = values.sorted()
      count = values.count
      medianMilliseconds = values.isEmpty ? 0 : values[values.count / 2]
      p95Milliseconds =
        values.isEmpty ? 0 : values[min(values.count - 1, Int(Double(values.count) * 0.95))]
      maximumMilliseconds = values.last ?? 0
    }
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let seededRecords: Int
    let firstViewportMilliseconds: Double
    let contendedReads: Distribution
    let settledReads: Distribution
    let foregroundDiskHits: Int
    let foregroundSourceDecodes: Int
    let maintenanceDrainMilliseconds: Double
    let originalsUnchanged: Bool
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let logicalCPUCount = ProcessInfo.processInfo.activeProcessorCount
    let physicalMemoryGiB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
    let notes: [String]
  }
  static func run() async throws -> Report {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let context = CGContext(
      data: nil, width: 2400, height: 1600, bitsPerComponent: 8,
      bytesPerRow: 9600, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    for y in stride(from: 0, to: 1600, by: 8) {
      context.setFillColor(CGColor(red: CGFloat(y % 233) / 233, green: 0.3, blue: 0.7, alpha: 1))
      context.fill(CGRect(x: 0, y: y, width: 2400, height: 8))
    }
    let master = root.appendingPathComponent("master.jpg")
    let destination = CGImageDestinationCreateWithURL(
      master as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw PreviewError.unreadable }
    let original = try digest(master)
    let files = try (0..<9).map { i in
      let file = root.appendingPathComponent("Frame\(i).jpg")
      try FileManager.default.copyItem(at: master, to: file)
      return file
    }
    let directory = root.appendingPathComponent("cache")
    let population = ThumbnailDiskCache(directory: directory)
    let initial = ImagePipeline(byteLimit: 1, thumbnailDiskCache: population)
    for file in files.prefix(8) { _ = try await initial.preview(for: file, maximumPixelSize: 480) }
    await population.waitForPendingWrites()
    let record = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    ).first!
    for i in 0..<4000 {
      let target = directory.appendingPathComponent(String(format: "%064x.thumb", i))
      guard clonefile(record.path, target.path, 0) == 0 else { throw PreviewError.unreadable }
    }
    let disk = ThumbnailDiskCache(directory: directory)
    let foreground = ImagePipeline(
      byteLimit: 1, thumbnailDiskCache: disk, maximumConcurrentLoads: 2)
    let writer = ImagePipeline(byteLimit: 1, thumbnailDiskCache: disk)
    let begin = ContinuousClock.now
    _ = try await writer.preview(for: files[8], maximumPixelSize: 480)
    var first = 0.0
    var times: [Double] = []
    for _ in 0..<8 {
      let viewport = ContinuousClock.now
      try await withThrowingTaskGroup(of: Double.self) { group in
        for file in files.prefix(8) {
          group.addTask {
            let start = ContinuousClock.now
            _ = try await foreground.preview(for: file, maximumPixelSize: 480)
            return elapsed(start)
          }
        }
        for try await value in group { times.append(value) }
      }
      if first == 0 { first = elapsed(viewport) }
    }
    await disk.waitForPendingWrites()
    let drain = elapsed(begin)
    var settled: [Double] = []
    for file in files.prefix(8) {
      let start = ContinuousClock.now
      _ = try await foreground.preview(for: file, maximumPixelSize: 480)
      settled.append(elapsed(start))
    }
    let stats = await foreground.cacheStatistics()
    let unchanged = try files.allSatisfy { try digest($0) == original }
    return Report(
      seededRecords: 4008, firstViewportMilliseconds: first,
      contendedReads: Distribution(times), settledReads: Distribution(settled),
      foregroundDiskHits: stats.diskHits, foregroundSourceDecodes: stats.sourceDecodes,
      maintenanceDrainMilliseconds: drain, originalsUnchanged: unchanged,
      notes: [
        "Nine synthetic JPEG copies; eight disk-hit foreground photos and one cold writer. 4000 APFS-cloned synthetic derived records force a lazy directory index on the first new write.",
        "Eight bursts of eight requests, two foreground workers and a one-byte RAM budget. First viewport and individual reads include queueing; maintenance drain includes the foreground route before its final writer barrier.",
        "The writer is admitted before reads; scheduling overlap is uncontrolled. Compare quiet fresh processes in baseline/candidate/candidate/baseline order, with identical benchmark code and only cache implementation changed.",
        "Application RAM/index state is fresh; OS caches are warmed by population/cloning and otherwise uncontrolled. This is not physical cold-media, UI/FPS, eviction-throughput or real-shoot timing.",
        "Original bytes are hashed before/after. Source paths, names, metadata, pixels, hashes and raw traces are omitted; no source sidecar writes.",
      ])
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    return Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds)
      / 1e15
  }
  private static func digest(_ file: URL) throws -> SHA256.Digest {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var value = SHA256()
    while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty {
      value.update(data: bytes)
    }
    return value.finalize()
  }
}
