import CoreImage
import CryptoKit
import Darwin
import Foundation
import ImageIO
import PhotoCore
import PhotoImaging

/// Read-only comparison with the pre-progressive full-detail algorithm.
enum DetailBenchmark {
  struct Distribution: Codable {
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
  struct Report: Encodable {
    let schemaVersion = 1
    let mode: String
    let fileCount: Int
    let requests: Int
    let failures: Int
    let focusRegions: Int
    let firstInspection: Distribution
    let fullCompletion: Distribution?
    let initialInspectionMilliseconds: Double
    let peakResidentMiB: Double
    let originalsUnchanged: Bool
    let operatingSystem: String
    let logicalCPUCount: Int
    let physicalMemoryGiB: Double
    let notes: [String]
  }
  static func run(folder: URL, baseline: Bool) async throws -> Report {
    let urls = try await LocalPhotoFileAccess().photos(in: folder)
    guard !urls.isEmpty else { throw PreviewError.unreadable }
    var hashes: [URL: SHA256.Digest] = [:]
    for url in urls { hashes[url] = try hash(url) }
    let pipeline = DetailPipeline()
    var first: [Double] = []
    var full: [Double] = []
    var failures = 0
    var regions = 0
    let focus = DetailFocus(
      point: CGPoint(x: 0.5, y: 0.5), viewportPixels: CGSize(width: 1600, height: 1200))
    for _ in 0..<3 {
      for url in urls {
        let start = ContinuousClock.now
        var inspected = false
        do {
          if baseline {
            try autoreleasepool {
              let image = try legacyDetail(url)
              // The old API can return a deferred CGImage. Include its first
              // visible draw, where that work previously reached the UI thread.
              drawViewport(image)
            }
            let elapsed = ms(start)
            first.append(elapsed)
          } else {
            for try await update in pipeline.updates(for: url, focus: focus) {
              if !inspected {
                switch update {
                case .region(let region): drawViewport(region.preview.image)
                case .complete(let image): drawViewport(image.image)
                }
              }
              let elapsed = ms(start)
              if !inspected {
                first.append(elapsed)
                inspected = true
              }
              switch update {
              case .region: regions += 1
              case .complete: full.append(elapsed)
              }
            }
          }
        } catch { failures += 1 }
      }
    }
    var unchanged = true
    for url in urls { if try hash(url) != hashes[url] { unchanged = false } }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Report(
      mode: baseline ? "baseline-full-image" : "progressive-focus-then-full",
      fileCount: urls.count, requests: urls.count * 3, failures: failures, focusRegions: regions,
      firstInspection: Distribution(first), fullCompletion: baseline ? nil : Distribution(full),
      initialInspectionMilliseconds: first.first ?? 0,
      peakResidentMiB: Double(usage.ru_maxrss) / 1_048_576,
      originalsUnchanged: unchanged,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount,
      physicalMemoryGiB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
      notes: [
        "Three passes in natural filename order; no full-detail image cache. First request includes process/decoder/context initialization.",
        "Viewport request is 1600 × 1200 physical pixels plus a bounded margin. RAW processing settings and scale are unchanged.",
        "Separate processes share OS file/driver caches; these are service timings, not native input/frame latency.",
        "Baseline first inspection includes the deferred CGImage's first viewport draw; baseline fullCompletion is absent because that draw need not render every offscreen pixel.",
        "Peak RSS includes Core Image/decoder/transient memory and is not the 256 MiB decoded-image limit.",
      ])
  }
  private static func ms(_ start: ContinuousClock.Instant) -> Double {
    let d = start.duration(to: .now)
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
  }
  private static func hash(_ url: URL) throws -> SHA256.Digest {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
      hasher.update(data: data)
    }
    return hasher.finalize()
  }
  private static func drawViewport(_ image: CGImage) {
    let bitmap = CGContext(
      data: nil, width: 1600, height: 1200,
      bitsPerComponent: 8, bytesPerRow: 1600 * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.interpolationQuality = .none
    bitmap.draw(
      image,
      in: CGRect(
        x: 800 - image.width / 2,
        y: 600 - image.height / 2, width: image.width, height: image.height))
  }
  private static func legacyDetail(_ url: URL) throws -> CGImage {
    guard
      let source = CGImageSourceCreateWithURL(
        url as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
    else { throw PreviewError.unreadable }
    guard DetailPipeline.fits(width: width, height: height) else {
      throw PreviewError.detailTooLarge
    }
    if PhotoFormats.isRaw(url) {
      guard let filter = CIRAWFilter(imageURL: url), let output = filter.outputImage,
        let result = CIContext(options: [.cacheIntermediates: false]).createCGImage(
          output, from: output.extent, format: .RGBA8,
          colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
      else { throw PreviewError.unreadable }
      return result
    }
    guard
      let result = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: max(width, height),
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    else { throw PreviewError.unreadable }
    return result
  }
}
