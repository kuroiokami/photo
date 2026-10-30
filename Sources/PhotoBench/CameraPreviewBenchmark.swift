import Darwin
import Foundation
import PhotoCore
import PhotoImaging

/// Explicit read-only corpus, anonymous results. Never writes previews/sidecars.
enum CameraPreviewBenchmark {
  struct Result: Encodable {
    let format: String
    let source: String?
    let width: Int?
    let height: Int?
    let decodedBytes: Int?
    let milliseconds: [Double]
    let failures: Int
    let peakWorkerResidentMiB: Double
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let originalsUnchanged: Bool
    let results: [Result]
    let peakResidentMiB: Double
    let retainedCameraPreviewBytesAfterRequests: Int
    let operatingSystem: String
    let notes = [
      "Three sequential on-demand camera-preview requests per file; one serial detail worker, no detail cache. Source hashing warms filesystem caches.",
      "Camera JPEG means verified embedded color JPEG bytes, not rendered RAW. Embedded preview is the conservative ImageIO fallback, capped at 4096 pixels; neither claims sensor-resolution RAW inspection.",
      "Decoded bytes bound the returned image. Parent and fresh-worker RSS are reported separately, include framework/transient allocations and shared pages, and must not be summed as unique physical memory. No whole-process 256 MiB guarantee.",
      "The parent service loop reads image metadata, not every mapped pixel. Display/pixel access faults shared pages into the parent; this RSS is not the displayed app footprint.",
      "No original names, paths, metadata values or pixels in output. These are service timings, not native input/frame latency or photographic quality equivalence.",
    ]
  }
  private struct Sample {
    let source: String
    let width: Int
    let height: Int
    let bytes: Int
    let milliseconds: Double
    let workerPeak: Double
  }
  private static func sample(_ worker: DetailPipeline, _ file: URL) async throws -> Sample {
    let start = ContinuousClock.now
    let image = try await worker.detail(for: file, source: .cameraPreview)
    let duration = start.duration(to: .now)
    return Sample(
      source: image.sourceKind.rawValue, width: image.decodedWidth,
      height: image.decodedHeight, bytes: image.byteCost,
      milliseconds: Double(duration.components.seconds) * 1000 + Double(
        duration.components.attoseconds) / 1e15,
      workerPeak: Double(image.workerPeakResidentBytes ?? 0) / 1_048_576)
  }
  static func run(folder: URL, recursive: Bool) async throws -> Report {
    let enumerator = FileManager.default.enumerator(
      at: folder, includingPropertiesForKeys: [.isRegularFileKey],
      options: recursive
        ? [.skipsHiddenFiles, .skipsPackageDescendants]
        : [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
    var files: [URL] = []
    while let url = enumerator?.nextObject() as? URL {
      if PhotoFormats.isRaw(url),
        try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
      {
        files.append(url)
      }
    }
    files.sort { $0.path < $1.path }
    guard !files.isEmpty else { throw PreviewError.unreadable }
    let before = try files.map { file in try autoreleasepool { try MediaOperations.checksum(file) }
    }
    let worker = DetailPipeline()
    var results: [Result] = []
    for file in files {
      var times: [Double] = []
      var failures = 0
      var workerPeak = 0.0
      var source: String?
      var width: Int?
      var height: Int?
      var bytes: Int?
      for _ in 0..<3 {
        do {
          let value = try await sample(worker, file)
          times.append(value.milliseconds)
          source = value.source
          width = value.width
          height = value.height
          bytes = value.bytes
          workerPeak = max(workerPeak, value.workerPeak)
        } catch { failures += 1 }

      }
      results.append(
        Result(
          format: file.pathExtension.lowercased(), source: source, width: width,
          height: height, decodedBytes: bytes, milliseconds: times, failures: failures,
          peakWorkerResidentMiB: workerPeak))
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Report(
      originalsUnchanged: try files.map { file in
        try autoreleasepool { try MediaOperations.checksum(file) }
      } == before,
      results: results, peakResidentMiB: Double(usage.ru_maxrss) / 1_048_576,
      retainedCameraPreviewBytesAfterRequests: DetailPipeline.retainedCameraPreviewBytes,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString)
  }
}
