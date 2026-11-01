import Darwin
import Foundation
import PhotoCore
import PhotoImaging

/// No paths, personal field values or pixels in reports. Hashing warms filesystem caches.
enum MetadataIndexingBenchmark {
  struct CanonReport: Encodable {
    let nativeEnabled: Bool
    let firstMilliseconds: Double
    let cachedMilliseconds: [Double]
    let statistics: MetadataReadStatistics
    let width: Int
    let height: Int
    let hasISO: Bool
    let hasCaptureTime: Bool
    let hasOffset: Bool
    let publicCommonFieldsMatch: Bool?
    let publicISOAndTimeMatch: Bool?
    let originalsUnchanged: Bool
    let peakResidentMiB: Double
  }
  static func canon(_ file: URL, native: Bool) async throws -> CanonReport {
    let before = try MediaOperations.checksum(file)
    let reader = ImageMetadataReader(nativeCanon: native)
    let start = ContinuousClock.now
    let value = try await reader.metadata(for: file)
    let first = ms(start)
    var hits: [Double] = []
    for _ in 0..<8 {
      let start = ContinuousClock.now
      let repeated = try await reader.metadata(for: file)
      hits.append(ms(start))
      guard repeated == value else { throw MediaOperationError.invalid("Cached metadata differs.") }
    }
    var reference: Bool?
    var common: Bool?
    if before == "89bd55532b0cceb5efa360e97827ba35c2076bce0de4675f3a4413a883dac880" {
      let clock = ISO8601DateFormatter()
      clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      let expected = clock.date(from: "2021-05-10T14:58:48.050Z")!
      common =
        value.pixelWidth == 6720 && value.pixelHeight == 4480
        && value.camera == "Canon EOS R" && value.lens == "RF85mm F2 MACRO IS STM"
        && value.exposureTime == 1.0 / 6 && value.aperture == 11 && value.focalLength == 85
      reference =
        value.iso == 100
        && abs((value.captureTime ?? .distantPast).timeIntervalSince(expected)) < 0.00001
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return CanonReport(
      nativeEnabled: native, firstMilliseconds: first, cachedMilliseconds: hits,
      statistics: await reader.statistics, width: value.pixelWidth, height: value.pixelHeight,
      hasISO: value.iso != nil, hasCaptureTime: value.captureTime != nil,
      hasOffset: value.captureTimeText?.contains(" +") == true
        || value.captureTimeText?.contains(" -") == true,
      publicCommonFieldsMatch: common, publicISOAndTimeMatch: reference,
      originalsUnchanged: try MediaOperations.checksum(file) == before,
      peakResidentMiB: Double(usage.ru_maxrss) / 1_048_576)
  }
  struct SidecarPass: Encodable {
    let reuseEnabled: Bool
    let milliseconds: [Double]
    let statistics: XMPReadStatistics
    let valuesMatch: Bool
  }
  struct SidecarReport: Encodable {
    let schemaVersion = 1
    let generatedFiles: Int
    let visitsPerPass: Int
    let packetBytes: Int
    let passes: [SidecarPass]
    let originalsUnchanged: Bool
    let notes: [String]
  }
  static func sidecars() async throws -> SidecarReport {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var files: [URL] = []
    var hashes: [String] = []
    var sidecarHashes: [String] = []
    var packetBytes = 0
    for i in 0..<16 {
      let file = root.appendingPathComponent("generated-\(i).jpg")
      // Regular placeholders: this measures persistence/XML only, never pixel decoding.
      try Data([1, 2, 3, UInt8(i)]).write(to: file)
      let records = (0..<160).map {
        "<rdf:li>Generated history entry \($0) with unrelated settings</rdf:li>"
      }.joined()
      let packet = Data(
        ("<rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description xmlns:xmp='http://ns.adobe.com/xap/1.0/' xmlns:dc='http://purl.org/dc/elements/1.1/' xmlns:crs='http://ns.adobe.com/camera-raw-settings/1.0/' xmp:Rating='3'><dc:title>Generated \(i)</dc:title><crs:History><rdf:Seq>"
          + records + "</rdf:Seq></crs:History></rdf:Description></rdf:RDF>").utf8)
      let sidecar = XMPSidecar.url(for: file)
      try packet.write(to: sidecar)
      files.append(file)
      hashes.append(try MediaOperations.checksum(file))
      sidecarHashes.append(try MediaOperations.checksum(sidecar))
      packetBytes += packet.count
    }
    var passes: [SidecarPass] = []
    for (iteration, reuse) in [false, true, true, false].enumerated() {
      let store = DecisionStore(
        databaseURL: root.appendingPathComponent("pass-\(iteration).sqlite"),
        xmpCacheEntryLimit: reuse ? 128 : 0)
      // Initialize SQLite, decision baselines and panel records outside timed repeated visits.
      for file in files { _ = try await store.loadMetadata(for: file) }
      var times: [Double] = []
      var valid = true
      for i in 0..<256 {
        let index = i % files.count
        let start = ContinuousClock.now
        let value = try await store.loadMetadata(for: files[index])
        times.append(ms(start))
        valid =
          valid && value.value.fields[.title] == "Generated \(index)" && value.status == "Saved"
      }
      passes.append(
        SidecarPass(
          reuseEnabled: reuse, milliseconds: times,
          statistics: await store.xmpReadStatistics, valuesMatch: valid))
    }
    let unchanged = try files.enumerated().allSatisfy {
      try MediaOperations.checksum($0.element) == hashes[$0.offset]
        && MediaOperations.checksum(XMPSidecar.url(for: $0.element)) == sidecarHashes[$0.offset]
    }
    guard unchanged, passes.allSatisfy(\.valuesMatch) else {
      throw MediaOperationError.invalid(
        "Sidecar benchmark changed sources or returned wrong fields.")
    }
    return SidecarReport(
      generatedFiles: 16, visitsPerPass: 256, packetBytes: packetBytes,
      passes: passes, originalsUnchanged: unchanged,
      notes: [
        "Current-code cache off/on/on/off controls, generated regular placeholders and 160 unrelated XML history entries per packet; no photographic decode.",
        "SQLite setup and first reads excluded from visit timings; fresh filesystem reads, source/sidecar safety checks and unchanged persistence work remain in every control.",
        "Typed parse results only are cached. Packet equality guards digest keys; no XML merge/write validation is bypassed.",
        "Filesystem caches/background load are uncontrolled. These service timings are not native frame, physical-media, cold-RAW, large-shoot or whole-process-memory evidence.",
      ])
  }
  private static func ms(_ start: ContinuousClock.Instant) -> Double {
    let v = start.duration(to: .now).components
    return Double(v.seconds) * 1000 + Double(v.attoseconds) / 1e15
  }
}
