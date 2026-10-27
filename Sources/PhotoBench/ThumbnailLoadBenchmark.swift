import CryptoKit
import Foundation
import PhotoCore
import PhotoImaging

/// Application-cache-cold viewport bursts; input files are read and hashed only.
enum ThumbnailLoadBenchmark {
  struct Distribution: Encodable {
    let count: Int
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double
    init(_ values: [Double]) {
      let values = values.sorted()
      count = values.count
      p50Milliseconds = values.isEmpty ? 0 : values[values.count / 2]
      p95Milliseconds =
        values.isEmpty ? 0 : values[min(values.count - 1, Int(Double(values.count) * 0.95))]
      maximumMilliseconds = values.last ?? 0
    }
  }
  struct Pass: Encodable {
    let mode: String
    let workers: Int
    let totalMilliseconds: Double
    let viewportReady: Distribution
    let firstPerViewport: Distribution
    let requestCompletion: Distribution
    let selectedFitMilliseconds: Double
    let selectedFitSucceeded: Bool
    let failures: Int
    let sourceDecodes: Int
    let diskHits: Int
    let peakActiveLoads: Int
    let memoryMiB: Double
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let fileCount: Int
    let includesSubfolders: Bool
    let viewportSize = 16
    let thumbnailLongEdge = 480
    let passes: [Pass]
    let originalsUnchanged: Bool
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let logicalCPUCount = ProcessInfo.processInfo.activeProcessorCount
    let physicalMemoryGiB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
    let notes: [String]
  }
  private struct Arrival: Sendable {
    let milliseconds: Double
    let succeeded: Bool
  }
  static func run(folder: URL, includingSubfolders: Bool = false) async throws -> Report {
    let files = Array(
      try await LocalPhotoFileAccess().photos(in: folder, includingSubfolders: includingSubfolders)
        .prefix(48))
    guard !files.isEmpty else { throw PreviewError.unreadable }
    var hashes: [SHA256.Digest] = []
    for file in files { hashes.append(try hash(file)) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let disk = ThumbnailDiskCache(directory: root, byteLimit: 128 * 1024 * 1024)
    var passes: [Pass] = []
    for workers in [1, 2, 2, 1] {
      passes.append(await measure(files, workers: workers, disk: nil))
    }
    // Populate optional disk records outside timing. Drain each viewport to
    // avoid treating intentionally dropped optional writes as read misses.
    let populate = ImagePipeline(byteLimit: 1, thumbnailDiskCache: disk)
    for (index, file) in files.enumerated() {
      _ = try? await populate.preview(for: file, maximumPixelSize: 480)
      if index % 16 == 15 { await disk.waitForPendingWrites() }
    }
    await disk.waitForPendingWrites()
    for workers in [2, 1, 1, 2] {
      passes.append(await measure(files, workers: workers, disk: disk))
    }
    await disk.waitForPendingWrites()
    var unchanged = true
    for (index, file) in files.enumerated() {
      if try hash(file) != hashes[index] { unchanged = false }
    }
    return Report(
      fileCount: files.count, includesSubfolders: includingSubfolders, passes: passes,
      originalsUnchanged: unchanged,
      notes: [
        "At most 48 naturally ordered files, consecutive 16-request viewport bursts; no UI/frame/physical-trackpad timing.",
        "Compare current scheduler with one/two workers, not a historical executable. Source passes use fresh RAM caches and no disk cache; OS caches are warmed by hashing and otherwise uncontrolled.",
        "Source order 1/2/2/1; disk order 2/1/1/2 in one process. New one-byte RAM caches force disk reuse. Failed previews remain counted, including unsupported RAW embedded previews.",
        "One selected 2560-pixel Fit request runs concurrently on its independent serial lane. No full RAW rendering or speculative read-ahead.",
        "Source stamps, post-read validation and bounded optional cache writes remain. Disk population/drain is excluded from timed passes; input names, metadata, pixels and hashes are omitted.",
        "Memory figures are retained thumbnail-cache bytes, not RSS or transient decoder bounds. Original image hashes are verified after all passes.",
      ])
  }
  private static func measure(_ files: [URL], workers: Int, disk: ThumbnailDiskCache?) async -> Pass
  {
    let pipeline = ImagePipeline(
      byteLimit: disk == nil ? 64 * 1024 * 1024 : 1,
      thumbnailDiskCache: disk, maximumConcurrentLoads: workers)
    let fit = ImagePipeline(byteLimit: 64 * 1024 * 1024)
    let start = ContinuousClock.now
    async let selected = fitTime(fit, file: files[0])
    var viewportTimes: [Double] = []
    var first: [Double] = []
    var all: [Double] = []
    var failures = 0
    for offset in stride(from: 0, to: files.count, by: 16) {
      let viewport = Array(files[offset..<min(files.count, offset + 16)])
      let begin = ContinuousClock.now
      var values: [Double] = []
      await withTaskGroup(of: Arrival.self) { group in
        for file in viewport {
          group.addTask {
            do {
              _ = try await pipeline.preview(for: file, maximumPixelSize: 480)
              return Arrival(milliseconds: elapsed(begin), succeeded: true)
            } catch { return Arrival(milliseconds: elapsed(begin), succeeded: false) }
          }
        }
        for await result in group {
          if result.succeeded { values.append(result.milliseconds) } else { failures += 1 }
        }
      }
      if let value = values.min() { first.append(value) }
      all.append(contentsOf: values)
      viewportTimes.append(elapsed(begin))
    }
    let selectedTime = await selected
    let stats = await pipeline.cacheStatistics()
    let schedule = await pipeline.schedulingStatistics()
    return Pass(
      mode: disk == nil ? "source" : "disk", workers: workers,
      totalMilliseconds: elapsed(start), viewportReady: Distribution(viewportTimes),
      firstPerViewport: Distribution(first), requestCompletion: Distribution(all),
      selectedFitMilliseconds: selectedTime.milliseconds,
      selectedFitSucceeded: selectedTime.succeeded,
      failures: failures,
      sourceDecodes: stats.sourceDecodes, diskHits: stats.diskHits,
      peakActiveLoads: schedule.maximumActiveLoads,
      memoryMiB: Double(stats.memoryBytes) / 1024 / 1024)
  }
  private static func fitTime(_ pipeline: ImagePipeline, file: URL) async -> Arrival {
    let start = ContinuousClock.now
    do {
      _ = try await pipeline.preview(for: file, maximumPixelSize: 2560, priority: .selected)
      return Arrival(milliseconds: elapsed(start), succeeded: true)
    } catch { return Arrival(milliseconds: elapsed(start), succeeded: false) }
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let d = start.duration(to: .now)
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
  }
  private static func hash(_ file: URL) throws -> SHA256.Digest {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty {
      hasher.update(data: bytes)
    }
    return hasher.finalize()
  }
}
