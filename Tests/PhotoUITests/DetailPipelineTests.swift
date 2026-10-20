import CryptoKit
import Foundation
import ImageIO
import PhotoCore
import PhotoImaging
import PhotoUI
import Testing
import UniformTypeIdentifiers

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
  func localSonyEmbeddedAndRenderedDetailPreserveSource() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["PHOTO_RAW_TEST_FOLDER"])
    let folder = URL(fileURLWithPath: path)
    let files = try await LocalPhotoFileAccess().photos(in: folder)
      .filter { $0.pathExtension.lowercased() == "arw" }
    #expect(!files.isEmpty)
    for file in files {
      let before = SHA256.hash(data: try Data(contentsOf: file))
      let embedded = try await ImagePipeline(byteLimit: 64 * 1024 * 1024).preview(
        for: file, maximumPixelSize: 2560)
      #expect(embedded.sourceKind == .embedded)
      #expect(embedded.decodedWidth <= 2560 && embedded.decodedHeight <= 2560)
      let detail = try await DetailPipeline().detail(for: file)
      #expect(detail.sourceKind == .raw)
      #expect(detail.decodedWidth == embedded.originalWidth)
      #expect(detail.decodedHeight == embedded.originalHeight)
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
}
