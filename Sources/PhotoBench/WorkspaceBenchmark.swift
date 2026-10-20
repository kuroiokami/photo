import CryptoKit
import Foundation
import PhotoCore
import PhotoImaging

/// Reads image/sidecar inputs, but confines all database writes to a fresh temporary folder.
/// Measures the actual workspace services; does not import into the user's decision database.
@MainActor
struct WorkspaceBenchmark {
  struct Report: Encodable {
    let schemaVersion = 1
    let fileCount: Int
    let originalsUnchanged: Bool
    let enumerationMilliseconds: Double
    let selectedDecisionMilliseconds: Double
    let firstPreviewDuringIndexingMilliseconds: Double
    let firstPreviewSucceeded: Bool
    let metadataIndexMilliseconds: Double
    let metadataFailures: Int
    let initialDecisionLoadMilliseconds: Double
    let repeatDecisionLoadMilliseconds: Double
    let decisionErrors: Int
    let isoSortMilliseconds: Double
    let ratingSortMilliseconds: Double
    let maximumMainActorGapMilliseconds: Double
    let mainActorSamples: Int
    let operatingSystem: String
    let logicalCPUCount: Int
    let notes: [String]
  }

  static func run(folder: URL) async throws -> Report {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let store = DecisionStore(databaseURL: scratch.appendingPathComponent("decisions.sqlite"))
    let access = LocalPhotoFileAccess()
    let start = ContinuousClock.now
    let urls = try await access.photos(in: folder)
    let enumeration = elapsed(start)
    let before = try await Task.detached { try hashes(urls) }.value
    let state = WorkspaceState(fileAccess: access, decisionStore: store)
    await state.openFolder(folder)
    let heartbeat = Heartbeat()
    let sampling = Task {
      var previous = ContinuousClock.now
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
        heartbeat.maximumGap = max(heartbeat.maximumGap, elapsed(previous))
        heartbeat.samples += 1
        previous = .now
      }
    }
    defer { sampling.cancel() }
    let firstDecisionStart = ContinuousClock.now
    if let first = urls.first { _ = try await store.load(for: first) }
    let selectedDecision = elapsed(firstDecisionStart)
    let indexing = Task {
      let start = ContinuousClock.now
      await state.indexMetadata(using: ImageMetadataReader())
      return elapsed(start)
    }
    let loading = Task {
      let start = ContinuousClock.now
      await state.loadDecisions()
      return elapsed(start)
    }
    let previewStart = ContinuousClock.now
    var previewSucceeded = false
    if let first = urls.first {
      previewSucceeded =
        (try? await ImagePipeline(byteLimit: 64 * 1024 * 1024)
          .preview(for: first, maximumPixelSize: 2560)) != nil
    }
    let firstPreview = elapsed(previewStart)
    let metadataTime = await indexing.value
    let loadTime = await loading.value
    // A fresh workspace forces reads again, using the existing database.
    let reloaded = WorkspaceState(fileAccess: access, decisionStore: store)
    await reloaded.openFolder(folder)
    let repeatStart = ContinuousClock.now
    await reloaded.loadDecisions()
    let repeatTime = elapsed(repeatStart)
    let isoStart = ContinuousClock.now
    await state.setSort(.iso)
    let isoTime = elapsed(isoStart)
    let ratingStart = ContinuousClock.now
    await state.setSort(.rating)
    let ratingTime = elapsed(ratingStart)
    let after = try await Task.detached { try hashes(urls) }.value
    sampling.cancel()
    await sampling.value
    return Report(
      fileCount: urls.count, originalsUnchanged: before == after,
      enumerationMilliseconds: enumeration, selectedDecisionMilliseconds: selectedDecision,
      firstPreviewDuringIndexingMilliseconds: firstPreview, firstPreviewSucceeded: previewSucceeded,
      metadataIndexMilliseconds: metadataTime, metadataFailures: urls.count - state.metadata.count,
      initialDecisionLoadMilliseconds: loadTime, repeatDecisionLoadMilliseconds: repeatTime,
      decisionErrors: state.saveStatus.values.filter { $0 != "Saved" }.count,
      isoSortMilliseconds: isoTime, ratingSortMilliseconds: ratingTime,
      maximumMainActorGapMilliseconds: heartbeat.maximumGap, mainActorSamples: heartbeat.samples,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount,
      notes: [
        "Fresh temporary SQLite database; source folders and sidecars are never written.",
        "Metadata and initial decision indexing run concurrently with the first preview.",
        "Selected decision is read before full indexing; repeat load uses a fresh workspace and the same database.",
        "Maximum main-actor gap samples a nominal 10 ms timer, including scheduler/OS delays; it is not frame time.",
        "All source bytes are hashed before/after. Reports omit names, paths, EXIF values and hashes.",
        "Single process run; uncontrolled filesystem caches; CLI service timings, not native input latency.",
      ])
  }

  private final class Heartbeat {
    var maximumGap = 0.0
    var samples = 0
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
      var hash = SHA256()
      while try autoreleasepool(invoking: {
        guard let data = try file.read(upToCount: 1_048_576), !data.isEmpty else { return false }
        hash.update(data: data)
        return true
      }) {}
      return hash.finalize()
    }
  }
}
