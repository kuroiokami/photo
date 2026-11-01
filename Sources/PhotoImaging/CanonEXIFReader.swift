import Foundation
import ImageIO

/// Standard CMT1/CMT2 fields only. Never invokes a RAW decoder or interprets maker notes/pixel payloads.
/// Unknown/ambiguous representations fall back to the existing ImageIO reader.
enum CanonEXIFReader {
  struct Result {
    let properties: [CFString: Any]
    let io: BufferedContainerReader.Statistics
  }
  private enum Unsupported: Error { case layout }
  private struct Box {
    let type: String
    let payload: UInt64
    let end: UInt64
  }
  private struct Field {
    let type: UInt64
    let count: UInt64
    let data: Data
  }
  private struct TIFF {
    let little: Bool
    let fields: [UInt64: Field]
    init(_ data: Data) throws {
      guard data.count >= 8,
        [Data([0x49, 0x49, 42, 0]), Data([0x4d, 0x4d, 0, 42])].contains(data.prefix(4))
      else { throw Unsupported.layout }
      little = data[0] == 0x49
      let start = Int(number(data, 4, 4, little: little))
      guard start >= 8, start <= data.count - 6 else { throw Unsupported.layout }
      let count = Int(number(data, start, 2, little: little))
      guard count <= 512, count <= (data.count - start - 6) / 12,
        number(data, start + 2 + count * 12, 4, little: little) == 0
      else { throw Unsupported.layout }
      // Only materialize the standard fields that Photo actually displays.
      let wanted: Set<UInt64> = [
        256, 257, 271, 272, 274, 33434, 33437, 34855,
        36864, 36867, 36881, 37386, 37521, 40962, 40963, 42036,
      ]
      var result: [UInt64: Field] = [:]
      for i in 0..<count {
        try Task.checkCancellation()
        let p = start + 2 + i * 12
        let tag = number(data, p, 2, little: little)
        guard wanted.contains(tag) else { continue }
        guard result[tag] == nil else { throw Unsupported.layout }
        let type = number(data, p + 2, 2, little: little)
        let n = number(data, p + 4, 4, little: little)
        let width: UInt64
        switch type {
        case 2, 7: width = 1
        case 3: width = 2
        case 4: width = 4
        case 5: width = 8
        default: throw Unsupported.layout
        }
        guard n > 0, n <= 4096, n * width <= 4096 else { throw Unsupported.layout }
        let bytes = Int(n * width)
        let offset = bytes <= 4 ? p + 8 : Int(number(data, p + 8, 4, little: little))
        guard offset >= 0, offset <= data.count, bytes <= data.count - offset else {
          throw Unsupported.layout
        }
        result[tag] = Field(type: type, count: n, data: data.subdata(in: offset..<(offset + bytes)))
      }
      fields = result
    }
    func integer(_ tag: UInt64) throws -> Int? {
      guard let f = fields[tag] else { return nil }
      guard [UInt64(3), 4].contains(f.type), f.count == 1 else { throw Unsupported.layout }
      return Int(number(f.data, 0, f.type == 3 ? 2 : 4, little: little))
    }
    func rational(_ tag: UInt64) throws -> Double? {
      guard let f = fields[tag] else { return nil }
      guard f.type == 5, f.count == 1 else { throw Unsupported.layout }
      let denominator = number(f.data, 4, 4, little: little)
      guard denominator > 0 else { throw Unsupported.layout }
      return Double(number(f.data, 0, 4, little: little)) / Double(denominator)
    }
    func text(_ tag: UInt64) throws -> String? {
      guard let f = fields[tag] else { return nil }
      guard f.type == 2, f.data.last == 0,
        !f.data.dropLast().contains(0), let text = String(data: f.data.dropLast(), encoding: .ascii)
      else { throw Unsupported.layout }
      return text
    }
  }
  private static func number(_ data: Data, _ offset: Int, _ count: Int, little: Bool = false)
    -> UInt64
  {
    var result: UInt64 = 0
    for i in 0..<count {
      result = result << 8 | UInt64(data[offset + (little ? count - i - 1 : i)])
    }
    return result
  }
  static func read(_ url: URL) throws -> Result? {
    guard url.pathExtension.lowercased() == "cr3" else { return nil }
    do {
      let reader = try BufferedContainerReader(url: url)
      return try read(reader)
    } catch is CancellationError { throw CancellationError() } catch { return nil }
  }
  static func read(_ reader: BufferedContainerReader) throws -> Result {
    var seen = 0
    func boxes(_ start: UInt64, _ end: UInt64) throws -> [Box] {
      var p = start
      var result: [Box] = []
      while p < end {
        try Task.checkCancellation()
        seen += 1
        guard seen <= 4096, end - p >= 8, let h = try reader.read(p, 8) else {
          throw Unsupported.layout
        }
        var size = number(h, 0, 4)
        var bytes: UInt64 = 8
        if size == 1 {
          guard end - p >= 16, let large = try reader.read(p + 8, 8) else {
            throw Unsupported.layout
          }
          size = number(large, 0, 8)
          bytes = 16
        } else if size == 0 {
          size = end - p
        }
        guard size >= bytes, size <= end - p else { throw Unsupported.layout }
        result.append(
          Box(type: String(decoding: h[4..<8], as: UTF8.self), payload: p + bytes, end: p + size))
        p += size
      }
      return result
    }
    let top = try boxes(0, reader.length)
    guard let brand = top.first, brand.type == "ftyp", brand.end - brand.payload >= 4,
      try reader.read(brand.payload, 4) == Data("crx ".utf8)
    else { throw Unsupported.layout }
    let uuid = Data([
      0x85, 0xc0, 0xb6, 0x87, 0x82, 0x0f, 0x11, 0xe0,
      0x81, 0x11, 0xf4, 0xce, 0x46, 0x2b, 0x6a, 0x48,
    ])
    var blocks: [String: Data] = [:]
    for movie in top where movie.type == "moov" {
      for atom in try boxes(movie.payload, movie.end)
      where atom.type == "uuid" && atom.end - atom.payload >= 16 {
        guard try reader.read(atom.payload, 16) == uuid else { continue }
        for cmt in try boxes(atom.payload + 16, atom.end) where ["CMT1", "CMT2"].contains(cmt.type)
        {
          guard blocks[cmt.type] == nil, cmt.end - cmt.payload <= 65_536,
            let bytes = try reader.read(cmt.payload, Int(cmt.end - cmt.payload))
          else { throw Unsupported.layout }
          blocks[cmt.type] = bytes
        }
      }
    }
    guard let first = blocks["CMT1"], let second = blocks["CMT2"] else { throw Unsupported.layout }
    let tiff = try TIFF(first)
    let exif = try TIFF(second)
    guard try tiff.text(271) == "Canon", let model = try tiff.text(272), !model.isEmpty,
      let width = try tiff.integer(256), let height = try tiff.integer(257), width > 0, height > 0,
      let orientation = try tiff.integer(274), (1...8).contains(orientation),
      let version = exif.fields[36864], version.type == 7, version.count == 4,
      ["0230", "0231", "0232"].contains(String(decoding: version.data, as: UTF8.self)),
      try exif.integer(40962) == width, try exif.integer(40963) == height
    else { throw Unsupported.layout }
    var values: [CFString: Any] = [:]
    values[kCGImagePropertyExifExposureTime] = try exif.rational(33434)
    values[kCGImagePropertyExifFNumber] = try exif.rational(33437)
    values[kCGImagePropertyExifFocalLength] = try exif.rational(37386)
    values[kCGImagePropertyExifLensModel] = try exif.text(42036)
    values[kCGImagePropertyExifDateTimeOriginal] = try exif.text(36867)
    if let offset = try exif.text(36881) {
      let bytes = Array(offset.utf8)
      guard bytes.count == 6, [UInt8(43), 45].contains(bytes[0]), bytes[3] == 58,
        [bytes[1], bytes[2], bytes[4], bytes[5]].allSatisfy({ (48...57).contains($0) }),
        Int(offset.dropFirst().prefix(2))! <= 23, Int(offset.suffix(2))! <= 59
      else { throw Unsupported.layout }
      values[kCGImagePropertyExifOffsetTimeOriginal] = offset
    }
    values[kCGImagePropertyExifSubsecTimeOriginal] = try exif.text(37521)
    if let iso = try exif.integer(34855) {
      guard iso > 0, iso < 65535 else { throw Unsupported.layout }
      values[kCGImagePropertyExifISOSpeedRatings] = [iso]
    }
    // Missing standard fields can still be recovered from vendor metadata by ImageIO.
    // Keep that route rather than publishing an incomplete fast-path result.
    guard let lens = values[kCGImagePropertyExifLensModel] as? String, !lens.isEmpty,
      let date = values[kCGImagePropertyExifDateTimeOriginal] as? String, !date.isEmpty,
      values[kCGImagePropertyExifISOSpeedRatings] != nil,
      [
        kCGImagePropertyExifExposureTime, kCGImagePropertyExifFNumber,
        kCGImagePropertyExifFocalLength,
      ]
      .allSatisfy({ (values[$0] as? Double ?? 0) > 0 })
    else { throw Unsupported.layout }
    return Result(
      properties: [
        kCGImagePropertyPixelWidth: width, kCGImagePropertyPixelHeight: height,
        kCGImagePropertyOrientation: orientation,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: model],
        kCGImagePropertyExifDictionary: values,
      ], io: reader.statistics)
  }
}
