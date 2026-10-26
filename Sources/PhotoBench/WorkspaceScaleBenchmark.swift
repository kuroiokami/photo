import CryptoKit
import Foundation
import PhotoCore
import PhotoImaging

/// Read-only image work; decisions and cache seeds use a fresh disposable database.
@MainActor
struct WorkspaceScaleBenchmark {
  struct Latency: Encodable {
    let count: Int
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double
    init(_ values: [Double]) {
      let sorted = values.sorted()
      count = sorted.count
      p50Milliseconds = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
      p95Milliseconds =
        sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
      maximumMilliseconds = sorted.last ?? 0
    }
  }
  struct Navigation: Encodable {
    let pattern: String
    let latency: Latency
    let selectionLatency: Latency
    let sourceDecodes: Int
    let selectedIdentityMatches: Bool
  }
  struct Memory: Encodable {
    let phase: String
    let residentMiB: Double
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let fileCount: Int
    let originalsUnchanged: Bool
    let folderOpenMilliseconds: Double
    let firstFitDuringIndexingMilliseconds: Double
    let selectedReadyDuringIndexingMilliseconds: Double
    let metadataIndexMilliseconds: Double
    let decisionIndexMilliseconds: Double
    let metadataPublications: Int
    let decisionPublications: Int
    let metadataFailures: Int
    let decisionErrors: Int
    let navigation: [Navigation]
    let cachedFit: Latency
    let selectAllMilliseconds: Double
    let selectedFileCount: Int
    let isoSortMilliseconds: Double
    let ratingSortMilliseconds: Double
    let pickFilterMilliseconds: Double
    let maximumMainActorGapMilliseconds: Double
    let mainActorSamples: Int
    let sampledPeakResidentMiB: Double
    let memory: [Memory]
    let fitCacheMiB: Double
    let operatingSystem: String
    let notes: [String]
  }
  private actor MemorySampler {
    var peak: UInt64 = 0
    func sample() { peak = max(peak, residentBytes()) }
  }
  private final class Heartbeat {
    var maximum = 0.0
    var samples = 0
  }
  static func run(folder: URL) async throws -> Report {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let access = LocalPhotoFileAccess()
    let urls = try await access.photos(in: folder)
    guard !urls.isEmpty, urls.count <= 40_000 else { throw CocoaError(.fileReadUnknown) }
    let original = try await Task.detached { try hashes(urls) }.value
    let sampler = MemorySampler()
    let sampling = Task.detached {
      while !Task.isCancelled {
        await sampler.sample()
        do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
      }
    }
    defer { sampling.cancel() }
    let heartbeat = Heartbeat()
    let beats = Task {
      var previous = ContinuousClock.now
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
        heartbeat.maximum = max(heartbeat.maximum, elapsed(previous))
        heartbeat.samples += 1
        previous = .now
      }
    }
    defer { beats.cancel() }
    var memory: [Memory] = []
    func checkpoint(_ phase: String) async {
      memory.append(Memory(phase: phase, residentMiB: Double(residentBytes()) / 1_048_576))
      await sampler.sample()
    }
    await checkpoint("before-workspace")
    let store = DecisionStore(databaseURL: scratch.appendingPathComponent("decisions.sqlite"))
    let state = WorkspaceState(photos: [], fileAccess: access, decisionStore: store)
    let opening = ContinuousClock.now
    await state.openFolder(folder)
    let openTime = elapsed(opening)
    guard state.photos.count == urls.count else { throw CocoaError(.fileReadUnknown) }
    await checkpoint("folder-open")
    let start = ContinuousClock.now
    let metadata = Task {
      let start = ContinuousClock.now
      await state.indexMetadata(using: ImageMetadataReader())
      return elapsed(start)
    }
    let decisions = Task {
      let start = ContinuousClock.now
      await state.loadDecisions()
      return elapsed(start)
    }
    let ready = Task {
      while !state.decisionSelectionReady {
        guard elapsed(start) < 120_000 else { throw CocoaError(.fileReadUnknown) }
        try await Task.sleep(for: .milliseconds(1))
      }
      return elapsed(start)
    }
    defer {
      metadata.cancel()
      decisions.cancel()
      ready.cancel()
    }
    let previews = ImagePipeline(byteLimit: 64 * 1024 * 1024)
    let first = ContinuousClock.now
    _ = try await previews.preview(for: urls[0], maximumPixelSize: 2560, sessionID: state.sessionID)
    let firstTime = elapsed(first)
    await checkpoint("first-fit")
    let readyTime = try await ready.value
    let metadataTime = await metadata.value
    let decisionTime = await decisions.value
    await checkpoint("indexed")
    let items = state.photos
    let sequential = Array(0..<min(64, items.count))
    let random = (0..<64).map { ($0 * 7919 + 17) % items.count }
    var navigation: [Navigation] = []
    for (pattern, indices) in [
      ("forward", sequential), ("reverse", sequential.reversed().map { $0 }), ("spread", random),
    ] {
      var times: [Double] = []
      var selectionTimes: [Double] = []
      var identityMatches = true
      let before = await previews.cacheStatistics()
      for index in indices {
        let photo = items[index]
        let beginning = ContinuousClock.now
        state.select(photo.id)
        selectionTimes.append(elapsed(beginning))
        _ = try await previews.preview(
          for: photo.fileURL!, maximumPixelSize: 2560, sessionID: state.sessionID)
        times.append(elapsed(beginning))
        identityMatches =
          identityMatches && state.selectedID == photo.id && state.decisionSelectionReady
      }
      let after = await previews.cacheStatistics()
      navigation.append(
        Navigation(
          pattern: pattern, latency: Latency(times), selectionLatency: Latency(selectionTimes),
          sourceDecodes: after.sourceDecodes - before.sourceDecodes,
          selectedIdentityMatches: identityMatches))
    }
    var cached: [Double] = []
    if let url = state.selectedPhoto?.fileURL {
      for _ in 0..<100 {
        let beginning = ContinuousClock.now
        _ = try await previews.preview(for: url, maximumPixelSize: 2560, sessionID: state.sessionID)
        cached.append(elapsed(beginning))
      }
    }
    await checkpoint("navigated")
    let selection = ContinuousClock.now
    state.selectAllVisible()
    let selectionTime = elapsed(selection)
    let count = state.selectionSummary.fileCount
    await checkpoint("all-selected")
    let isoStart = ContinuousClock.now
    await state.setSort(.iso)
    let isoTime = elapsed(isoStart)
    let ratingStart = ContinuousClock.now
    await state.setSort(.rating)
    let ratingTime = elapsed(ratingStart)
    let filterStart = ContinuousClock.now
    state.setFilter(.pick, minimumRating: 0)
    let filterTime = elapsed(filterStart)
    state.setFilter(.all, minimumRating: 0)
    await checkpoint("filtered-and-sorted")
    beats.cancel()
    await beats.value
    await sampler.sample()
    sampling.cancel()
    await sampling.value
    let after = try await Task.detached { try hashes(urls) }.value
    return Report(
      fileCount: urls.count, originalsUnchanged: original == after,
      folderOpenMilliseconds: openTime, firstFitDuringIndexingMilliseconds: firstTime,
      selectedReadyDuringIndexingMilliseconds: readyTime, metadataIndexMilliseconds: metadataTime,
      decisionIndexMilliseconds: decisionTime,
      metadataPublications: state.publicationMetrics.metadata,
      decisionPublications: state.publicationMetrics.decisions,
      metadataFailures: urls.count - state.metadata.count,
      decisionErrors: state.saveStatus.values.filter { $0 != "Saved" }.count,
      navigation: navigation, cachedFit: Latency(cached), selectAllMilliseconds: selectionTime,
      selectedFileCount: count, isoSortMilliseconds: isoTime, ratingSortMilliseconds: ratingTime,
      pickFilterMilliseconds: filterTime, maximumMainActorGapMilliseconds: heartbeat.maximum,
      mainActorSamples: heartbeat.samples,
      sampledPeakResidentMiB: Double(await sampler.peak) / 1_048_576,
      memory: memory, fitCacheMiB: Double(await previews.cachedByteCount) / 1_048_576,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      notes: [
        "Fresh process recommended per run; temporary SQLite database, unchanged FULL durability, no image/sidecar writes or shared thumbnail disk cache.",
        "All input image bytes hashed before/after outside timing/sampling. OS caches are warmed by hashing; cold means new process/database, not cold physical storage.",
        "Folder-open repeats inventory after validation/hashing. Timings include actual workspace model and per-photo display records.",
        "First Fit and selected readiness overlap full EXIF/decision indexing; readiness polls at 1ms, not native keyboard-to-display time.",
        "Navigation uses model selection and the Fit pipeline at 2560px, with a 64MiB RAM cache. Forward/reverse/spread do not guarantee cache hits; decode counts are reported.",
        "No SwiftUI rendering, thumbnail-grid loading, 35ms view debounce, presented frames, full RAW detail or bulk save/XMP throughput in this service report.",
        "Preflight inventory/byte hashing runs before the first RSS checkpoint; its retained input URLs coexist with the workspace inventory. Baseline/helper allocations are included, so service RSS is not native Photo RSS.",
        "Process RSS sampled about every 10ms plus phase checkpoints; includes runtime/allocator/decoder/model memory, not a whole-app peak bound. The heartbeat is not frame time.",
        "ISO/rating sorts have tied synthetic values when generated gradients have no EXIF/ratings. Pick filtering may remove all files; this is not diverse-metadata sorting acceptance.",
      ])
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    return Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds)
      / 1e15
  }
  private nonisolated static func hashes(_ urls: [URL]) throws -> [SHA256.Digest] {
    try urls.map { url in
      let file = try FileHandle(forReadingFrom: url)
      defer { try? file.close() }
      var digest = SHA256()
      while try autoreleasepool(invoking: {
        guard let data = try file.read(upToCount: 1_048_576), !data.isEmpty else { return false }
        digest.update(data: data)
        return true
      }) {}
      return digest.finalize()
    }
  }
}
