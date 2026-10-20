import CoreImage
import CryptoKit
import Foundation
import ImageIO
import PhotoCore
import PhotoUI
import Testing
import UniformTypeIdentifiers

@testable import PhotoImaging

struct DetailPipelineTests {
  @Test func fullResolutionOrientationAndOriginalBytes() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let sample = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let source = try #require(CGImageSourceCreateWithURL(sample as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let jpeg = dir.appendingPathComponent("rotated.jpg")
    let destination = try #require(
      CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(
      destination, image,
      [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyExifDictionary: [
          kCGImagePropertyExifDateTimeOriginal: "2026:10:19 12:00:00",
          kCGImagePropertyExifOffsetTimeOriginal: "+02:00", kCGImagePropertyExifExposureTime: 0.001,
          kCGImagePropertyExifFNumber: 2.8, kCGImagePropertyExifISOSpeedRatings: [400],
        ],
      ] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let original = try Data(contentsOf: jpeg)
    let detail = try await DetailPipeline().detail(for: jpeg)
    #expect(detail.decodedWidth == 400)
    #expect(detail.decodedHeight == 640)
    #expect(detail.sourceKind == .image)
    let metadata = try await ImageMetadataReader().metadata(for: jpeg)
    let expected = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00Z")
    #expect(metadata.captureTime == expected)
    #expect(metadata.iso == 400)
    #expect(metadata.exposureTime == 0.001)
    #expect(metadata.pixelWidth == 400)
    #expect(try Data(contentsOf: jpeg) == original)
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTO_RAW_TEST_FOLDER"] != nil))
  func localRawEmbeddedAndRenderedDetailPreserveSource() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["PHOTO_RAW_TEST_FOLDER"])
    let folder = URL(fileURLWithPath: path)
    let files = try await LocalPhotoFileAccess().photos(in: folder)
      .filter(PhotoFormats.isRaw)
    #expect(!files.isEmpty)
    for file in files {
      let before = SHA256.hash(data: try Data(contentsOf: file))
      let embedded = try await ImagePipeline(byteLimit: 64 * 1024 * 1024).preview(
        for: file, maximumPixelSize: 2560)
      #expect(embedded.sourceKind == .embedded)
      #expect(embedded.decodedWidth <= 2560 && embedded.decodedHeight <= 2560)
      let detail = try await DetailPipeline().detail(for: file)
      #expect(detail.sourceKind == .raw)
      #expect(detail.decodedWidth >= embedded.decodedWidth)
      #expect(detail.decodedHeight >= embedded.decodedHeight)
      #expect(detail.byteCost <= DetailPipeline.byteLimit)
      #expect(SHA256.hash(data: try Data(contentsOf: file)) == before)
    }
  }

  @Test func corruptDetailExplainsReadFailureInsteadOfMemoryLimit() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("corrupt.ARW")
    try Data("not a RAW image".utf8).write(to: file)
    do {
      _ = try await DetailPipeline().detail(for: file)
      Issue.record("Corrupt detail unexpectedly decoded")
    } catch let error as PreviewError {
      #expect(error == .unreadable)
    }
  }

  @Test func budgetOverflowAndCancellationAreSafe() async throws {
    #expect(!DetailPipeline.fits(width: Int.max, height: Int.max))
    #expect(!DetailPipeline.fits(width: 20_000, height: 20_000))
    #expect(!DetailPipeline.fits(width: 0, height: 100))
    #expect(DetailPipeline.fits(width: 9504, height: 6336))
    let sample = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await DetailPipeline().detail(for: sample)
    }
    do {
      _ = try await task.value
      Issue.record("Cancelled detail decoded")
    } catch { #expect(error is CancellationError) }
  }
  @Test func focusBoundsRespectEdgesOrientationAndCombinedBudget() {
    let focus = DetailFocus(
      point: CGPoint(x: 1, y: 0), viewportPixels: CGSize(width: 1600, height: 1200))
    let rect = DetailPipeline.focusBounds(width: 9504, height: 6336, focus: focus)
    #expect(rect?.maxX == 9504)
    #expect(rect?.minY == 0)
    #expect(rect?.size == CGSize(width: 1856, height: 1456))
    let portrait = DetailPipeline.focusBounds(width: 6336, height: 9504, focus: focus)
    #expect(portrait?.maxX == 6336)
    #expect(portrait?.minY == 0)
    #expect(DetailPipeline.focusBounds(width: 8192, height: 8192, focus: focus) == nil)
    #expect(DetailPipeline.focusBounds(width: 640, height: 400, focus: focus) == nil)
    #expect(
      DetailPipeline.focusBounds(
        width: 9504, height: 6336,
        focus: DetailFocus(
          point: CGPoint(x: Double.nan, y: 0), viewportPixels: CGSize(width: 100, height: 100)))
        == nil)
  }

  @Test func progressiveOrdinaryImageFinishesAndCancelledConsumerStops() async throws {
    let sample = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let pipeline = DetailPipeline()
    let focus = DetailFocus(
      point: CGPoint(x: 0.5, y: 0.5), viewportPixels: CGSize(width: 400, height: 300))
    var completions = 0
    for try await update in pipeline.updates(for: sample, focus: focus) {
      switch update {
      case .region: Issue.record("Ordinary images should decode directly")
      case .complete(let preview):
        completions += 1
        #expect(preview.sourceKind == .image)
        #expect(preview.byteCost <= DetailPipeline.byteLimit)
      }
    }
    #expect(completions == 1)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      for try await _ in pipeline.updates(for: sample, focus: focus) {
        Issue.record("Cancelled consumer received a late image")
      }
    }
    _ = try? await task.value
    // A cancelled stream must not poison the shared serial lane.
    #expect(try await pipeline.detail(for: sample).decodedWidth > 0)
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTO_RAW_TEST_FOLDER"] != nil))
  func rawFocusRegionMatchesFullImagePixelsAndCancellationLeavesLaneUsable() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["PHOTO_RAW_TEST_FOLDER"])
    let files = try await LocalPhotoFileAccess().photos(in: URL(fileURLWithPath: path)).filter(
      PhotoFormats.isRaw)
    let file = try #require(files.first)
    let before = SHA256.hash(data: try Data(contentsOf: file))
    let pipeline = DetailPipeline()
    let focus = DetailFocus(
      point: CGPoint(x: 0.8, y: 0.2), viewportPixels: CGSize(width: 800, height: 600))
    var patch: DetailRegion?
    var full: PhotoPreview?
    for try await update in pipeline.updates(for: file, focus: focus) {
      switch update {
      case .region(let region):
        #expect(full == nil)
        patch = region
      case .complete(let image): full = image
      }
    }
    let region = try #require(patch)
    let image = try #require(full)
    #expect(region.preview.sourceKind == .raw)
    #expect(region.preview.originalWidth == image.decodedWidth)
    #expect(region.preview.originalHeight == image.decodedHeight)
    #expect(region.preview.byteCost + image.byteCost <= DetailPipeline.byteLimit)
    let cropped = try #require(image.image.cropping(to: region.bounds))
    let a = try pixels(region.preview.image)
    let b = try pixels(cropped)
    #expect(a.count == b.count)
    #expect(zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
    let cancelled = Task {
      for try await update in pipeline.updates(for: file, focus: focus) {
        if case .region = update { withUnsafeCurrentTask { $0?.cancel() } }
        if case .complete = update { Issue.record("Cancelled region consumer received full image") }
      }
    }
    _ = try? await cancelled.value
    #expect(try await pipeline.detail(for: file).decodedWidth == image.decodedWidth)
    #expect(SHA256.hash(data: try Data(contentsOf: file)) == before)
  }
  @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8])
  func eagerBitmapPreservesEveryOrientationAndNonzeroExtent(_ orientation: Int) throws {
    let sample = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let source = try #require(CGImageSourceCreateWithURL(sample as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let output = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: 1, y: 8))
      .oriented(
        CGImagePropertyOrientation(rawValue: UInt32(orientation))!
      )
      .transformed(by: CGAffineTransform(translationX: 17, y: 23))
    let context = CIContext(options: [.cacheIntermediates: false])
    let expected = try #require(
      context.createCGImage(
        output, from: output.extent,
        format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB), deferred: false))
    let result = try DetailPipeline.renderBitmap(
      output, extent: output.extent.integral, context: context)
    #expect(result.width == expected.width)
    #expect(result.height == expected.height)
    let a = try pixels(result)
    let b = try pixels(expected)
    #expect(zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
  }

  private func pixels(_ image: CGImage) throws -> [UInt8] {
    let context = try #require(
      CGContext(
        data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = try #require(context.data)
    return Array(
      UnsafeBufferPointer(
        start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
  }

}
