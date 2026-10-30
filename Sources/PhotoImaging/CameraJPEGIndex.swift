import Foundation

/// Format fields only: bounded classic TIFF/SubIFDs and single-sample CR3 JPEG tracks.
/// Does not scan sensor payloads, unpack RAW, or copy a third-party decoder.
struct CameraJPEGIndex {
  struct Range: Equatable {
    let offset: UInt64
    let count: Int
  }
  struct Frame {
    let range: Range
    let width: Int
    let height: Int
  }
  let reader: BufferedContainerReader
  init(reader: BufferedContainerReader) { self.reader = reader }
  private var entries = 0
  private var boxesSeen = 0
  private(set) var orientation: Int?
  private(set) var ranges: [Range] = []
  private func number(_ data: Data, _ start: Int, _ count: Int, little: Bool = false) -> UInt64 {
    var result: UInt64 = 0
    for index in 0..<count {
      result = (result << 8) | UInt64(data[start + (little ? count - index - 1 : index)])
    }
    return result
  }
  mutating func tiff(base: UInt64 = 0, length: UInt64? = nil) throws {
    let length = length ?? reader.length
    guard length >= 8, base <= reader.length, length <= reader.length - base,
      let header = try reader.read(base, 8),
      [
        Data([0x49, 0x49, 0x2a, 0]), Data([0x4d, 0x4d, 0, 0x2a]),
        Data([0x49, 0x49, 0x52, 0x4f]), Data([0x49, 0x49, 0x53, 0x52]),
      ].contains(header.prefix(4))
    else { throw CameraPreviewError.unavailable }
    let little = header[0] == 0x49
    func read(_ offset: UInt64, _ count: Int) throws -> Data? {
      guard offset <= length, UInt64(count) <= length - offset else { return nil }
      return try reader.read(base + offset, count)
    }
    var pending = [number(header, 4, 4, little: little)]
    var visited = Set<UInt64>()
    while let offset = pending.popLast() {
      try Task.checkCancellation()
      guard offset != 0, !visited.contains(offset) else { continue }
      guard visited.count < 64, let countData = try read(offset, 2) else {
        throw CameraPreviewError.unavailable
      }
      visited.insert(offset)
      let count = Int(number(countData, 0, 2, little: little))
      entries += count
      guard count <= 4096, entries <= 16_384,
        let data = try read(offset + 2, count * 12 + 4)
      else { throw CameraPreviewError.unavailable }
      var tags: [UInt64: UInt64] = [:]
      for i in 0..<count {
        let p = i * 12
        let tag = number(data, p, 2, little: little)
        let type = number(data, p + 2, 2, little: little)
        let values = number(data, p + 4, 4, little: little)
        guard type == 3 || type == 4 else { continue }
        let value = number(data, p + 8, type == 3 && values == 1 ? 2 : 4, little: little)
        if values == 1 { tags[tag] = value }
        if tag == 330 {
          guard type == 4, values > 0, values <= 64 else { throw CameraPreviewError.unavailable }
          if values == 1 {
            pending.append(value)
          } else {
            guard let children = try read(value, Int(values) * 4) else {
              throw CameraPreviewError.unavailable
            }
            for j in 0..<Int(values) { pending.append(number(children, j * 4, 4, little: little)) }
          }
        }
      }
      if let value = tags[274] {
        guard (1...8).contains(value) else { throw CameraPreviewError.unavailable }
        // IFD0 orientation is authoritative; preview IFDs often simply say 1.
        if orientation == nil { orientation = Int(value) }
      }
      if let start = tags[513], let size = tags[514] {
        try add(base + start, size, end: base + length)
      } else if tags[259] == 6, let start = tags[273], let size = tags[279] {
        try add(base + start, size, end: base + length)
      }
      pending.append(number(data, count * 12, 4, little: little))
    }
  }
  private mutating func add(_ offset: UInt64, _ count: UInt64, end: UInt64) throws {
    guard count >= 4, count <= 64 * 1024 * 1024, offset <= end, count <= end - offset else {
      return
    }
    let range = Range(offset: offset, count: Int(count))
    guard !ranges.contains(range) else { return }
    guard ranges.count < 64 else { throw CameraPreviewError.unavailable }
    ranges.append(range)
  }
  struct Box {
    let type: String
    let payload: UInt64
    let end: UInt64
  }
  private mutating func boxes(_ start: UInt64, _ end: UInt64) throws -> [Box] {
    var result: [Box] = []
    var p = start
    while p < end {
      boxesSeen += 1
      guard boxesSeen <= 4096, end - p >= 8, let header = try reader.read(p, 8) else {
        throw CameraPreviewError.unavailable
      }
      var size = number(header, 0, 4)
      var bytes: UInt64 = 8
      if size == 1 {
        guard end - p >= 16, let extended = try reader.read(p + 8, 8) else {
          throw CameraPreviewError.unavailable
        }
        size = number(extended, 0, 8)
        bytes = 16
      } else if size == 0 {
        size = end - p
      }
      guard size >= bytes, size <= end - p else { throw CameraPreviewError.unavailable }
      result.append(
        Box(type: String(decoding: header[4..<8], as: UTF8.self), payload: p + bytes, end: p + size)
      )
      p += size
    }
    return result
  }
  mutating func cr3() throws {
    let top = try boxes(0, reader.length)
    guard let brand = top.first, brand.type == "ftyp", brand.end - brand.payload >= 4,
      try reader.read(brand.payload, 4) == Data("crx ".utf8)
    else { throw CameraPreviewError.unavailable }
    let media = top.filter { $0.type == "mdat" }
    let metadataUUID = Data([
      0x85, 0xc0, 0xb6, 0x87, 0x82, 0x0f, 0x11, 0xe0, 0x81, 0x11, 0xf4, 0xce, 0x46, 0x2b, 0x6a,
      0x48,
    ])
    for movie in top where movie.type == "moov" {
      let children = try boxes(movie.payload, movie.end)
      for child in children {
        if child.type == "uuid", child.end - child.payload >= 16,
          try reader.read(child.payload, 16) == metadataUUID
        {
          for cmt in try boxes(child.payload + 16, child.end) where cmt.type == "CMT1" {
            try tiff(base: cmt.payload, length: cmt.end - cmt.payload)
          }
        }
        guard child.type == "trak" else { continue }
        for mdia in try boxes(child.payload, child.end) where mdia.type == "mdia" {
          for minf in try boxes(mdia.payload, mdia.end) where minf.type == "minf" {
            for stbl in try boxes(minf.payload, minf.end) where stbl.type == "stbl" {
              let table = try boxes(stbl.payload, stbl.end)
              guard let stsd = table.first(where: { $0.type == "stsd" }),
                stsd.end - stsd.payload >= 16,
                let header = try reader.read(stsd.payload, 16), number(header, 4, 4) == 1
              else { continue }
              let sample = stsd.payload + 8
              let size = number(header, 8, 4)
              let type = String(decoding: header[12..<16], as: UTF8.self)
              guard size >= 8, size <= stsd.end - sample else { continue }
              var jpeg = type == "jpeg" || type == "JPEG"
              if type == "CRAW", size >= 98 {
                jpeg = try boxes(sample + 90, sample + size).contains(where: { $0.type == "JPEG" })
              }
              guard jpeg, let stsz = table.first(where: { $0.type == "stsz" }),
                stsz.end - stsz.payload >= 12,
                let sizes = try reader.read(stsz.payload, 12), number(sizes, 8, 4) == 1,
                let stsc = table.first(where: { $0.type == "stsc" }), stsc.end - stsc.payload >= 20,
                let chunks = try reader.read(stsc.payload, 20), number(chunks, 4, 4) == 1,
                number(chunks, 8, 4) == 1, number(chunks, 12, 4) == 1, number(chunks, 16, 4) == 1,
                let offsets = table.first(where: { $0.type == "co64" || $0.type == "stco" })
              else { continue }
              var count = number(sizes, 4, 4)
              if count == 0 {
                guard stsz.end - stsz.payload >= 16,
                  let entry = try reader.read(stsz.payload + 12, 4)
                else { continue }
                count = number(entry, 0, 4)
              }
              let width = offsets.type == "co64" ? 8 : 4
              guard offsets.end - offsets.payload >= UInt64(8 + width),
                let chunk = try reader.read(offsets.payload, 8 + width),
                number(chunk, 4, 4) == 1
              else { continue }
              let start = number(chunk, 8, width)
              guard
                media.contains(where: {
                  start >= $0.payload && start <= $0.end && count <= $0.end - start
                })
              else { continue }
              try add(start, count, end: reader.length)
            }
          }
        }
      }
    }
  }
  func frame(_ range: Range) throws -> Frame? {
    guard let soi = try reader.read(range.offset, 2), soi == Data([0xff, 0xd8]) else { return nil }
    var p: UInt64 = 2
    for _ in 0..<128 {
      guard p + 4 <= UInt64(range.count), let header = try reader.read(range.offset + p, 4),
        header[0] == 0xff
      else { return nil }
      let marker = header[1]
      if marker == 0xff {
        p += 1
        continue
      }
      guard marker != 0xda, marker != 0xd9, marker != 0x00 else { return nil }
      if marker == 0x01 || (0xd0...0xd7).contains(marker) {
        p += 2
        continue
      }
      let count = number(header, 2, 2)
      guard count >= 2, count <= UInt64(range.count) - p - 2 else { return nil }
      if [0xc0, 0xc1, 0xc2].contains(marker) {
        guard count >= 17, let info = try reader.read(range.offset + p + 4, 6), info[0] == 8,
          info[5] == 3
        else { return nil }
        let height = Int(number(info, 1, 2))
        let width = Int(number(info, 3, 2))
        guard width > 0, height > 0 else { return nil }
        return Frame(range: range, width: width, height: height)
      }
      if (0xc0...0xcf).contains(marker), ![0xc4, 0xc8, 0xcc].contains(marker) { return nil }
      p += 2 + count
    }
    return nil
  }
}
