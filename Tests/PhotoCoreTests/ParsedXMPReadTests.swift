import Darwin
import Foundation
import Testing

@testable import PhotoCore

struct ParsedXMPReadTests {
  private func packet(_ title: String, rating: Int = 3) throws -> Data {
    var value = DescriptiveMetadata()
    value.fields[.title] = title
    value.keywords = ["Wedding"]
    value.keywordsPresent = true
    let original = try XMPSidecar.merging(CullingDecision(rating: rating, flag: .pick), into: nil)
    return try XMPSidecar.mergingMetadata(value, fields: [.title], keywords: true, into: original)
  }
  @Test
  func valuesAreLazyImmutableAndExactBytesGuardDigestCollisions() throws {
    let cache = ParsedXMPReads()
    let a = try packet("First")
    let b = try packet("Other", rating: 5)
    #expect(try cache.decision(a, digest: "same").rating == 3)
    #expect(try cache.decision(b, digest: "same").rating == 5)
    #expect(try cache.decision(b, digest: "same").flag == .pick)
    var value = try cache.descriptive(b)
    value.fields[.title] = "Mutation"
    #expect(try cache.descriptive(b).fields[.title] == "Other")
    #expect(cache.statistics.decisionParses == 2 && cache.statistics.decisionHits == 1)
    #expect(cache.statistics.descriptiveParses == 1 && cache.statistics.descriptiveHits == 1)
  }
  @Test
  func budgetsEvictionDisabledCacheErrorsAndEmptyOverlayArePreserved() throws {
    let cache = ParsedXMPReads(entryLimit: 2)
    let a = try packet("A")
    let b = try packet("B")
    let c = try packet("C")
    for d in [a, b, a, c, b] { _ = try cache.decision(d) }
    #expect(cache.statistics.entries == 2 && cache.statistics.evictions == 2)
    for limit in [0, 1] {
      let disabled = ParsedXMPReads(entryLimit: limit, byteLimit: limit)
      _ = try disabled.descriptive(a)
      _ = try disabled.descriptive(a)
      #expect(disabled.statistics.entries == 0 && disabled.statistics.descriptiveParses == 2)
    }
    for _ in 0..<2 {
      #expect(throws: SidecarError.self) {
        try cache.descriptive(Data("<!DOCTYPE bad><bad/>".utf8))
      }
    }
    let empty = Data(
      "<rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description xmlns:dc='http://purl.org/dc/elements/1.1/'><dc:subject><rdf:Bag/></dc:subject></rdf:Description></rdf:RDF>"
        .utf8)
    #expect(try cache.combined(sidecar: empty, embedded: a).keywords.isEmpty)
    #expect(try cache.combined(sidecar: nil, embedded: a).keywords == ["Wedding"])
  }
  @Test
  func cancelledHitsDoNotPublish() async throws {
    let task = Task {
      let cache = ParsedXMPReads()
      let data = try packet("Cached")
      _ = try cache.descriptive(data)
      withUnsafeCurrentTask { $0?.cancel() }
      return try cache.descriptive(data)
    }
    do {
      _ = try await task.value
      Issue.record("Cancelled cache hit completed")
    } catch is CancellationError {} catch { Issue.record("Wrong cancellation error") }
  }
  @Test
  func actorCacheObservesSameLengthExternalEditsRemovalSymlinksAndConflicts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("photo.jpg")
    try Data([1, 2, 3]).write(to: image)
    let sidecar = XMPSidecar.url(for: image)
    let a = try packet("First")
    let b = try packet("Other")
    #expect(a.count == b.count)
    try a.write(to: sidecar)
    let store = DecisionStore(databaseURL: root.appendingPathComponent("db.sqlite"))
    #expect(try await store.loadMetadata(for: image).value.fields[.title] == "First")
    #expect(try await store.loadMetadata(for: image).value.fields[.title] == "First")
    let old = try FileManager.default.attributesOfItem(atPath: sidecar.path)[.modificationDate]
    try b.write(to: sidecar)
    try FileManager.default.setAttributes([.modificationDate: old!], ofItemAtPath: sidecar.path)
    #expect(try await store.loadMetadata(for: image).value.fields[.title] == "Other")
    var patch = MetadataPatch()
    patch.fields[.copyright] = "Generated owner"
    let plan = try await store.prepareMetadata(patch, images: [image])[0]
    try a.write(to: sidecar)
    #expect(try await store.saveMetadata(plan).status == "XMP conflict")
    #expect(try Data(contentsOf: sidecar) == a)
    _ = try await store.useExternalMetadata(for: image)
    try FileManager.default.removeItem(at: sidecar)
    #expect(try await store.loadMetadata(for: image).value.fields[.title] == nil)
    let peer = root.appendingPathComponent("peer.xmp")
    try a.write(to: peer)
    try FileManager.default.createSymbolicLink(at: sidecar, withDestinationURL: peer)
    #expect(try await store.loadMetadata(for: image).status != "Saved")
    #expect(await store.xmpReadStatistics.descriptiveHits > 0)
    #expect(try Data(contentsOf: image) == Data([1, 2, 3]))
  }
}
