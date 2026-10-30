import CoreGraphics
import Foundation
import PhotoCore
import Testing

@testable import PhotoImaging
@testable import PhotoUI

struct AdaptiveThumbnailTests {
  @Test func resolutionClassesFollowRetinaScaleAndRemainStableWithinAClass() {
    #expect(ThumbnailResolution.edge(points: 84, displayScale: 1) == 160)
    #expect(ThumbnailResolution.edge(points: 84, displayScale: 2) == 240)
    #expect(ThumbnailResolution.edge(points: 160, displayScale: 2) == 320)
    #expect(ThumbnailResolution.edge(points: 240, displayScale: 2) == 480)
    #expect(ThumbnailResolution.edge(points: 10000, displayScale: 2) == 480)
    #expect(ThumbnailResolution.edge(points: 85, displayScale: 2) == 240)
    #expect(ThumbnailResolution.edge(points: .nan, displayScale: .infinity) == 480)
  }
  @Test func cachedStandInsPreferAdequatePixelsAndRespectFileSessionClearAndBudget() async throws {
    let url = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let pipeline = ImagePipeline(byteLimit: 2 * 1024 * 1024)
    let session = UUID()
    await pipeline.startSession(session)
    _ = try await pipeline.preview(for: url, maximumPixelSize: 160, sessionID: session)
    let lower = try #require(
      pipeline.bestCachedThumbnail(for: url, maximumPixelSize: 320, sessionID: session))
    #expect(lower.requestedPixelSize == 160)
    #expect(
      pipeline.immediateCachedPreview(for: url, maximumPixelSize: 320, sessionID: session) == nil)
    _ = try await pipeline.preview(for: url, maximumPixelSize: 480, sessionID: session)
    let larger = try #require(
      pipeline.bestCachedThumbnail(for: url, maximumPixelSize: 240, sessionID: session))
    #expect(larger.requestedPixelSize == 480 && larger.preview.image.width == 480)
    #expect(pipeline.bestCachedThumbnail(for: url, maximumPixelSize: 240, sessionID: UUID()) == nil)
    #expect(
      pipeline.bestCachedThumbnail(
        for: url.appendingPathExtension("different"), maximumPixelSize: 240, sessionID: session)
        == nil)
    #expect(
      pipeline.bestCachedThumbnail(for: url, maximumPixelSize: 2560, sessionID: session) == nil)
    #expect(await pipeline.decodedImageCount == 2)
    #expect(await pipeline.cachedByteCount <= 2 * 1024 * 1024)
    await pipeline.clearThumbnailCache()
    #expect(
      pipeline.bestCachedThumbnail(for: url, maximumPixelSize: 240, sessionID: session) == nil)
  }
  @Test func viewIdentityRetainsOnlyTheSameImageAcrossResolutionChanges() {
    let pipeline = ImagePipeline(byteLimit: 1)
    let session = UUID()
    func identity(_ id: String = "a", size: Int = 160, generation: Int = 0, token: UUID? = nil)
      -> ImageRequestIdentity
    {
      ImageRequestIdentity(
        photoID: id, pipeline: ObjectIdentifier(pipeline), session: token ?? session,
        maximumPixelSize: size, cacheGeneration: generation, retry: 0)
    }
    #expect(identity().sameImage(as: identity(size: 480)))
    #expect(!identity().sameImage(as: identity("b")))
    #expect(!identity().sameImage(as: identity(generation: 1)))
    #expect(!identity().sameImage(as: identity(token: UUID())))
  }
  @Test func jpegCacheIsOptInAndAlphaFallsBackLosslessly() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for alpha in [CGImageAlphaInfo.noneSkipLast, .premultipliedLast] {
      let context = try #require(
        CGContext(
          data: nil, width: 32, height: 20, bitsPerComponent: 8,
          bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: alpha.rawValue))
      context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5))
      context.fill(CGRect(x: 0, y: 0, width: 32, height: 20))
      let image = try #require(context.makeImage())
      let cache = ThumbnailDiskCache(directory: root, encoding: .jpeg)
      let key = alpha == .noneSkipLast ? "opaque" : "alpha"
      cache.store(
        PhotoPreview(
          image: image, sourceKind: .embedded, originalWidth: 6000, originalHeight: 4000), key: key)
      let result = try #require(cache.read(key))
      #expect(
        result.decodedWidth == 32 && result.originalWidth == 6000 && result.sourceKind == .embedded)
      let data = try Data(contentsOf: root.appendingPathComponent(key + ".thumb"))
      let record = try #require(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
      #expect(record["version"] as? Int == (alpha == .noneSkipLast ? 2 : 1))
      if alpha == .premultipliedLast {
        #expect(result.image.alphaInfo != .none && result.image.alphaInfo != .noneSkipLast)
      }
    }
  }
}

extension AdaptiveThumbnailTests {
  @Test func experimentalCodecRetainsWideGamutProfileAndLosslessFallbackTypes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = ThumbnailDiskCache(directory: root, encoding: .jpeg)
    let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    let context = try #require(
      CGContext(
        data: nil, width: 24, height: 20, bitsPerComponent: 8,
        bytesPerRow: 96, space: p3, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(try #require(CGColor(colorSpace: p3, components: [0.1, 0.8, 0.3, 1])))
    context.fill(CGRect(x: 0, y: 0, width: 24, height: 20))
    let wide = try #require(context.makeImage())
    cache.store(PhotoPreview(image: wide, originalWidth: 24, originalHeight: 20), key: "wide")
    let restored = try #require(cache.read("wide"))
    #expect(restored.image.colorSpace?.name == CGColorSpace.displayP3)

    let gray = try #require(
      CGContext(
        data: nil, width: 24, height: 20, bitsPerComponent: 8,
        bytesPerRow: 24, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue))
    let grayImage = try #require(gray.makeImage())
    let provider = try #require(
      CGDataProvider(data: Data(repeating: 32, count: 144 * 20) as CFData))
    let deep = try #require(
      CGImage(
        width: 24, height: 20, bitsPerComponent: 16, bitsPerPixel: 48,
        bytesPerRow: 144, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    for (key, image) in [("gray", grayImage), ("deep", deep)] {
      cache.store(PhotoPreview(image: image, originalWidth: 24, originalHeight: 20), key: key)
      let data = try Data(contentsOf: root.appendingPathComponent(key + ".thumb"))
      let record = try #require(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
      #expect(record["version"] as? Int == 1)
      #expect(cache.read(key)?.decodedWidth == 24)
    }
  }
}
