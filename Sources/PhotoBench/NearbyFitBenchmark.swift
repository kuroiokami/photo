import CryptoKit
import Foundation
import PhotoCore
import PhotoImaging

/// Service navigation with identical simulated dwell, never a UI/FPS benchmark.
enum NearbyFitBenchmark {
  struct Pass: Encodable {
    let preparation: Bool
    let dwellMilliseconds: Int
    let selections: Int
    let readyRAMHits: Int
    let failures: Int
    let firstFitMilliseconds: Double
    let navigation: [Double]
    let sourceDecodes: Int
    let peakActiveLoads: Int
    let maximumCacheMiB: Double
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let fileCount: Int
    let includesSubfolders: Bool
    let passes: [Pass]
    let originalsUnchanged: Bool
    let logicalCPUCount = ProcessInfo.processInfo.activeProcessorCount
    let physicalMemoryGiB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let notes: [String]
  }
  static func run(folder: URL, includingSubfolders: Bool) async throws -> Report {
    let files = Array(
      try await LocalPhotoFileAccess().photos(in: folder, includingSubfolders: includingSubfolders)
        .prefix(8))
    guard files.count >= 2 else { throw PreviewError.unreadable }
    let hashes = try files.map(hash)
    var passes: [Pass] = []
    for dwell in [250, 0] {
      for enabled in [false, true, true, false] {
        passes.append(try await measure(files, enabled: enabled, dwell: dwell))
      }
    }
    var unchanged = true
    for (index, file) in files.enumerated() {
      if try hash(file) != hashes[index] { unchanged = false }
    }
    return Report(
      fileCount: files.count, includesSubfolders: includingSubfolders, passes: passes,
      originalsUnchanged: unchanged,
      notes: [
        "At most eight naturally ordered photos; forward, reverse, then last/first jumps. Initial Fit is separate from later navigation timings.",
        "Current implementation with preparation off/on/on/off for each 250ms and zero-dwell group, in one quiet process. Each pass has a new 64 MiB Fit cache; no thumbnail, disk-cache, full-detail or ingest work.",
        "Preparation waits 150ms after current Fit readiness, requests next/previous sequentially, and owns one additional reserved worker. Cancelled opaque reads retain their slots. Storage eligibility may suppress preparation.",
        "Original hashing warms OS caches; decoder initialization, fixed order and only eight files limit conclusions. RAM-hit checks precede selected service requests; view debounce/rendering and physical input are omitted.",
        "Every selected request succeeds or is counted; optional failures are best-effort and excluded from selected failures. Source-decode counts include optional work; retained cache maximum is not RSS or transient decode memory.",
        "All original image bytes are hashed before/after. Input paths, names, metadata, pixels and digests are omitted. No source sidecar writes.",
      ])
  }
  private static func measure(_ files: [URL], enabled: Bool, dwell: Int) async throws -> Pass {
    let pipeline = ImagePipeline(byteLimit: 64 * 1024 * 1024, preparesNearby: enabled)
    let order =
      Array(files.indices) + Array(files.indices.dropLast().reversed()) + [files.count - 1, 0]
    var timings: [Double] = []
    var hits = 0
    var failures = 0
    var maximumBytes = 0
    var first = 0.0
    for (step, index) in order.enumerated() {
      let start = ContinuousClock.now
      if pipeline.immediateCachedPreview(for: files[index], maximumPixelSize: 2560) != nil {
        hits += 1
      }
      do {
        _ = try await pipeline.preview(
          for: files[index], maximumPixelSize: 2560, priority: .selected)
      } catch { failures += 1 }
      let ready = elapsed(start)
      if step == 0 { first = ready } else { timings.append(ready) }
      let candidates = [index + 1, index - 1].compactMap {
        files.indices.contains($0) ? files[$0] : nil
      }
      let preparation = Task(priority: .background) {
        if enabled {
          await pipeline.prepareNearby(after: files[index], candidates: candidates, sessionID: nil)
        }
      }
      if dwell > 0 { try await Task.sleep(for: .milliseconds(dwell)) }
      preparation.cancel()
      await preparation.value
      maximumBytes = max(maximumBytes, await pipeline.cachedByteCount)
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while await pipeline.schedulingStatistics().activeLoads > 0 {
      guard ContinuousClock.now < deadline else { throw PreviewError.unreadable }
      try await Task.sleep(for: .milliseconds(1))
    }
    let stats = await pipeline.cacheStatistics()
    let schedule = await pipeline.schedulingStatistics()
    return Pass(
      preparation: enabled, dwellMilliseconds: dwell, selections: order.count,
      readyRAMHits: hits, failures: failures, firstFitMilliseconds: first, navigation: timings,
      sourceDecodes: stats.sourceDecodes, peakActiveLoads: schedule.maximumActiveLoads,
      maximumCacheMiB: Double(maximumBytes) / 1024 / 1024)
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    return Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds)
      / 1e15
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
