import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import PhotoCore
import Testing
import UniformTypeIdentifiers

@testable import PhotoImaging
@testable import PhotoUI

struct MetadataReuseTests {
  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  private func image(_ url: URL, model: String = "Synthetic A", png: Bool = false) throws {
    let context = try #require(
      CGContext(
        data: nil, width: 12, height: 8, bitsPerComponent: 8,
        bytesPerRow: 48, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
    let destination = try #require(
      CGImageDestinationCreateWithURL(
        url as CFURL,
        (png ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil))
    let properties: [CFString: Any] =
      png
      ? [:]
      : [
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: model],
        kCGImagePropertyExifDictionary: [
          kCGImagePropertyExifISOSpeedRatings: [640],
          kCGImagePropertyExifExposureTime: 0.004,
          kCGImagePropertyExifDateTimeOriginal: "2026:10:27 10:30:00",
        ],
        kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCObjectName: model],
      ]
    CGImageDestinationAddImage(
      destination, try #require(context.makeImage()), properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
  }
  @Test(arguments: [false, true])
  func bothOrdersShareOneSourceAndThenUseValidatedResults(_ xmpFirst: Bool) async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("sample.jpg")
    try image(file)
    let before = try Data(contentsOf: file)
    let reader = ImageMetadataReader()
    if xmpFirst { _ = try await reader.embeddedXMP(for: file) }
    let metadata = try await reader.metadata(for: file)
    let packet = try await reader.embeddedXMP(for: file)
    #expect(metadata.camera == "Synthetic A" && metadata.iso == 640)
    #expect(try XMPSidecar.descriptive(packet).fields[.title] == "Synthetic A")
    #expect(try await reader.metadata(for: file) == metadata)
    #expect(try await reader.embeddedXMP(for: file) == packet)
    let stats = await reader.statistics
    #expect(stats.sourceCreations == 1 && stats.sourceReuses == 1)
    #expect(stats.propertyReads == 1 && stats.xmpReads == 1)
    #expect(stats.exifHits == 1 && stats.xmpHits >= 1)
    #expect(stats.retainedSources == 0)
    #expect(try Data(contentsOf: file) == before)
  }
  @Test(arguments: [false, true])
  func replacementOrInPlaceEditPreservingSizeAndModificationTimeCannotReuseOldFields(
    _ inPlace: Bool
  ) async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("sample.jpg")
    try image(file)
    let reader = ImageMetadataReader()
    #expect(try await reader.metadata(for: file).camera == "Synthetic A")
    var before = stat()
    #expect(lstat(file.path, &before) == 0)
    let replacement = root.appendingPathComponent("replacement.jpg")
    try image(replacement, model: "Synthetic B")
    let newBytes = try Data(contentsOf: replacement)
    #expect(try Data(contentsOf: file).count == newBytes.count)
    if inPlace {
      let writer = try FileHandle(forWritingTo: file)
      try writer.write(contentsOf: newBytes)
      try writer.close()
    } else {
      _ = try FileManager.default.replaceItemAt(file, withItemAt: replacement)
    }
    // Set exact timestamps on the final file, independent of Foundation's
    // replacement-attribute policy and Date's floating-point precision.
    let times = [before.st_atimespec, before.st_mtimespec]
    let status = times.withUnsafeBufferPointer { utimensat(AT_FDCWD, file.path, $0.baseAddress, 0) }
    #expect(status == 0)
    var after = stat()
    #expect(lstat(file.path, &after) == 0)
    #expect(after.st_size == before.st_size)
    #expect(after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec)
    #expect(after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec)
    if inPlace { #expect(after.st_ino == before.st_ino) }
    #expect(try await reader.metadata(for: file).camera == "Synthetic B")
    #expect(
      try XMPSidecar.descriptive(await reader.embeddedXMP(for: file)).fields[.title]
        == "Synthetic B")
    #expect(await reader.statistics.sourceCreations == 2)
  }
  @Test(arguments: [false, true])
  func changesDuringReadOrCacheValidationAreRejected(_ cached: Bool) async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("sample.jpg")
    try image(file)
    let reader = ImageMetadataReader()
    if cached { _ = try await reader.metadata(for: file) }
    await reader.setValidationProbe {
      try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)], ofItemAtPath: file.path)
    }
    await #expect(throws: DecisionStoreError.self) { try await reader.metadata(for: file) }
    #expect(await reader.statistics.cachedEntries == 0)
    #expect(await reader.statistics.retainedSources == 0)
    await reader.setValidationProbe(nil)
    #expect(try await reader.metadata(for: file).camera == "Synthetic A")
  }
  @Test func boundedLRUAndDisabledControlDoNotGrowWithFolderSize() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let files = (0..<4).map { root.appendingPathComponent("\($0).jpg") }
    for file in files { try image(file) }
    let reader = ImageMetadataReader(entryLimit: 2, byteLimit: 4096)
    for index in [0, 1, 0, 2, 0, 1] { _ = try await reader.metadata(for: files[index]) }
    #expect(await reader.statistics.sourceCreations == 4)
    #expect(await reader.statistics.exifHits == 2)
    #expect(await reader.statistics.cachedEntries == 2)
    #expect(await reader.statistics.cachedResultBytes <= 4096)
    let control = ImageMetadataReader(entryLimit: 0)
    for _ in 0..<3 { _ = try await control.metadata(for: files[0]) }
    #expect(await control.statistics.sourceCreations == 3)
    #expect(await control.statistics.cachedEntries == 0)
    #expect(await control.statistics.retainedSources == 0)
  }
  @Test func failedReadsAndSymbolicAliasesDoNotPopulateResultCache() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("sample.jpg")
    try Data("not an image".utf8).write(to: file)
    let reader = ImageMetadataReader()
    await #expect(throws: PreviewError.self) { try await reader.metadata(for: file) }
    #expect(await reader.statistics.cachedEntries == 0)
    try image(file)
    #expect(try await reader.metadata(for: file).camera == "Synthetic A")
    let before = await reader.statistics.sourceCreations
    let alias = root.appendingPathComponent("alias.jpg")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
    for _ in 0..<2 { #expect(try await reader.metadata(for: alias).camera == "Synthetic A") }
    #expect(await reader.statistics.sourceCreations == before + 2)
    #expect(await reader.statistics.cachedEntries == 1)
  }
  @Test func oversizedPacketsBypassCacheAndClearReleasesEverything() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("sample.jpg")
    try image(file, model: String(repeating: "a", count: 6000))
    let reader = ImageMetadataReader(byteLimit: 512)
    let packet = try await reader.embeddedXMP(for: file)
    #expect(try #require(packet).count > 512)
    #expect(await reader.statistics.cachedEntries == 0)
    #expect(await reader.statistics.retainedSources == 0)
    let normal = root.appendingPathComponent("normal.jpg")
    try image(normal)
    _ = try await reader.metadata(for: normal)
    #expect(await reader.statistics.cachedEntries == 1)
    await reader.clear()
    #expect(await reader.statistics.cachedEntries == 0)
    #expect(await reader.statistics.cachedResultBytes == 0)
    #expect(await reader.statistics.retainedSources == 0)
    _ = try await reader.metadata(for: normal)
    #expect(await reader.statistics.propertyReads == 2)
  }
  @Test func emptyDescriptiveFieldsAreCachedAndCancelledCallDoesNotReadProperties() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("plain.png")
    try image(file, png: true)
    let reader = ImageMetadataReader()
    // ImageIO can synthesize structural XMP even for an untagged PNG.
    // Assert empty descriptive values without assuming a nil packet.
    let packet = try await reader.embeddedXMP(for: file)
    #expect(try XMPSidecar.descriptive(packet).fields[.title] == nil)
    #expect(try await reader.embeddedXMP(for: file) == packet)
    #expect(await reader.statistics.xmpReads == 1)
    let gate = AsyncStream<Void>.makeStream()
    let task = Task {
      for await _ in gate.stream {}
      return try await reader.metadata(for: file)
    }
    task.cancel()
    gate.continuation.finish()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await reader.statistics.propertyReads == 0)
  }
  @MainActor @Test func workflowRefreshReusesEmbeddedPacketButReadsExternalSidecarAgain()
    async throws
  {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("photos")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("sample.jpg")
    try image(file)
    let store = DecisionStore(databaseURL: root.appendingPathComponent("decisions.sqlite"))
    let state = WorkspaceState(decisionStore: store)
    await state.openFolder(folder)
    let reader = ImageMetadataReader()
    let operations = MediaOperations(journalDirectory: root.appendingPathComponent("operations"))
    let model = WorkflowModel(workspace: state, mediaOperations: operations, metadataReader: reader)
    await state.indexMetadata(using: reader)
    await model.refresh()
    #expect(model.currentMetadata.fields[.title] == "Synthetic A")
    var changed = DescriptiveMetadata()
    changed.fields[.title] = "External edit"
    let sidecar = try XMPSidecar.mergingMetadata(
      changed, fields: [.title], keywords: false, into: nil)
    try sidecar.write(to: XMPSidecar.url(for: file), options: .atomic)
    await model.refresh()
    #expect(model.currentMetadata.fields[.title] == "External edit")
    #expect(await reader.statistics.sourceCreations == 1)
    #expect(await reader.statistics.xmpHits == 1)
  }
  @Test func sourceLeaseExpiresAndDoesNotRetainReader() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("sample.jpg")
    try image(file)
    var reader: ImageMetadataReader? = ImageMetadataReader()
    weak var weakReader: ImageMetadataReader?
    weakReader = reader
    _ = try await reader?.metadata(for: file)
    #expect(await reader?.statistics.retainedSources == 1)
    // A loaded CI executor can resume the test after its entire wall-clock
    // deadline, before the background lease gets a turn. Allow bounded polling
    // opportunities instead; keep the idle release/cache/deallocation assertions.
    for _ in 0..<100 {
      if await reader?.statistics.retainedSources == 0 { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    #expect(await reader?.statistics.retainedSources == 0)
    #expect(await reader?.statistics.cachedEntries == 1)
    reader = nil
    for _ in 0..<100 {
      if weakReader == nil { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(weakReader == nil)
  }
}
