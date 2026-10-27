import CoreGraphics
import Foundation
import ImageIO
import PhotoCore
import PhotoImaging
import UniformTypeIdentifiers

/// Generated files only. This compares reuse on/off in the current reader;
/// it does not time scrolling or restore a historical application executable.
enum MetadataReadBenchmark {
  struct Phase: Encodable {
    let name: String
    let samplesMilliseconds: [Double]
    let statistics: MetadataReadStatistics
    let valuesMatch: Bool
  }
  struct Pass: Encodable {
    let reuseEnabled: Bool
    let phases: [Phase]
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let generatedFiles: Int
    let originalsUnchanged: Bool
    let passes: [Pass]
    let operatingSystem: String
    let notes: [String]
  }
  static func run() async throws -> Report {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let urls = try (0..<512).map { index -> URL in
      let png = index.isMultiple(of: 4)
      let url = root.appendingPathComponent("generated-\(index)." + (png ? "png" : "jpg"))
      try generate(url, index: index, png: png)
      return url
    }
    let originals = try urls.map { try MediaOperations.checksum($0) }
    var passes: [Pass] = []
    for reuse in [false, true, true, false] {
      var phases: [Phase] = []
      for name in ["cold_exif", "paired_exif_xmp", "repeated_panel_reads", "cold_exif_eviction"] {
        let reader = ImageMetadataReader(entryLimit: reuse ? 128 : 0)
        let visits =
          name == "repeated_panel_reads"
          ? (0..<32).map { [1, 8, 17, 23][$0 % 4] }
          : Array(urls.indices.prefix(name == "cold_exif_eviction" ? urls.count : 24))
        let wantsXMP = name == "paired_exif_xmp" || name == "repeated_panel_reads"
        var samples: [Double] = []
        var matches = true
        for index in visits {
          let start = ContinuousClock.now
          let info = try await reader.metadata(for: urls[index])
          let xmp = wantsXMP ? try await reader.embeddedXMP(for: urls[index]) : nil
          let elapsed = start.duration(to: .now).components
          samples.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
          matches = matches && info.pixelWidth == 16 && info.pixelHeight == 12
          if !index.isMultiple(of: 4) {
            matches =
              matches && info.camera == "Generated \(index)" && info.iso == Double(100 + index)
            if wantsXMP {
              let title = try XMPSidecar.descriptive(xmp).fields[.title]
              matches = matches && title == "Generated \(index)"
            }
          }
        }
        phases.append(
          Phase(
            name: name, samplesMilliseconds: samples,
            statistics: await reader.statistics, valuesMatch: matches))
        await reader.clear()
      }
      passes.append(Pass(reuseEnabled: reuse, phases: phases))
    }
    let after = try urls.map { try MediaOperations.checksum($0) }
    guard originals == after, passes.allSatisfy({ $0.phases.allSatisfy(\.valuesMatch) }) else {
      throw MediaOperationError.invalid(
        "Metadata benchmark values or original hashes did not match.")
    }
    return Report(
      generatedFiles: urls.count, originalsUnchanged: true, passes: passes,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      notes: [
        "Generated 16 × 12 JPEG/PNG; metadata only. No private photos or paths in output.",
        "Alternating off/on/on/off controls use the same current reader and file-stamp checks.",
        "Cold EXIF is one read per file, paired queries request both fields, panel visits revisit four files eight times.",
        "Filesystem caches and background load are uncontrolled. No RAW startup, UI-frame, physical-media or RSS claim.",
        "Accounted result bytes exclude dictionary/allocator overhead and ImageIO's one short-lived opaque source.",
      ])
  }
  private static func generate(_ url: URL, index: Int, png: Bool) throws {
    guard
      let context = CGContext(
        data: nil, width: 16, height: 12, bitsPerComponent: 8,
        bytesPerRow: 64, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw PreviewError.unreadable }
    context.setFillColor(CGColor(red: CGFloat(index) / 24, green: 0.5, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
    guard let image = context.makeImage(),
      let output = CGImageDestinationCreateWithURL(
        url as CFURL,
        (png ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil)
    else { throw PreviewError.unreadable }
    let properties: [CFString: Any] =
      png
      ? [:]
      : [
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Generated \(index)"],
        kCGImagePropertyExifDictionary: [
          kCGImagePropertyExifISOSpeedRatings: [100 + index],
          kCGImagePropertyExifDateTimeOriginal: "2026:10:27 10:30:00",
        ],
        kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCObjectName: "Generated \(index)"],
      ]
    CGImageDestinationAddImage(output, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(output) else { throw PreviewError.unreadable }
  }
}
