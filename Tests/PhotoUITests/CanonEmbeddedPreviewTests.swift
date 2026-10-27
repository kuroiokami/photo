import CoreGraphics
import Foundation
import ImageIO
import PhotoCore
import PhotoUI
import Testing
import UniformTypeIdentifiers

@testable import PhotoImaging

@Suite(.serialized)
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
  private func container() throws -> (Data, Data) {
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
    return (header, preview)
  }
  private func big64(_ value: UInt64) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
  }
  @Test func denseHeadersAndExtendedSizesKeepSamePreviewWithFarFewerReads() throws {
    let image = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".CR3")
    defer { try? FileManager.default.removeItem(at: image) }
    let (header, preview) = try container()
    let brand = box("ftyp", Data("crx ".utf8))
    var dense = brand
    for _ in 0..<4094 { dense.append(box("free", Data())) }
    // The extended box header crosses the reader's window boundary.
    dense.append(big(1) + Data("free".utf8) + big64(16))
    dense.append(header.dropFirst(brand.count))
    // A zero-sized final box extends to EOF, as allowed by the container.
    dense.append(big(0) + Data("uuid".utf8) + preview)
    try dense.write(to: image)
    let buffered = try BufferedContainerReader(url: image)
    let control = try BufferedContainerReader(url: image, buffering: false)
    let actual = try #require(try CanonEmbeddedPreview.decode(buffered, maximumPixelSize: 160))
    let expected = try #require(try CanonEmbeddedPreview.decode(control, maximumPixelSize: 160))
    #expect(try pixels(actual.image) == pixels(expected.image))
    #expect(buffered.statistics.reads <= 12)
    #expect(control.statistics.reads > 4000)
    var excessiveBoxes = brand
    for _ in 0..<10_001 { excessiveBoxes.append(box("free", Data())) }
    var oversized = brand + big(1)
    oversized.append(Data("uuid".utf8))
    oversized.append(big64(UInt64.max))
    var undersized = brand + big(1)
    undersized.append(Data("uuid".utf8))
    undersized.append(big64(15))
    let malformed: [Data] = [
      oversized, undersized, brand + Data(repeating: 0, count: 7), excessiveBoxes,
    ]
    for invalid in malformed {
      try invalid.write(to: image)
      #expect(try CanonEmbeddedPreview.decode(image, maximumPixelSize: 160) == nil)
    }
    if let fixture = ProcessInfo.processInfo.environment["PHOTO_CANON_BENCHMARK_FIXTURE"],
      let report = ProcessInfo.processInfo.environment["PHOTO_CANON_BENCHMARK_REPORT"]
    {
      try benchmark(URL(fileURLWithPath: fixture), report: URL(fileURLWithPath: report))
    }
  }
  @Test func skipsLargeSparseSensorPayloadWithoutReadingItAll() throws {
    let image = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".CR3")
    defer { try? FileManager.default.removeItem(at: image) }
    let (header, preview) = try container()
    try header.write(to: image)
    let writer = try FileHandle(forWritingTo: image)
    let payloadSize: UInt64 = 128 * 1024 * 1024 + 16
    try writer.seekToEnd()
    try writer.write(contentsOf: big(1) + Data("mdat".utf8) + big64(payloadSize))
    try writer.seek(toOffset: UInt64(header.count) + payloadSize)
    try writer.write(contentsOf: box("uuid", preview))
    try writer.close()
    let reader = try BufferedContainerReader(url: image)
    let decoded = try #require(try CanonEmbeddedPreview.decode(reader, maximumPixelSize: 160))
    #expect(decoded.decodedWidth == 100 && decoded.decodedHeight == 160)
    #expect(reader.length > 128 * 1024 * 1024)
    #expect(reader.statistics.bytesRead < 256 * 1024)
    #expect(reader.statistics.reads <= 8)
  }
  private func benchmark(_ image: URL, report: URL) throws {
    func run(_ buffering: Bool) throws -> [String: Any] {
      try autoreleasepool {
        let start = ContinuousClock.now
        let reader = try BufferedContainerReader(url: image, buffering: buffering)
        let preview = try #require(try CanonEmbeddedPreview.decode(reader, maximumPixelSize: 2048))
        let duration = start.duration(to: .now).components
        return [
          "milliseconds": Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15,
          "reads": reader.statistics.reads, "bytes_read": reader.statistics.bytesRead,
          "speculative_bytes": reader.statistics.speculativeBytes,
          "decoded_width": preview.decodedWidth, "decoded_height": preview.decodedHeight,
          "original_width": preview.originalWidth, "original_height": preview.originalHeight,
        ]
      }
    }
    for _ in 0..<3 {
      _ = try run(false)
      _ = try run(true)
    }
    var samples: [[String: Any]] = []
    for index in 0..<30 {
      for buffered in (index.isMultiple(of: 2) ? [false, true] : [true, false]) {
        var sample = try run(buffered)
        sample["buffered"] = buffered
        samples.append(sample)
      }
    }
    let data = try JSONSerialization.data(
      withJSONObject: [
        "maximum_pixel_size": 2048,
        "warmups_per_mode": 3, "pairs": 30,
        "control": "Same parser and JPEG decode with header buffering disabled",
        "limitations":
          "Warm filesystem/cache component benchmark; not app first-paint or full RAW rendering.",
        "samples": samples,
      ], options: [.prettyPrinted, .sortedKeys])
    try data.write(to: report, options: .atomic)
  }
  @Test func boundedContainerReadsPreviewAndRejectsInvalidOffsets() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("synthetic.CR3")
    let (header, preview) = try container()
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
