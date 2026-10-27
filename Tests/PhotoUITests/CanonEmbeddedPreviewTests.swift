import CoreGraphics
import Foundation
import ImageIO
import PhotoCore
import PhotoUI
import Testing
import UniformTypeIdentifiers

@testable import PhotoImaging

struct CanonEmbeddedPreviewTests {
  private func pixels(_ image: CGImage) throws -> Data {
    let context = try #require(
      CGContext(
        data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
  }
  @Test(arguments: Array(1...8))
  func orientationsMatchImageIO(_ orientation: Int) throws {
    let original = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let input = try #require(CGImageSourceCreateWithURL(original as CFURL, nil))
    let data = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImageFromSource(
      destination, input, 0, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let source = try #require(CGImageSourceCreateWithData(data, nil))
    let unrotated = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let expected = try #require(
      CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 640,
        ] as CFDictionary))
    let actual = try #require(CanonEmbeddedPreview.oriented(unrotated, orientation: orientation))
    #expect(actual.width == expected.width && actual.height == expected.height)
    #expect(try pixels(actual) == pixels(expected))
  }
  private func big(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
  }
  private func box(_ type: String, _ payload: Data) -> Data {
    big(UInt32(payload.count + 8)) + Data(type.utf8) + payload
  }
  @Test func boundedContainerReadsPreviewAndRejectsInvalidOffsets() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("synthetic.CR3")
    let original = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let source = try #require(CGImageSourceCreateWithURL(original as CFURL, nil))
    let jpeg = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImageFromSource(destination, source, 0, nil)
    #expect(CGImageDestinationFinalize(destination))
    let tiff = Data([
      0x49, 0x49, 42, 0, 8, 0, 0, 0, 3, 0,
      0, 1, 4, 0, 1, 0, 0, 0, 0x80, 2, 0, 0,
      1, 1, 4, 0, 1, 0, 0, 0, 0x90, 1, 0, 0,
      0x12, 1, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0,
    ])
    let metadataUUID = Data([
      0x85, 0xc0, 0xb6, 0x87, 0x82, 0x0f, 0x11, 0xe0, 0x81, 0x11, 0xf4, 0xce, 0x46, 0x2b, 0x6a,
      0x48,
    ])
    let previewUUID = Data([
      0xea, 0xf4, 0x2b, 0x5e, 0x1c, 0x98, 0x4b, 0x88, 0xb9, 0xfb, 0xb7, 0xdc, 0x40, 0x6e, 0x4d,
      0x16,
    ])
    let header =
      box("ftyp", Data("crx ".utf8)) + box("moov", box("uuid", metadataUUID + box("CMT1", tiff)))
    let preview =
      previewUUID + Data(repeating: 0, count: 8) + big(UInt32(jpeg.length + 24)) + Data("PRVW".utf8)
      + Data(repeating: 0, count: 12) + big(UInt32(jpeg.length)) + (jpeg as Data)
    try (header + box("uuid", preview)).write(to: image)
    #expect(throws: CancellationError.self) {
      try CanonEmbeddedPreview.decode(
        image, maximumPixelSize: 160,
        checkCancellation: {
          throw CancellationError()
        })
    }
    let decoded = try #require(try CanonEmbeddedPreview.decode(image, maximumPixelSize: 160))
    #expect(decoded.sourceKind == .embedded)
    #expect(decoded.decodedWidth == 100 && decoded.decodedHeight == 160)
    #expect(decoded.originalWidth == 400 && decoded.originalHeight == 640)
    for invalid in [
      Data(), big(UInt32.max) + Data("uuid".utf8), header + box("uuid", preview.prefix(47)),
    ] {
      try invalid.write(to: image)
      #expect(try CanonEmbeddedPreview.decode(image, maximumPixelSize: 160) == nil)
    }
  }
}
