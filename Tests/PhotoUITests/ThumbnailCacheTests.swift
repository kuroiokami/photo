import CoreGraphics
import Foundation
import PhotoCore
import PhotoUI
import Testing

@testable import PhotoImaging

struct ThumbnailCacheTests {
  private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  @Test func diskSurvivesWorkerRestartAndPreservesPixelsAndSourceDescription() async throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let file = root.appendingPathComponent("photo.png")
    try FileManager.default.copyItem(at: source, to: file)
    let original = try Data(contentsOf: file)
    let directory = root.appendingPathComponent("cache")
    let first = ImagePipeline(
      byteLimit: 1, thumbnailDiskCache: ThumbnailDiskCache(directory: directory))
    let expected = try await first.preview(for: file, maximumPixelSize: 480)
    let second = ImagePipeline(
      byteLimit: 1, thumbnailDiskCache: ThumbnailDiskCache(directory: directory))
    let actual = try await second.preview(for: file, maximumPixelSize: 480)
    #expect(await second.decodedImageCount == 0)
    #expect(await second.diskHitCount == 1)
    #expect(actual.originalWidth == expected.originalWidth)
    #expect(actual.originalHeight == expected.originalHeight)
    #expect(actual.sourceKind == expected.sourceKind)
    #expect(try raster(actual.image) == raster(expected.image))
    #expect(try Data(contentsOf: file) == original)
  }
  @Test func replacementSizeCorruptionAndMissingSourceCannotReuseOldDiskPixels() async throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let replacement = try #require(SampleResources.url(for: SampleLibrary.photos[1]))
    let file = root.appendingPathComponent("photo.png")
    try FileManager.default.copyItem(at: first, to: file)
    let disk = ThumbnailDiskCache(directory: root.appendingPathComponent("cache"))
    let pipeline = ImagePipeline(byteLimit: 1, thumbnailDiskCache: disk)
    let original = try await pipeline.preview(for: file, maximumPixelSize: 160)
    // Atomic source replacement changes the stamp even at the same pathname.
    try Data(contentsOf: replacement).write(to: file, options: .atomic)
    let updated = try await pipeline.preview(for: file, maximumPixelSize: 160)
    #expect(try raster(original.image) != raster(updated.image))
    _ = try await pipeline.preview(for: file, maximumPixelSize: 120)
    #expect(await pipeline.decodedImageCount == 3)
    let key = try #require(disk.key(for: file, size: 160))
    try Data("corrupt cache".utf8).write(to: root.appendingPathComponent("cache/\(key).thumb"))
    _ = try await pipeline.preview(for: file, maximumPixelSize: 160)
    #expect(await pipeline.decodedImageCount == 4)
    try FileManager.default.removeItem(at: file)
    await #expect(throws: (any Error).self) {
      try await pipeline.preview(for: file, maximumPixelSize: 160)
    }
  }
  @Test func diskBudgetClearAndUnwritableCacheKeepOriginalsViewable() async throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("cache")
    let source = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let disk = ThumbnailDiskCache(directory: directory, byteLimit: 30_000)
    let pipeline = ImagePipeline(byteLimit: 1, thumbnailDiskCache: disk)
    for size in stride(from: 80, through: 240, by: 20) {
      _ = try await pipeline.preview(for: source, maximumPixelSize: size)
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey])
    let bytes = try files.reduce(0) {
      try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }
    #expect(bytes <= 30_000)
    let unrelated = directory.appendingPathComponent("keep.txt")
    try Data("unrelated".utf8).write(to: unrelated)
    await pipeline.clearThumbnailCache()
    let remaining = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    #expect(remaining.map(\.lastPathComponent) == ["keep.txt"])
    #expect(try Data(contentsOf: unrelated) == Data("unrelated".utf8))
    let blocked = root.appendingPathComponent("not-a-folder")
    try Data().write(to: blocked)
    let fallback = ImagePipeline(
      byteLimit: 1, thumbnailDiskCache: ThumbnailDiskCache(directory: blocked))
    _ = try await fallback.preview(for: source, maximumPixelSize: 160)
    #expect(await fallback.decodedImageCount == 1)
  }
  @Test func immediateMemoryHitsRespectRecencySessionAndBudgetWithoutDiskAccess() async throws {
    let urls = try SampleLibrary.photos.map { try #require(SampleResources.url(for: $0)) }
    let probe = ImagePipeline(byteLimit: 1)
    let cost = try await probe.preview(for: urls[0], maximumPixelSize: 160).byteCost
    let pipeline = ImagePipeline(byteLimit: cost * 2)
    _ = try await pipeline.preview(for: urls[0], maximumPixelSize: 160)
    _ = try await pipeline.preview(for: urls[1], maximumPixelSize: 160)
    #expect(pipeline.immediateCachedPreview(for: urls[0], maximumPixelSize: 160) != nil)
    _ = try await pipeline.preview(for: urls[2], maximumPixelSize: 160)
    #expect(pipeline.immediateCachedPreview(for: urls[0], maximumPixelSize: 160) != nil)
    #expect(pipeline.immediateCachedPreview(for: urls[1], maximumPixelSize: 160) == nil)
    #expect(
      pipeline.immediateCachedPreview(for: urls[0], maximumPixelSize: 160, sessionID: UUID()) == nil
    )
    #expect(await pipeline.cachedByteCount <= cost * 2)
    await pipeline.startSession(UUID())
    #expect(pipeline.immediateCachedPreview(for: urls[0], maximumPixelSize: 160) == nil)
    #expect(ThumbnailCachePolicy.memoryByteLimit(physicalMemory: 0) == 64 * 1024 * 1024)
    #expect(ThumbnailCachePolicy.memoryByteLimit(physicalMemory: UInt64.max) == 256 * 1024 * 1024)
  }
  @Test func embeddedPreviewDescriptionSurvivesDiskWithoutCachingFitOrRawDetail() async throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let disk = ThumbnailDiskCache(directory: root.appendingPathComponent("cache"))
    let probe = ImagePipeline(byteLimit: 1)
    let image = try await probe.preview(for: source, maximumPixelSize: 160)
    // Synthetic embedded-preview description; no RAW fixture/camera claim.
    let embedded = PhotoPreview(
      image: image.image, sourceKind: .embedded,
      originalWidth: 8640, originalHeight: 5760)
    let key = try #require(disk.key(for: source, size: 160))
    disk.store(embedded, key: key)
    let result = try #require(disk.read(key))
    #expect(result.sourceKind == .embedded)
    #expect(result.originalWidth == 8640)
    #expect(result.originalHeight == 5760)
    #expect(disk.key(for: source, size: 2560) == nil)
  }

  @Test func concurrentImmediateLookupsAndActorEvictionStayConsistent() async throws {
    let urls = try SampleLibrary.photos.map { try #require(SampleResources.url(for: $0)) }
    let probe = ImagePipeline(byteLimit: 1)
    let cost = try await probe.preview(for: urls[0], maximumPixelSize: 160).byteCost
    let pipeline = ImagePipeline(byteLimit: cost * 2)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for worker in 0..<8 {
        group.addTask {
          for i in 0..<100 {
            let file = urls[(i + worker) % urls.count]
            if worker % 2 == 0 {
              _ = try await pipeline.preview(for: file, maximumPixelSize: 160)
            }
            if let cached = pipeline.immediateCachedPreview(for: file, maximumPixelSize: 160) {
              #expect(cached.decodedWidth == 160)
            }
          }
        }
      }
      try await group.waitForAll()
    }
    #expect(await pipeline.cachedByteCount <= cost * 2)
  }

  private func raster(_ image: CGImage) throws -> Data {
    let context = try #require(
      CGContext(
        data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Data(bytes: try #require(context.data), count: context.bytesPerRow * context.height)
  }
}
