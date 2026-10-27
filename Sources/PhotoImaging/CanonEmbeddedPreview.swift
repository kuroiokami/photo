import CoreGraphics
import Foundation
import ImageIO

/// Reads the bounded Canon CR3 PRVW JPEG without initializing Apple's RAW
/// container decoder. Unknown layouts fall back to the embedded-only ImageIO path.
/// Container field references: docs/decisions/0006-ingest-metadata-cameras.md.
enum CanonEmbeddedPreview {
  private struct Box {
    let type: String
    let payload: UInt64
    let end: UInt64
  }
  static func decode(
    _ url: URL, maximumPixelSize: Int,
    checkCancellation: @Sendable () throws -> Void = { try Task.checkCancellation() }
  ) throws -> PhotoPreview? {
    guard url.pathExtension.lowercased() == "cr3" else { return nil }
    // The reader and its stored cancellation callback stay inside this
    // synchronous decode; keep the pipeline's cancellation scope nonescaping.
    return try withoutActuallyEscaping(checkCancellation) { cancellation in
      let reader = try BufferedContainerReader(url: url, checkCancellation: cancellation)
      return try decode(reader, maximumPixelSize: maximumPixelSize, checkCancellation: cancellation)
    }
  }
  static func decode(
    _ reader: BufferedContainerReader, maximumPixelSize: Int,
    checkCancellation: @Sendable () throws -> Void = { try Task.checkCancellation() }
  ) throws -> PhotoPreview? {
    let length = reader.length
    func read(_ position: UInt64, _ count: Int) throws -> Data? {
      try reader.read(position, count)
    }
    func integer(_ data: Data, _ start: Int, _ count: Int, little: Bool = false) -> UInt64 {
      var value: UInt64 = 0
      for index in 0..<count {
        let position = start + (little ? count - index - 1 : index)
        value = (value << 8) | UInt64(data[position])
      }
      return value
    }
    var boxesRead = 0
    func boxes(_ start: UInt64, _ end: UInt64) throws -> [Box]? {
      var result: [Box] = []
      var position = start
      while position < end {
        boxesRead += 1
        guard boxesRead <= 10_000, end - position >= 8,
          let header = try read(position, 8)
        else { return nil }
        var size = integer(header, 0, 4)
        var headerSize: UInt64 = 8
        if size == 1 {
          guard end - position >= 16, let extended = try read(position + 8, 8) else { return nil }
          size = integer(extended, 0, 8)
          headerSize = 16
        } else if size == 0 {
          size = end - position
        }
        guard size >= headerSize, size <= end - position else { return nil }
        result.append(
          Box(
            type: String(decoding: header[4..<8], as: UTF8.self), payload: position + headerSize,
            end: position + size))
        position += size
      }
      return result
    }
    guard let top = try boxes(0, length), let brand = top.first, brand.type == "ftyp",
      brand.end - brand.payload >= 4,
      try read(brand.payload, 4) == Data("crx ".utf8)
    else { return nil }
    let metadataUUID = Data([
      0x85, 0xc0, 0xb6, 0x87, 0x82, 0x0f, 0x11, 0xe0, 0x81, 0x11, 0xf4, 0xce, 0x46, 0x2b, 0x6a,
      0x48,
    ])
    let previewUUID = Data([
      0xea, 0xf4, 0x2b, 0x5e, 0x1c, 0x98, 0x4b, 0x88, 0xb9, 0xfb, 0xb7, 0xdc, 0x40, 0x6e, 0x4d,
      0x16,
    ])
    var tiff: Data?
    for movie in top where movie.type == "moov" {
      guard let children = try boxes(movie.payload, movie.end) else { return nil }
      for child in children where child.type == "uuid" && child.end - child.payload >= 16 {
        guard try read(child.payload, 16) == metadataUUID else { continue }
        guard let atoms = try boxes(child.payload + 16, child.end) else { return nil }
        if let cmt = atoms.first(where: { $0.type == "CMT1" }), cmt.end - cmt.payload <= 65_536 {
          tiff = try read(cmt.payload, Int(cmt.end - cmt.payload))
        }
      }
    }
    guard let tiff, tiff.count >= 8,
      [Data([0x49, 0x49, 0x2a, 0]), Data([0x4d, 0x4d, 0, 0x2a])].contains(tiff.prefix(4))
    else { return nil }
    let little = tiff[0] == 0x49
    let offset = integer(tiff, 4, 4, little: little)
    guard offset <= UInt64(tiff.count - 2) else { return nil }
    let count = integer(tiff, Int(offset), 2, little: little)
    guard count <= UInt64((tiff.count - Int(offset) - 2) / 12) else { return nil }
    var tags: [UInt64: Int] = [:]
    for index in 0..<Int(count) {
      let position = Int(offset) + 2 + index * 12
      let tag = integer(tiff, position, 2, little: little)
      let type = integer(tiff, position + 2, 2, little: little)
      guard [UInt64(256), 257, 274].contains(tag), [UInt64(3), 4].contains(type),
        integer(tiff, position + 4, 4, little: little) == 1
      else { continue }
      tags[tag] = Int(integer(tiff, position + 8, type == 3 ? 2 : 4, little: little))
    }
    guard let width = tags[256], let height = tags[257], width > 0, height > 0,
      let orientation = tags[274], (1...8).contains(orientation)
    else { return nil }
    for preview in top where preview.type == "uuid" && preview.end - preview.payload >= 48 {
      guard let header = try read(preview.payload, 48), header.prefix(16) == previewUUID,
        String(decoding: header[28..<32], as: UTF8.self) == "PRVW"
      else { continue }
      let size = integer(header, 44, 4)
      guard size >= 4, size <= 64 * 1024 * 1024, size <= preview.end - preview.payload - 48,
        let jpeg = try read(preview.payload + 48, Int(size)),
        jpeg.prefix(3) == Data([0xff, 0xd8, 0xff]),
        let source = CGImageSourceCreateWithData(
          jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
        CGImageSourceGetType(source) as String? == "public.jpeg",
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary),
        let image = oriented(thumbnail, orientation: orientation)
      else { return nil }
      try checkCancellation()
      return PhotoPreview(
        image: image, sourceKind: .embedded,
        originalWidth: orientation >= 5 ? height : width,
        originalHeight: orientation >= 5 ? width : height)
    }
    return nil
  }
  static func oriented(_ image: CGImage, orientation: Int) -> CGImage? {
    guard orientation != 1 else { return image }
    let w = CGFloat(image.width)
    let h = CGFloat(image.height)
    let transforms = [
      CGAffineTransform.identity,
      CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0),
      CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h),
      CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h),
      CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w),
      CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w),
      CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0),
      CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0),
    ]
    guard (1...8).contains(orientation),
      let context = CGContext(
        data: nil, width: orientation >= 5 ? image.height : image.width,
        height: orientation >= 5 ? image.width : image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.concatenate(transforms[orientation - 1])
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return context.makeImage()
  }
}
