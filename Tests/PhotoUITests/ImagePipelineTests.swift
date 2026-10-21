import CoreGraphics
import Foundation
import ImageIO
import PhotoCore
import PhotoUI
import Testing
import UniformTypeIdentifiers

@testable import PhotoImaging

struct ImagePipelineTests {
  @Test func pngAndJPEGDecodeWithoutChangingSourceBytes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let png = directory.appendingPathComponent("example.png")
    try FileManager.default.copyItem(at: original, to: png)
    let data = try Data(contentsOf: png)
    let pipeline = ImagePipeline(byteLimit: 1024 * 1024)
    let decoded = try await pipeline.preview(for: png, maximumPixelSize: 160)
    #expect(decoded.image.width == 160)
    #expect(decoded.image.height == 100)
    #expect(decoded.originalWidth == 640)
    #expect(decoded.originalHeight == 400)
    #expect(try Data(contentsOf: png) == data)

    let jpeg = directory.appendingPathComponent("rotated.jpg")
    let source = try #require(CGImageSourceCreateWithURL(png as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let destination = try #require(
      CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let jpegData = try Data(contentsOf: jpeg)
    let rotated = try await pipeline.preview(for: jpeg, maximumPixelSize: 160)
    #expect(rotated.image.width == 100)
    #expect(rotated.image.height == 160)
    #expect(rotated.originalWidth == 400)
    #expect(rotated.originalHeight == 640)
    #expect(try Data(contentsOf: jpeg) == jpegData)
  }

  @Test func corruptRemovedAndCancelledFilesFailSafely() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("broken.png")
    try Data("not an image".utf8).write(to: file)
    let pipeline = ImagePipeline(byteLimit: 1024)
    await #expect(throws: (any Error).self) {
      try await pipeline.preview(for: file, maximumPixelSize: 160)
    }
    try FileManager.default.removeItem(at: file)
    await #expect(throws: (any Error).self) {
      try await pipeline.preview(for: file, maximumPixelSize: 160)
    }
    let task = Task {
      // Cancellation before a queued decode must prevent file work and cache insertion.
      withUnsafeCurrentTask { $0?.cancel() }
      return try await pipeline.preview(for: file, maximumPixelSize: 160)
    }
    do {
      _ = try await task.value
      Issue.record("Cancelled decode unexpectedly succeeded")
    } catch { #expect(error is CancellationError) }
    #expect(await pipeline.cachedByteCount == 0)
  }

  @Test func unreadableImageCanBeRetriedAfterAccessIsRestored() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("restricted.png")
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      try? FileManager.default.removeItem(at: directory)
    }
    let source = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    try FileManager.default.copyItem(at: source, to: file)
    let original = try Data(contentsOf: file)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
    let pipeline = ImagePipeline(byteLimit: 1024 * 1024)
    await #expect(throws: (any Error).self) {
      try await pipeline.preview(for: file, maximumPixelSize: 160)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let result = try await pipeline.preview(for: file, maximumPixelSize: 160)
    #expect(result.image.width == 160)
    #expect(try Data(contentsOf: file) == original)
  }

  @Test func concurrentRequestsDecodeOnceAndShareTheCache() async throws {
    let url = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let pipeline = ImagePipeline(byteLimit: 1024 * 1024)
    try await withThrowingTaskGroup(of: PhotoPreview.self) { group in
      for _ in 0..<8 {
        group.addTask { try await pipeline.preview(for: url, maximumPixelSize: 160) }
      }
      var count = 0
      for try await image in group {
        #expect(image.image.width == 160)
        count += 1
      }
      #expect(count == 8)
    }
    #expect(await pipeline.decodedImageCount == 1)
    #expect(await pipeline.cachedPreview(for: url, maximumPixelSize: 160) != nil)
    #expect(await pipeline.cachedPreview(for: url, maximumPixelSize: 160, sessionID: UUID()) == nil)
    #expect(await pipeline.decodedImageCount == 1)
  }

  @Test func cancelledSessionResetCannotEvictTheCurrentCache() async throws {
    let url = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let pipeline = ImagePipeline(byteLimit: 1024 * 1024)
    let current = UUID()
    _ = try await pipeline.preview(for: url, maximumPixelSize: 160, sessionID: current)
    let reset = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      await pipeline.startSession(UUID())
    }
    await reset.value
    #expect(
      await pipeline.cachedPreview(for: url, maximumPixelSize: 160, sessionID: current) != nil)
    #expect(await pipeline.decodedImageCount == 1)
  }

  @Test func newFolderSessionDropsStalePixelsAndAllowsRetry() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let bytes = try Data(contentsOf: original)
    let file = directory.appendingPathComponent("reload.png")
    try bytes.write(to: file)
    let pipeline = ImagePipeline(byteLimit: 1024 * 1024)
    let first = UUID()
    let next = UUID()
    _ = try await pipeline.preview(for: file, maximumPixelSize: 160, sessionID: first)
    try Data("changed externally".utf8).write(to: file)
    #expect(await pipeline.cachedPreview(for: file, maximumPixelSize: 160, sessionID: first) != nil)
    await pipeline.startSession(next)
    #expect(await pipeline.cachedByteCount == 0)
    await #expect(throws: (any Error).self) {
      try await pipeline.preview(for: file, maximumPixelSize: 160, sessionID: next)
    }
    try bytes.write(to: file)
    let recovered = try await pipeline.preview(for: file, maximumPixelSize: 160, sessionID: next)
    #expect(recovered.image.width == 160)
    #expect(await pipeline.decodedImageCount == 3)
  }

  @Test func cacheRecencySurvivesRepeatedHitsEvictionAndSessionReset() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let urls = try (0..<4).map { index in
      let url = directory.appendingPathComponent("Frame\(index).png")
      try FileManager.default.copyItem(at: original, to: url)
      return url
    }
    let sample = try await ImagePipeline(byteLimit: 0).preview(for: urls[0], maximumPixelSize: 160)
    let pipeline = ImagePipeline(byteLimit: sample.byteCost * 2)
    for index in [0, 1] {
      _ = try await pipeline.preview(for: urls[index], maximumPixelSize: 160)
    }
    for _ in 0..<10 {
      #expect(await pipeline.cachedPreview(for: urls[0], maximumPixelSize: 160) != nil)
    }
    _ = try await pipeline.preview(for: urls[2], maximumPixelSize: 160)
    #expect(await pipeline.cachedPreview(for: urls[1], maximumPixelSize: 160) == nil)
    #expect(await pipeline.cachedPreview(for: urls[2], maximumPixelSize: 160) != nil)
    // Both the decode entry point and non-decoding lookup must update recency.
    _ = try await pipeline.preview(for: urls[0], maximumPixelSize: 160)
    _ = try await pipeline.preview(for: urls[1], maximumPixelSize: 160)
    #expect(await pipeline.cachedPreview(for: urls[2], maximumPixelSize: 160) == nil)
    #expect(await pipeline.cachedByteCount == sample.byteCost * 2)
    #expect(await pipeline.decodedImageCount == 4)
    let session = UUID()
    _ = try await pipeline.preview(for: urls[3], maximumPixelSize: 160, sessionID: session)
    #expect(await pipeline.cachedByteCount == sample.byteCost)
    #expect(
      await pipeline.cachedPreview(for: urls[0], maximumPixelSize: 160, sessionID: session) == nil)
    #expect(
      await pipeline.cachedPreview(for: urls[3], maximumPixelSize: 160, sessionID: session) != nil)
  }

  @Test func reusedEXIFDateParsersKeepOffsetsFractionsAndMissingValuesIndependent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let source = try #require(CGImageSourceCreateWithURL(original as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let reader = ImageMetadataReader()
    let text = "2026:10:20 12:34:56"
    let utc = Date(timeIntervalSince1970: 1_792_499_696)
    let cases: [([CFString: String], Date?)] = [
      (
        [
          kCGImagePropertyExifDateTimeOriginal: text,
          kCGImagePropertyExifOffsetTimeOriginal: "+02:00",
        ], utc.addingTimeInterval(-7200)
      ),
      ([kCGImagePropertyExifDateTimeOriginal: text], utc),
      (
        [
          kCGImagePropertyExifDateTimeOriginal: text,
          kCGImagePropertyExifOffsetTimeOriginal: "-04:30",
          kCGImagePropertyExifSubsecTimeOriginal: "125",
        ], utc.addingTimeInterval(16200.125)
      ),
      ([:], nil),
      ([kCGImagePropertyExifDateTimeOriginal: "invalid"], nil),
      ([kCGImagePropertyExifDateTimeOriginal: text], utc),
    ]
    for (index, item) in cases.enumerated() {
      let file = directory.appendingPathComponent("Date\(index).jpg")
      let destination = try #require(
        CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(
        destination, image, [kCGImagePropertyExifDictionary: item.0] as CFDictionary)
      #expect(CGImageDestinationFinalize(destination))
      let result = try await reader.metadata(for: file)
      #expect(result.captureTime == item.1)
    }
  }

  @Test func cacheStaysWithinBudgetAndOversizedImagesAreNotCached() async throws {
    let url = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let budget = 100_000
    let pipeline = ImagePipeline(byteLimit: budget)
    for size in [100, 120, 140, 160, 180, 200] {
      let result = try await pipeline.preview(for: url, maximumPixelSize: size)
      #expect(result.image.width == size)
      #expect(await pipeline.cachedByteCount <= budget)
    }
    let tiny = ImagePipeline(byteLimit: 1)
    _ = try await tiny.preview(for: url, maximumPixelSize: 100)
    #expect(await tiny.cachedByteCount == 0)
  }
}
