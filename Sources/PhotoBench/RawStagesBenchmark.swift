import CoreGraphics
import Darwin
import Foundation
import PhotoCore
import PhotoImaging

/// One explicit file per fresh process; source hashes warm the OS cache.
/// Compare API stages, not differently scoped totals or image-rendering quality.
enum RawStagesBenchmark {
  struct Report: Encodable {
    var schemaVersion = 1
    var previewMilliseconds: Double?
    var previewSource: String?
    var previewWidth = 0
    var previewHeight = 0
    var originalWidth = 0
    var originalHeight = 0
    var metadataMilliseconds: Double?
    var metadataWidth = 0
    var metadataHeight = 0
    var hasISO = false
    var hasShutter = false
    var hasAperture = false
    var hasFocalLength = false
    var detailFirstMilliseconds: Double?
    var detailCompleteMilliseconds: Double?
    var detailSource: String?
    var detailWidth = 0
    var detailHeight = 0
    var previewFailed = false
    var metadataFailed = false
    var detailFailed = false
    var peakResidentMiB = 0.0
    var originalsUnchanged = false
  }
  static func run(file: URL, full: Bool) async throws -> Report {
    let hash = try MediaOperations.checksum(file)
    var report = Report()
    var start = ContinuousClock.now
    do {
      let value = try await ImagePipeline(byteLimit: 0).preview(
        for: file, maximumPixelSize: 2560)
      report.previewMilliseconds = ms(start)
      report.previewSource = value.sourceKind.rawValue
      report.previewWidth = value.decodedWidth
      report.previewHeight = value.decodedHeight
      report.originalWidth = value.originalWidth
      report.originalHeight = value.originalHeight
    } catch { report.previewFailed = true }
    start = .now
    do {
      let value = try await ImageMetadataReader().metadata(for: file)
      report.metadataMilliseconds = ms(start)
      report.metadataWidth = value.pixelWidth
      report.metadataHeight = value.pixelHeight
      report.hasISO = value.iso != nil
      report.hasShutter = value.exposureTime != nil
      report.hasAperture = value.aperture != nil
      report.hasFocalLength = value.focalLength != nil
    } catch { report.metadataFailed = true }
    if full {
      start = .now
      do {
        let focus = DetailFocus(
          point: CGPoint(x: 0.5, y: 0.5), viewportPixels: CGSize(width: 1600, height: 1200))
        let detail = DetailPipeline()
        for try await update in detail.updates(for: file, focus: focus) {
          let image: CGImage
          switch update {
          case .region(let value): image = value.preview.image
          case .complete(let value):
            image = value.image
            report.detailSource = value.sourceKind.rawValue
            report.detailWidth = value.decodedWidth
            report.detailHeight = value.decodedHeight
          }
          // Include a display-sized draw; no claim of equivalent render settings.
          let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
          context?.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
          if report.detailFirstMilliseconds == nil { report.detailFirstMilliseconds = ms(start) }
          if case .complete = update { report.detailCompleteMilliseconds = ms(start) }
        }
      } catch { report.detailFailed = true }
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    report.peakResidentMiB = Double(usage.ru_maxrss) / 1_048_576
    report.originalsUnchanged = try hash == MediaOperations.checksum(file)
    return report
  }
  private static func ms(_ start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    return Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds)
      / 1e15
  }
}
