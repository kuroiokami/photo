import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import PhotoCore
import PhotoImaging
import UniformTypeIdentifiers

private struct Timing: Codable {
  let count: Int
  let p50Milliseconds: Double
  let p95Milliseconds: Double
  let maximumMilliseconds: Double

  init(_ values: [Double]) {
    let sorted = values.sorted()
    count = sorted.count
    p50Milliseconds = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, sorted.count / 2)]
    p95Milliseconds =
      sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    maximumMilliseconds = sorted.last ?? 0
  }
}

private func milliseconds(_ duration: Duration) -> Double {
  Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

func residentBytes() -> UInt64 {
  var info = mach_task_basic_info()
  var count = mach_msg_type_number_t(
    MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
    }
  }
  return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}

private actor MemorySamples {
  var peak: UInt64 = 0
  func sample() { peak = max(peak, residentBytes()) }
}

private struct Report: Codable {
  let schemaVersion: Int
  let fileCount: Int
  let decodedFileCount: Int
  let totalSourceBytes: Int
  let minimumLongEdge: Int
  let maximumLongEdge: Int
  let imageFailures: Int
  let originalsUnchanged: Bool
  let enumeration: Timing
  let thumbnails: Timing
  let previews: Timing
  let cachedPreviews: Timing
  let concurrentSameImageMilliseconds: Double
  let rapidSelection: Timing
  let virtualCollectionCount: Int
  let folderSwitching: Timing
  let peakResidentMiB: Double
  let finalResidentMiB: Double
  let thumbnailCacheMiB: Double
  let previewCacheMiB: Double
  let operatingSystem: String
  let logicalCPUCount: Int
  let physicalMemoryGiB: Double
  let notes: [String]
}

