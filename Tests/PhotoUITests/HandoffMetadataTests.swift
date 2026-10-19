import CryptoKit
import Foundation
import ImageIO
import PhotoCore
import PhotoImaging
import PhotoUI
import Testing
import UniformTypeIdentifiers

struct HandoffMetadataTests {
  @Test(arguments: ["jpg", "png"])
  func embedsMetadataInCopiesWithoutRecompressingPixelsOrChangingSource(_ ext: String) async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sample = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let source = root.appendingPathComponent("original." + ext)
    let imageSource = try #require(CGImageSourceCreateWithURL(sample as CFURL, nil))
    let output = try #require(
      CGImageDestinationCreateWithURL(
        source as CFURL, (ext == "jpg" ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil))
    CGImageDestinationAddImageFromSource(
      output, imageSource, 0, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(output))
    let before = try Data(contentsOf: source)
    let copy = root.appendingPathComponent("handoff." + ext)
    try FileManager.default.copyItem(at: source, to: copy)
    var patch = MetadataPatch()
    patch.fields = [.creator: "Photographer", .title: "Title & caption", .caption: "Description"]
    patch.keywordAction = .append
    patch.keywordText = "Wildlife|Birds|Heron"
    let value = try patch.applying(to: DescriptiveMetadata())
    let descriptive = try XMPSidecar.mergingMetadata(
      value, fields: Set(patch.fields.keys), keywords: true, into: nil)
    let packet = try XMPSidecar.merging(CullingDecision(rating: 4, flag: .pick), into: descriptive)
    #expect(!String(decoding: packet, as: UTF8.self).hasPrefix("<?xml "))
    #expect(
      CGImageMetadataCreateFromXMPData(packet as CFData) != nil,
      "Synthetic XMP must be accepted by ImageIO: \(String(decoding: packet, as: UTF8.self))")
    let sidecar = XMPSidecar.url(for: copy)
    try packet.write(to: sidecar)
    _ = try await HandoffMetadataWriter().embed(in: copy, sidecar: sidecar)
    #expect(try Data(contentsOf: source) == before)
    let metadata = try #require(try await ImageMetadataReader().embeddedXMP(for: copy))
    #expect(try XMPSidecar.descriptive(metadata).fields[.caption] == "Description")
    #expect(try XMPSidecar.descriptive(metadata).hierarchy == ["Wildlife|Birds|Heron"])
    #expect(try XMPSidecar.read(metadata) == CullingDecision(rating: 4, flag: .pick))
    let originalSource = try #require(CGImageSourceCreateWithURL(source as CFURL, nil))
    let derivedSource = try #require(CGImageSourceCreateWithURL(copy as CFURL, nil))
    let originalImage = try #require(CGImageSourceCreateImageAtIndex(originalSource, 0, nil))
    let derivedImage = try #require(CGImageSourceCreateImageAtIndex(derivedSource, 0, nil))
    #expect(
      originalImage.width == derivedImage.width && originalImage.height == derivedImage.height)
    #expect(originalImage.dataProvider?.data as Data? == derivedImage.dataProvider?.data as Data?)
    let originalMetadata = try await ImageMetadataReader().metadata(for: source)
    let derivedMetadata = try await ImageMetadataReader().metadata(for: copy)
    #expect(originalMetadata.pixelWidth == derivedMetadata.pixelWidth)
    #expect(originalMetadata.pixelHeight == derivedMetadata.pixelHeight)
    let cleared = try XMPSidecar.mergingMetadata(
      DescriptiveMetadata(), fields: [.title], keywords: true, into: packet)
    try cleared.write(to: sidecar)
    _ = try await HandoffMetadataWriter().embed(in: copy, sidecar: sidecar)
    let clearedXMP = try #require(try await ImageMetadataReader().embeddedXMP(for: copy))
    #expect(try XMPSidecar.descriptive(clearedXMP).keywords.isEmpty)
    #expect(try XMPSidecar.descriptive(clearedXMP).hierarchy.isEmpty)
    #expect(try XMPSidecar.descriptive(clearedXMP).fields[.title, default: ""].isEmpty)
    #expect(try Data(contentsOf: source) == before)
  }
  @Test func keywordAppendIncludesEmbeddedValuesAndExplicitClearSuppressesThem() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("test.png")
    try Data("fixture".utf8).write(to: image)
    var original = MetadataPatch()
    original.fields = [.creator: "Original author", .title: "Original title"]
    original.keywordAction = .append
    original.keywordText = "Existing"
    let embedded = try XMPSidecar.mergingMetadata(
      original.applying(to: DescriptiveMetadata()), fields: Set(original.fields.keys),
      keywords: true, into: nil)
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db"))
    _ = try await store.load(for: image)
    _ = try await store.save(CullingDecision(rating: 3), for: image)
    var append = MetadataPatch()
    append.keywordAction = .append
    append.keywordText = "New"
    let plans = try await store.prepareMetadata(
      append, images: [image], embedded: [image.path: embedded])
    #expect(try #require(plans.first).after.keywords == ["Existing", "New"])
    #expect(try await store.saveMetadata(try #require(plans.first)).status == "Saved")
    var clear = MetadataPatch()
    clear.fields = [.title: ""]
    clear.keywordAction = .clear
    let clearing = try await store.prepareMetadata(
      clear, images: [image], embedded: [image.path: embedded])
    _ = try await store.saveMetadata(try #require(clearing.first))
    let read = try await store.loadMetadata(for: image, embedded: embedded)
    #expect(read.value.keywords.isEmpty)
    #expect(read.value.fields[.title] == "")
    #expect(read.value.fields[.creator] == "Original author")
  }
}
