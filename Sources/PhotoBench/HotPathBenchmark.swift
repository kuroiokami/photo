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
    let schemaVersion = 2
    let cacheHits: [CacheTiming]
    let metadataReads: Int
    let metadataMilliseconds: Double
    let decisionReads: Int
    let decisionMilliseconds: Double
    let coldDecisionCount: Int
    let coldIndividualMilliseconds: Double
    let coldBatchedMilliseconds: Double
    let sort: SortTiming
    let readiness: ReadinessTiming
    let originalsUnchanged: Bool
    let operatingSystem: String
    let logicalCPUCount: Int
    let notes: [String]
  }
  struct SortTiming: Encodable {
    let photos = 40_000
    let repetitions = 5
    let nativeMilliseconds: Double
    let rankBuildMilliseconds: Double
    let rankedMilliseconds: Double
    let identicalOrder: Bool
  }
  struct ReadinessTiming: Encodable {
    let selectedFiles = 10_000
    let queries = 10_000
    let milliseconds: Double
    let selectionEvaluations: Int
  }
  private static func sortTiming() -> SortTiming {
    let photos = (0..<40_000).map { index in
      let number = index * 7919 % 40_000
      return PhotoItem(id: String(number), filename: "Frame\(number).jpg", resourceName: "")
    }
    let start = ContinuousClock.now
    var native: [PhotoItem] = []
    for _ in 0..<5 { native = PhotoSort.rating.ordered(photos, metadata: [:]) }
    let nativeTime = elapsed(start)
    let building = ContinuousClock.now
    let ranks = PhotoSort.filenameRanks(for: photos)
    let buildTime = elapsed(building)
    let rankedStart = ContinuousClock.now
    var ranked: [PhotoItem] = []
    for _ in 0..<5 {
      ranked = PhotoSort.rating.ordered(photos, metadata: [:], filenameRanks: ranks)
    }
    return SortTiming(
      nativeMilliseconds: nativeTime, rankBuildMilliseconds: buildTime,
      rankedMilliseconds: elapsed(rankedStart), identicalOrder: native.map(\.id) == ranked.map(\.id)
    )
  }
  @MainActor private static func readinessTiming() async -> ReadinessTiming {
    let photos = (0..<10_000).map {
      PhotoItem(id: String($0), filename: "Frame\($0).jpg", resourceName: "")
    }
    let state = WorkspaceState(photos: photos)
    await state.loadDecisions()
    state.selectAllVisible()
    let before = state.selectionReadinessEvaluations
    let start = ContinuousClock.now
    for _ in 0..<10_000 { precondition(state.decisionSelectionReady) }
    return ReadinessTiming(
      milliseconds: elapsed(start),
      selectionEvaluations: state.selectionReadinessEvaluations - before)
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
    let decisionTime = elapsed(decisionStart)
    let individual = DecisionStore(databaseURL: scratch.appendingPathComponent("individual.sqlite"))
    let batched = DecisionStore(databaseURL: scratch.appendingPathComponent("batched.sqlite"))
    _ = try await individual.load(for: source)
    _ = try await batched.load(for: source)
    let cold = Array(urls.prefix(1000))
    let individualStart = ContinuousClock.now
    for file in cold { _ = try await individual.loadImageState(for: file) }
    let individualTime = elapsed(individualStart)
    let batchStart = ContinuousClock.now
    for result in try await batched.loadImageStates(for: cold) { _ = try result.get() }
    let batchTime = elapsed(batchStart)
    let sort = sortTiming()
    let readiness = await readinessTiming()
    let original = try Data(contentsOf: source)
    let unchanged = try urls.allSatisfy { try Data(contentsOf: $0) == original }
    return Report(
      cacheHits: caches, metadataReads: 1000, metadataMilliseconds: metadataTime,
      decisionReads: 1000, decisionMilliseconds: decisionTime,
      coldDecisionCount: cold.count, coldIndividualMilliseconds: individualTime,
      coldBatchedMilliseconds: batchTime, sort: sort, readiness: readiness,
      originalsUnchanged: unchanged,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount,
      notes: [
        "Disposable synthetic 8x8 JPEGs; cache warmed before timing; no user photos or shared database.",
        "Cache loop includes actor calls and URL hashing. Cache population is excluded.",
        "Metadata loop reads one warm JPEG with an offset-bearing EXIF date; not RAW decoder startup.",
        "Decision loop reads one warm JPEG without XMP after its initial durable cache seed.",
        "Cold decision indexing compares individual loads with batches of 16 on fresh databases; FULL durability retained. No XMP writes or bulk flag-save benchmark.",
        "40k synthetic filenames: five rating sorts with all ratings tied, native versus reusable native-order ranks; rank construction reported separately.",
        "Readiness: 10k sample selections, 10k readiness queries on main actor, including first cache construction; no SwiftUI frame measurement.",
        "Single-process microbenchmarks, uncontrolled OS caches; not UI latency or large-shoot acceptance.",
      ])
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    return Double(duration.components.seconds) * 1000
      + Double(duration.components.attoseconds) / 1e15
  }
}