@main
private struct PhotoBench {
  static func main() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if ["--scale", "--scale-tree"].contains(arguments.first ?? ""), arguments.count == 2 {
      let report = try await WorkspaceScaleBenchmark.run(
        folder: URL(fileURLWithPath: arguments[1]),
        includingSubfolders: arguments[0] == "--scale-tree")
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(report), as: UTF8.self))
      return
    }
    if arguments.first == "--generate-scale", arguments.count == 3 {
      guard let count = Int(arguments[2]), (1...40_000).contains(count) else { exit(2) }
      try generate(at: URL(fileURLWithPath: arguments[1]), count: count, cloned: true)
      print("Generated synthetic JPEG/PNG clones with separate file identities.")
      return
    }
    if arguments == ["--selection-summary"] {
      let report = await SelectionSummaryBenchmark.run()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(report), as: UTF8.self))
      return
    }
    if arguments == ["--sqlite-statements"] {
      let report = try await SQLiteStatementBenchmark.run()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(report), as: UTF8.self))
      return
    }
    if arguments == ["--ingest-journal"] {
      let report = try await IngestJournalBenchmark.run()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(report), as: UTF8.self))
      return
    }
    if ["--nearby-fit", "--nearby-fit-tree"].contains(arguments.first ?? ""), arguments.count == 2 {
      do {
        let report = try await NearbyFitBenchmark.run(
          folder: URL(fileURLWithPath: arguments[1]),
          includingSubfolders: arguments[0] == "--nearby-fit-tree")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
      } catch {
        FileHandle.standardError.write(
          Data("Nearby-Fit benchmark could not run: \(error.localizedDescription)\n".utf8))
        exit(2)
      }
      return
    }
    if ["--thumbnail-loads", "--thumbnail-loads-tree"].contains(arguments.first ?? ""),
      arguments.count == 2
    {
      do {
        let report = try await ThumbnailLoadBenchmark.run(
          folder: URL(fileURLWithPath: arguments[1]),
          includingSubfolders: arguments[0] == "--thumbnail-loads-tree")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
      } catch {
        FileHandle.standardError.write(
          Data("Thumbnail-load benchmark could not run: \(error.localizedDescription)\n".utf8))
        exit(2)
      }
      return
    }
    if arguments == ["--thumbnail-cache"] {
      let report = try await ThumbnailCacheBenchmark.run()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(report), as: UTF8.self))
      return
    }
    if arguments == ["--hot-paths"] {
      let report = try await HotPathBenchmark.run()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(report), as: UTF8.self))
      return
    }
    if arguments.first == "--generate", arguments.count >= 2 {
      let count = arguments.count >= 3 ? Int(arguments[2]) ?? 2000 : 2000
      try generate(at: URL(fileURLWithPath: arguments[1]), count: max(1, min(count, 10_000)))
      print("Generated synthetic JPEG/PNG corpus.")
      return
    }
    if arguments.first == "--detail",
      arguments.count == 2 || (arguments.count == 3 && arguments[2] == "--baseline")
    {
      let report = try await DetailBenchmark.run(
        folder: URL(fileURLWithPath: arguments[1]), baseline: arguments.count == 3)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(report), as: UTF8.self))
      return
    }
    if ["--workspace", "--workspace-ingest"].contains(arguments.first ?? ""), arguments.count == 2 {
      let report = try await WorkspaceBenchmark.run(
        folder: URL(fileURLWithPath: arguments[1]),
        concurrentIngest: arguments.first == "--workspace-ingest")
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(report), as: UTF8.self))
      return
    }
    guard arguments.first == "--folder", arguments.count == 2 else {
      print("Usage: PhotoBench --folder /path/to/folder > report.json")
      print("       PhotoBench --detail /path/to/folder [--baseline] > detail-report.json")
      print("       PhotoBench --generate /new/temp/folder [count]")
      print("       PhotoBench --workspace /path/to/folder > workspace-report.json")
      print("       PhotoBench --workspace-ingest /path/to/folder > workspace-ingest-report.json")
      print("       PhotoBench --hot-paths > hot-path-report.json")
      print("       PhotoBench --thumbnail-cache > thumbnail-cache-report.json")
      print("       PhotoBench --nearby-fit /path/to/folder > nearby-fit-report.json")
      print("       PhotoBench --nearby-fit-tree /path/to/shoot > nearby-fit-report.json")
      print("       PhotoBench --thumbnail-loads /path/to/folder > thumbnail-loads-report.json")
      print("       PhotoBench --thumbnail-loads-tree /path/to/shoot > thumbnail-loads-report.json")
      print("       PhotoBench --ingest-journal > ingest-journal-report.json")
      print("       PhotoBench --sqlite-statements > sqlite-statements-report.json")
      print("       PhotoBench --selection-summary > selection-summary-report.json")
      print(
        "       PhotoBench --generate-scale /new/temp/folder count [1...40000; requires file cloning]"
      )
      print("       PhotoBench --scale /path/to/folder > scale-report.json")
      print("       PhotoBench --scale-tree /path/to/shoot > tree-report.json")
      if arguments != ["--help"] { exit(2) }
      return
    }
    let folder = URL(fileURLWithPath: arguments[1])
    let report = try await run(folder: folder)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
  }

  @MainActor
  private static func run(folder: URL) async throws -> Report {
    let memory = MemorySamples()
    let sampling = Task.detached {
      while !Task.isCancelled {
        await memory.sample()
        try? await Task.sleep(for: .milliseconds(10))
      }
    }
    defer { sampling.cancel() }
    let access = LocalPhotoFileAccess()
    var enumeration: [Double] = []
    var urls: [URL] = []
    for _ in 0..<5 {
      let start = ContinuousClock.now
      urls = try await access.photos(in: folder)
      enumeration.append(milliseconds(start.duration(to: .now)))
    }
    let allURLs = urls
    let selected = Array(urls.prefix(64))
    let before = try await Task.detached { try fingerprints(allURLs) }.value
    let thumbnails = ImagePipeline(byteLimit: 24 * 1024 * 1024)
    let previews = ImagePipeline(byteLimit: 64 * 1024 * 1024)
    var thumbTimes: [Double] = []
    var previewTimes: [Double] = []
    var dimensions: [Int] = []
    var failures = 0
    // Emulate visible grid batches; decoding itself remains on its actor lane.
    for url in selected {
      let start = ContinuousClock.now
      do {
        let image = try await thumbnails.preview(for: url, maximumPixelSize: 480)
        dimensions.append(max(image.originalWidth, image.originalHeight))
        thumbTimes.append(milliseconds(start.duration(to: .now)))
      } catch { failures += 1 }
    }
    for url in selected {
      let start = ContinuousClock.now
      do {
        _ = try await previews.preview(for: url, maximumPixelSize: 2560)
        previewTimes.append(milliseconds(start.duration(to: .now)))
      } catch { failures += 1 }
    }
    var warm: [Double] = []
    let warmPipeline = ImagePipeline(byteLimit: 64 * 1024 * 1024)
    if let url = selected.first {
      _ = try? await warmPipeline.preview(for: url, maximumPixelSize: 2560)
      for _ in 0..<30 {
        let start = ContinuousClock.now
        _ = try? await warmPipeline.preview(for: url, maximumPixelSize: 2560)
        warm.append(milliseconds(start.duration(to: .now)))
      }
    }
    var concurrentMilliseconds = 0.0
    if let url = selected.first {
      let pipeline = ImagePipeline(byteLimit: 64 * 1024 * 1024)
      let start = ContinuousClock.now
      await withTaskGroup(of: Void.self) { group in
        for _ in 0..<8 {
          group.addTask { _ = try? await pipeline.preview(for: url, maximumPixelSize: 2560) }
        }
      }
      concurrentMilliseconds = milliseconds(start.duration(to: .now))
    }
    let virtualCount = 50_000
    let models = await Task.detached {
      (0..<virtualCount).map {
        PhotoItem(fileURL: URL(fileURLWithPath: "/benchmark/Photo\($0).JPG"))
      }
    }.value
    let workspace = WorkspaceState(photos: models)
    var selection: [Double] = []
    for index in 0..<500 {
      let id = models[virtualCount - 1 - index % 100].id
      let start = ContinuousClock.now
      workspace.select(id)
      _ = workspace.selectedPhoto
      _ = workspace.selectedIndex
      selection.append(milliseconds(start.duration(to: .now)))
      await Task.yield()
    }
    let folderWorkspace = WorkspaceState()
    var switches: [Double] = []
    for _ in 0..<10 {
      let start = ContinuousClock.now
      await folderWorkspace.openFolder(folder)
      switches.append(milliseconds(start.duration(to: .now)))
      folderWorkspace.showSamples()
    }
    let after = try await Task.detached { try fingerprints(allURLs) }.value
    await memory.sample()
    let totalBytes = try await Task.detached {
      try allURLs.reduce(0) { result, url in
        result + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
      }
    }.value
    return Report(
      schemaVersion: 1, fileCount: urls.count, decodedFileCount: selected.count,
      totalSourceBytes: totalBytes, minimumLongEdge: dimensions.min() ?? 0,
      maximumLongEdge: dimensions.max() ?? 0, imageFailures: failures,
      originalsUnchanged: before == after, enumeration: Timing(enumeration),
      thumbnails: Timing(thumbTimes), previews: Timing(previewTimes), cachedPreviews: Timing(warm),
      concurrentSameImageMilliseconds: concurrentMilliseconds, rapidSelection: Timing(selection),
      virtualCollectionCount: virtualCount, folderSwitching: Timing(switches),
      peakResidentMiB: Double(await memory.peak) / 1_048_576,
      finalResidentMiB: Double(residentBytes()) / 1_048_576,
      thumbnailCacheMiB: Double(await thumbnails.cachedByteCount) / 1_048_576,
      previewCacheMiB: Double(await previews.cachedByteCount) / 1_048_576,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount,
      physicalMemoryGiB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
      notes: [
        "Pipeline-cold timings; OS filesystem caches are uncontrolled.",
        "At most 64 files decoded; hashes cover all enumerated files.",
        "RSS sampled at 10 ms in this CLI process, not total UI app memory.",
        "Selection timing uses a virtual 50,000-item collection, not real input event latency.",
        "Reports contain aggregate statistics only, with no filenames, paths, hashes, EXIF, or photo content.",
      ])
  }

  private static func fingerprints(_ urls: [URL]) throws -> [SHA256.Digest] {
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

  private static func generate(at directory: URL, count: Int, cloned: Bool = false) throws {
    // Never add benchmark data to an existing directory or a user's library.
    guard !FileManager.default.fileExists(atPath: directory.path) else {
      throw CocoaError(.fileWriteFileExists)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let space = CGColorSpaceCreateDeviceRGB()
    let configurations = [
      (2400, 1600, UTType.jpeg), (1200, 1800, UTType.jpeg), (1536, 1024, UTType.png),
    ]
    var templates: [Data] = []
    for (width, height, type) in configurations {
      guard
        let context = CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
        let gradient = CGGradient(
          colorsSpace: space,
          colors: [
            CGColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1),
            CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1),
          ] as CFArray,
          locations: nil)
      else { throw PreviewError.unreadable }
      context.drawLinearGradient(
        gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
      guard let image = context.makeImage() else { throw PreviewError.unreadable }
      let data = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          data, type.identifier as CFString, 1, nil)
      else { throw PreviewError.unreadable }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { throw PreviewError.unreadable }
      templates.append(data as Data)
    }
    let seeds = directory.appendingPathComponent(".seeds")
    if cloned {
      try FileManager.default.createDirectory(at: seeds, withIntermediateDirectories: false)
      for (index, data) in templates.enumerated() {
        try data.write(
          to: seeds.appendingPathComponent(String(index)), options: .withoutOverwriting)
      }
    }
    let extensions = ["jpg", "JPG", "jpeg", "JPEG", "JpEg", "jPeG"]
    for index in 0..<count {
      let slot = index % 3
      let ext = slot == 2 ? (index % 2 == 0 ? "PNG" : "png") : extensions[index % extensions.count]
      let name = String(format: "café-Photo%05d.%@", index, ext)
      if cloned {
        guard
          clonefile(
            seeds.appendingPathComponent(String(slot)).path,
            directory.appendingPathComponent(name).path, 0) == 0
        else {
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
      } else {
        try templates[slot].write(
          to: directory.appendingPathComponent(name), options: .withoutOverwriting)
      }
    }
  }
}
