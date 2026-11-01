import CryptoKit
import Foundation
import ImageIO
import PhotoCore
import Testing

@testable import PhotoImaging
@testable import PhotoUI

struct CanonMetadataTests {
  private func directory() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
  private func integer(_ n: UInt64, _ width: Int, _ little: Bool = false) -> Data {
    Data((0..<width).map { UInt8(truncatingIfNeeded: n >> (8 * (little ? $0 : width - $0 - 1))) })
  }
  private func box(_ type: String, _ data: Data) -> Data {
    integer(UInt64(data.count + 8), 4) + Data(type.utf8) + data
  }
  private func tiff(_ fields: [(Int, Int, Int, Data)], little: Bool) -> Data {
    let end = 8 + 2 + fields.count * 12 + 4
    var result = Data(little ? [0x49, 0x49, 42, 0] : [0x4d, 0x4d, 0, 42]) + integer(8, 4, little)
    result += integer(UInt64(fields.count), 2, little)
    var payload = Data()
    for (tag, type, count, data) in fields.sorted(by: { $0.0 < $1.0 }) {
      result += integer(UInt64(tag), 2, little) + integer(UInt64(type), 2, little)
      result += integer(UInt64(count), 4, little)
      if data.count <= 4 {
        result += data + Data(repeating: 0, count: 4 - data.count)
      } else {
        result += integer(UInt64(end + payload.count), 4, little)
        payload += data
      }
    }
    return result + Data(repeating: 0, count: 4) + payload
  }
  private func fixture(
    little: Bool = true, orientation: Int = 1, offset: String = "+05:30",
    iso: Int = 640, duplicate: Bool = false, omittedField: Int? = nil
  ) -> Data {
    func short(_ tag: Int, _ n: Int, _ endian: Bool) -> (Int, Int, Int, Data) {
      (tag, 3, 1, integer(UInt64(n), 2, endian))
    }
    func text(_ tag: Int, _ s: String) -> (Int, Int, Int, Data) {
      let d = Data(s.utf8) + Data([0])
      return (tag, 2, d.count, d)
    }
    func rational(_ tag: Int, _ a: Int, _ b: Int) -> (Int, Int, Int, Data) {
      (tag, 5, 1, integer(UInt64(a), 4, !little) + integer(UInt64(b), 4, !little))
    }
    let first = tiff(
      [
        short(256, 6000, little), short(257, 4000, little), short(274, orientation, little),
        text(271, "Canon"), text(272, "Generated Canon"),
      ], little: little)
    var fields = [
      short(34855, iso, !little), short(40962, 6000, !little), short(40963, 4000, !little),
      (36864, 7, 4, Data("0231".utf8)), text(36867, "2026:10:30 12:00:00"),
      text(36881, offset), text(37521, "125"), text(42036, "Generated lens"),
      rational(33434, 1, 250), rational(33437, 28, 10), rational(37386, 85, 1),
    ]
    if duplicate { fields.append(short(34855, iso, !little)) }
    if let omittedField { fields.removeAll { $0.0 == omittedField } }
    let uuid = Data([
      0x85, 0xc0, 0xb6, 0x87, 0x82, 0x0f, 0x11, 0xe0, 0x81, 0x11, 0xf4, 0xce, 0x46, 0x2b, 0x6a,
      0x48,
    ])
    return box("ftyp", Data("crx ".utf8))
      + box(
        "moov",
        box(
          "uuid",
          uuid + box("CMT1", first)
            + box("CMT2", tiff(fields, little: !little))))
  }
  @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8])
  func standardFieldsMixedEndianOrientationAndOffsets(_ orientation: Int) async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("generated.Cr3")
    let bytes = fixture(little: orientation.isMultiple(of: 2), orientation: orientation)
    try bytes.write(to: file)
    let reader = ImageMetadataReader()
    let value = try await reader.metadata(for: file)
    #expect(value.pixelWidth == (orientation >= 5 ? 4000 : 6000))
    #expect(value.pixelHeight == (orientation >= 5 ? 6000 : 4000))
    #expect(value.camera == "Generated Canon" && value.lens == "Generated lens")
    #expect(
      value.iso == 640 && value.exposureTime == 0.004 && value.aperture == 2.8
        && value.focalLength == 85)
    let clock = ISO8601DateFormatter()
    clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    #expect(value.captureTime == clock.date(from: "2026-10-30T06:30:00.125Z"))
    #expect(value.captureTimeText == "2026:10:30 12:00:00 +05:30")
    #expect(try await reader.metadata(for: file) == value)
    let stats = await reader.statistics
    #expect(stats.nativeCanonReads == 1 && stats.exifHits == 1 && stats.sourceCreations == 0)
    #expect(try Data(contentsOf: file) == bytes)
    // Negative offsets and a missing-sign/unknown representation must not be mistaken for UTC.
    try fixture(offset: "-03:30").write(to: file)
    await reader.clear()
    let negative = try await reader.metadata(for: file)
    #expect(negative.captureTime == clock.date(from: "2026-10-30T15:30:00.125Z"))
  }
  @Test
  func unsupportedInvalidAndDuplicateFieldsFallBackRatherThanGuess() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("generated.cr3")
    var badOffset = fixture()
    let marker = try #require(badOffset.range(of: Data("CMT2".utf8)))
    let pointer = marker.upperBound + 4
    badOffset.replaceSubrange(pointer..<(pointer + 4), with: Data(repeating: 255, count: 4))
    var newerVersion = fixture()
    let version = try #require(newerVersion.range(of: Data("0231".utf8)))
    newerVersion.replaceSubrange(version, with: Data("0300".utf8))
    var zeroDenominator = fixture()
    let rational = try #require(zeroDenominator.range(of: Data([0, 0, 0, 1, 0, 0, 0, 250])))
    zeroDenominator.replaceSubrange(
      (rational.upperBound - 4)..<rational.upperBound, with: Data(repeating: 0, count: 4))
    for bytes in [
      badOffset, newerVersion, zeroDenominator,
      fixture(omittedField: 42036), fixture(omittedField: 34855), fixture(omittedField: 33437),
      fixture(offset: "bad"), fixture(offset: "+24:00"), fixture(offset: "+00:60"),
      fixture(iso: 65535), fixture(duplicate: true),
      Data([0, 0, 0, 1, 0x6d, 0x6f, 0x6f, 0x76]), Data(repeating: 0, count: 8),
    ] {
      try bytes.write(to: file)
      #expect(try CanonEXIFReader.read(file) == nil)
    }
  }
  @Test
  func sparseSensorDataIsSkippedAndCancellationIsNotFallback() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("generated.cr3")
    var bytes = fixture()
    bytes += integer(8 * 1024 * 1024, 4) + Data("mdat".utf8)
    try bytes.write(to: file)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: UInt64(bytes.count + 8 * 1024 * 1024 - 8))
    try handle.close()
    let before = SHA256.hash(data: try Data(contentsOf: file))
    let result = try #require(try CanonEXIFReader.read(file))
    #expect(result.io.bytesRead < 16 * 1024 && result.io.largestRead <= 4096)
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try CanonEXIFReader.read(file) != nil
    }
    do {
      _ = try await cancelled.value
      Issue.record("Cancelled metadata read completed")
    } catch is CancellationError {} catch { Issue.record("Cancellation became a different error") }
    #expect(try CanonEXIFReader.read(file) != nil)
    #expect(SHA256.hash(data: try Data(contentsOf: file)) == before)
  }
  @Test
  func nativeCacheStillRejectsChangesAndUnknownContainersUseImageIO() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("generated.cr3")
    try fixture().write(to: file)
    let reader = ImageMetadataReader()
    _ = try await reader.metadata(for: file)
    await reader.setValidationProbe { try Data([0]).write(to: file) }
    do {
      _ = try await reader.metadata(for: file)
      Issue.record("Stale native metadata returned")
    } catch DecisionStoreError.fileChanged {} catch { Issue.record("Wrong replacement error") }
    await reader.setValidationProbe(nil)
    let sample = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    try Data(contentsOf: sample).write(to: file)
    let info = try await reader.metadata(for: file)
    #expect(info.pixelWidth == 640 && info.pixelHeight == 400)
    #expect(await reader.statistics.propertyReads == 1)
  }
}
