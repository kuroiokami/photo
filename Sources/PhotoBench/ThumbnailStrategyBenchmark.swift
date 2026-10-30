import CoreGraphics
import Foundation
import ImageIO
import PhotoCore
import PhotoImaging
import UniformTypeIdentifiers

struct ThumbnailStrategyBenchmark {
  struct Case: Encodable {
    let encoding: String
    let pixelClass: Int
    let initialReadyP95Milliseconds: Double
    let readyAndWritesDrainedMilliseconds: Double
    let diskReadyP95Milliseconds: Double
    let diskBytes: Int
    let retainedDecodedBytes: Int
    let sourceDecodes: Int
    let diskHits: Int
    let jpegRecords: Int
    let meanAbsoluteChannelError: Double
    let maximumChannelError: Int
    let metadataMatches: Bool
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let originalsUnchanged: Bool
    let cases: [Case]
    let notes = [
      "Sixteen generated opaque RGB JPEGs; PNG/JPEG/JPEG/PNG at each 240/480 class. Both codecs use the same current pipeline, source stamps, bounded async writes and decode worker.",
      "JPEG quality 0.90 is experimental; production remains PNG. Alpha/high-depth/non-RGB inputs retain PNG. Quality errors compare sRGB RGBA bytes, not focus judgment or color-managed display acceptance.",
      "Ready timing excludes a derived-write barrier; readyAndWritesDrained includes all derived writes. Source hashing warms OS caches. Disk hits use a fresh RAM cache.",
      "Retained decoded bytes are cache accounting, not RSS or total renderer memory. These are service controls, not scrolling frames, physical media or broad camera/shoot acceptance.",
    ]
  }
  static func run() async throws -> Report {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let urls = try (0..<16).map { i -> URL in
      let url = root.appendingPathComponent("generated-\(i).jpg")
      try generate(url, index: i)
      return url
    }
    let hashes = try urls.map { try MediaOperations.checksum($0) }
    var cases: [Case] = []
    for edge in [240, 480] {
      for (iteration, encoding) in [ThumbnailDiskEncoding.png, .jpeg, .jpeg, .png].enumerated() {
        let cacheRoot = root.appendingPathComponent("cache-\(edge)-\(iteration)")
        let cache = ThumbnailDiskCache(directory: cacheRoot, encoding: encoding)
        let pipeline = ImagePipeline(byteLimit: 32 * 1024 * 1024, thumbnailDiskCache: cache)
        var ready: [Double] = []
        var references: [PhotoPreview] = []
        let start = ContinuousClock.now
        for url in urls {
          let request = ContinuousClock.now
          references.append(try await pipeline.preview(for: url, maximumPixelSize: edge))
          ready.append(elapsed(request))
        }
        await cache.waitForPendingWrites()
        let drained = elapsed(start)
        let reader = ImagePipeline(byteLimit: 0, thumbnailDiskCache: cache)
        var disk: [Double] = []
        var total: UInt64 = 0
        var components = 0
        var maximum = 0
        var matches = true
        for (index, url) in urls.enumerated() {
          let request = ContinuousClock.now
          let value = try await reader.preview(for: url, maximumPixelSize: edge)
          disk.append(elapsed(request))
          matches =
            matches && value.decodedWidth == references[index].decodedWidth
            && value.decodedHeight == references[index].decodedHeight
            && value.originalWidth == references[index].originalWidth
            && value.originalHeight == references[index].originalHeight
            && value.sourceKind == references[index].sourceKind
          let a = try rgba(references[index].image)
          let b = try rgba(value.image)
          for (x, y) in zip(a, b) {
            let error = abs(Int(x) - Int(y))
            total += UInt64(error)
            maximum = max(maximum, error)
          }
          components += a.count
        }
        await cache.waitForPendingWrites()
        let files = try FileManager.default.contentsOfDirectory(
          at: cacheRoot, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) {
          try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        let jpeg = try files.filter { url in
          let data = try Data(contentsOf: url)
          let record =
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
          return record?["encoding"] as? String == "jpeg"
        }.count
        let sourceStats = await pipeline.cacheStatistics()
        let diskStats = await reader.cacheStatistics()
        cases.append(
          Case(
            encoding: encoding.rawValue, pixelClass: edge,
            initialReadyP95Milliseconds: p95(ready), readyAndWritesDrainedMilliseconds: drained,
            diskReadyP95Milliseconds: p95(disk), diskBytes: bytes,
            retainedDecodedBytes: sourceStats.memoryBytes, sourceDecodes: sourceStats.sourceDecodes,
            diskHits: diskStats.diskHits, jpegRecords: jpeg,
            meanAbsoluteChannelError: Double(total) / Double(max(1, components)),
            maximumChannelError: maximum, metadataMatches: matches))
      }
    }
    return Report(
      originalsUnchanged: try urls.map { try MediaOperations.checksum($0) } == hashes, cases: cases)
  }
  private static func generate(_ url: URL, index: Int) throws {
    let width = 1600
    let height = 1067
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let p = (y * width + x) * 4
        bytes[p] = UInt8((x / 7 + y / 11 + index * 13) % 256)
        bytes[p + 1] = UInt8((x / 13 + y / 5 + index * 17) % 256)
        bytes[p + 2] = UInt8((x / 19 + y / 17 + index * 29) % 256)
      }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    guard
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw PreviewError.unreadable }
    CGImageDestinationAddImage(
      destination, image, [kCGImageDestinationLossyCompressionQuality: 0.96] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw PreviewError.unreadable }
  }
  private static func rgba(_ image: CGImage) throws -> [UInt8] {
    var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try result.withUnsafeMutableBytes { bytes in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { throw PreviewError.unreadable }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return result
  }
  private static func p95(_ values: [Double]) -> Double {
    values.sorted()[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)]
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let d = start.duration(to: .now)
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
  }
}
