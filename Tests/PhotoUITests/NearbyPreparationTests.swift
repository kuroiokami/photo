import CoreGraphics
import Foundation
import PhotoCore
import Testing

@testable import PhotoImaging
@testable import PhotoUI

@Suite(.timeLimit(.minutes(1)))
struct NearbyPreparationTests {
  private enum Timeout: Error { case waiting }
  private func file(_ name: String) -> URL { URL(fileURLWithPath: "/synthetic/\(name).jpg") }
  private func eventually(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
      guard ContinuousClock.now < deadline else { throw Timeout.waiting }
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  private func pipeline(_ gate: GatedPreviewDecoder, limit: Int = 64 * 1024 * 1024) -> ImagePipeline
  {
    ImagePipeline(byteLimit: limit, maximumConcurrentLoads: 1, preparesNearby: true) {
      await gate.load($0, size: $1)
    }
  }
  @Test func preparationRequiresReadyForegroundAndReadsAtMostTwoNeighbors() async throws {
    let gate = try GatedPreviewDecoder()
    let pipeline = pipeline(gate)
    defer { Task { await gate.releaseAll() } }
    await pipeline.prepareNearby(after: file("a"), candidates: [file("b")], sessionID: nil)
    #expect(await gate.names.isEmpty)
    let selected = Task {
      try await pipeline.preview(for: file("a"), maximumPixelSize: 2560, priority: .selected)
    }
    try await eventually { await gate.names.count == 1 }
    await gate.release(1)
    _ = try await selected.value
    let prep = Task {
      await pipeline.prepareNearby(
        after: file("a"), candidates: [file("b"), file("c"), file("d")], sessionID: nil)
    }
    try await eventually { await gate.names.count == 2 }
    #expect(await gate.names == ["a.jpg", "b.jpg"])
    await gate.release(2)
    try await eventually { await gate.names.count == 3 }
    await gate.release(3)
    await prep.value
    #expect(await gate.names == ["a.jpg", "b.jpg", "c.jpg"])
    #expect(pipeline.immediateCachedPreview(for: file("b"), maximumPixelSize: 2560) != nil)
    #expect(pipeline.immediateCachedPreview(for: file("c"), maximumPixelSize: 2560) != nil)
  }
  @Test func foregroundBypassesUninterruptiblePreparationAndDropsItsLateResult() async throws {
    let gate = try GatedPreviewDecoder()
    let pipeline = pipeline(gate)
    defer { Task { await gate.releaseAll() } }
    await gate.release(1)
    _ = try await pipeline.preview(for: file("a"), maximumPixelSize: 2560, priority: .selected)
    let prep = Task {
      await pipeline.prepareNearby(
        after: file("a"), candidates: [file("b"), file("d")], sessionID: nil)
    }
    try await eventually { await gate.names.count == 2 }
    let selected = Task {
      try await pipeline.preview(for: file("c"), maximumPixelSize: 2560, priority: .selected)
    }
    try await eventually { await gate.names.count == 3 }
    #expect(await gate.active == 2)
    #expect(await gate.names == ["a.jpg", "b.jpg", "c.jpg"])
    await gate.release(3)
    _ = try await selected.value
    await prep.value
    await gate.release(2)
    try await eventually { await pipeline.schedulingStatistics().activeLoads == 0 }
    #expect(pipeline.immediateCachedPreview(for: file("b"), maximumPixelSize: 2560) == nil)
    #expect(pipeline.immediateCachedPreview(for: file("c"), maximumPixelSize: 2560) != nil)
    #expect(await pipeline.schedulingStatistics().maximumActiveLoads == 2)
  }
  @Test func matchingForegroundSharesPreparationDespiteOldViewCancellation() async throws {
    let gate = try GatedPreviewDecoder()
    let pipeline = pipeline(gate)
    defer { Task { await gate.releaseAll() } }
    await gate.release(1)
    _ = try await pipeline.preview(for: file("a"), maximumPixelSize: 2560, priority: .selected)
    let prep = Task {
      await pipeline.prepareNearby(
        after: file("a"), candidates: [file("b"), file("c")], sessionID: nil)
    }
    try await eventually { await gate.names.count == 2 }
    let selected = Task {
      try await pipeline.preview(for: file("b"), maximumPixelSize: 2560, priority: .selected)
    }
    try await eventually { await pipeline.schedulingStatistics().coalescedRequests == 1 }
    prep.cancel()
    await prep.value
    await gate.release(2)
    #expect(try await selected.value.image.width == 32)
    #expect(await gate.names == ["a.jpg", "b.jpg"])
    #expect(await pipeline.decodedImageCount == 2)
  }
  @Test func clearAndSessionResetRejectOptionalPixelsAndLatePreparation() async throws {
    let gate = try GatedPreviewDecoder()
    let pipeline = pipeline(gate)
    defer { Task { await gate.releaseAll() } }
    let first = UUID()
    let next = UUID()
    await gate.release(1)
    _ = try await pipeline.preview(
      for: file("a"), maximumPixelSize: 2560, sessionID: first, priority: .selected)
    let prep = Task {
      await pipeline.prepareNearby(after: file("a"), candidates: [file("b")], sessionID: first)
    }
    try await eventually { await gate.names.count == 2 }
    await pipeline.clearThumbnailCache()
    await prep.value
    await pipeline.startSession(next)
    await pipeline.prepareNearby(after: file("a"), candidates: [file("c")], sessionID: first)
    await gate.release(2)
    try await eventually { await pipeline.schedulingStatistics().activeLoads == 0 }
    #expect(await pipeline.cachedByteCount == 0)
    #expect(await gate.names == ["a.jpg", "b.jpg"])
  }
  @Test func speculativeEvictionProtectsDisplayedPhotoWithoutGrowingBudget() async throws {
    let gate = try GatedPreviewDecoder()
    let cost = gate.image.byteCost
    let pipeline = pipeline(gate, limit: cost * 2)
    await gate.releaseAll()
    _ = try await pipeline.preview(for: file("a"), maximumPixelSize: 2560, priority: .selected)
    _ = try await pipeline.preview(for: file("old"), maximumPixelSize: 2560)
    await pipeline.prepareNearby(
      after: file("a"), candidates: [file("b"), file("c")], sessionID: nil)
    #expect(pipeline.immediateCachedPreview(for: file("a"), maximumPixelSize: 2560) != nil)
    #expect(pipeline.immediateCachedPreview(for: file("old"), maximumPixelSize: 2560) == nil)
    // Keep the first-priority neighbor when both cannot fit beside the selection.
    #expect(pipeline.immediateCachedPreview(for: file("b"), maximumPixelSize: 2560) != nil)
    #expect(pipeline.immediateCachedPreview(for: file("c"), maximumPixelSize: 2560) == nil)
    #expect(await pipeline.cachedByteCount == cost * 2)
    let tight = self.pipeline(gate, limit: cost)
    _ = try await tight.preview(for: file("a"), maximumPixelSize: 2560, priority: .selected)
    await tight.prepareNearby(after: file("a"), candidates: [file("b")], sessionID: nil)
    #expect(tight.immediateCachedPreview(for: file("a"), maximumPixelSize: 2560) != nil)
    #expect(tight.immediateCachedPreview(for: file("b"), maximumPixelSize: 2560) == nil)
    #expect(await tight.cachedByteCount == cost)
  }
  @Test func storagePolicyFailsClosedForCardsNetworksAndUnknownValues() {
    let values: [Bool?] = [true, false, nil]
    for local in values {
      for removable in values {
        for ejectable in values {
          #expect(
            NearbyPreviewStorage.allows(local: local, removable: removable, ejectable: ejectable)
              == (local == true && removable == false && ejectable == false))
        }
      }
    }
  }
  @Test func productionWorkersPrepareOnlyEligibleStorageAndKeepOriginalsUntouched() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let original = try Data(contentsOf: source)
    let files = try (0..<3).map { index in
      let file = root.appendingPathComponent("Frame\(index).png")
      try original.write(to: file)
      return file
    }
    let pipeline = ImagePipeline(byteLimit: 16 * 1024 * 1024, preparesNearby: true)
    _ = try await pipeline.preview(for: files[0], maximumPixelSize: 2560, priority: .selected)
    await pipeline.prepareNearby(
      after: files[0], candidates: Array(files.dropFirst()), sessionID: nil)
    let eligible = NearbyPreviewStorage.allows(files[0])
    for file in files.dropFirst() {
      #expect(
        (pipeline.immediateCachedPreview(for: file, maximumPixelSize: 2560) != nil) == eligible)
    }
    #expect(await pipeline.decodedImageCount == (eligible ? 3 : 1))
    #expect(await pipeline.schedulingStatistics().activeLoads == 0)
    for file in files { #expect(try Data(contentsOf: file) == original) }
  }

  @Test func unavailableNeighborDoesNotBlockTheOtherPreview() async throws {
    let gate = try GatedPreviewDecoder()
    await gate.releaseAll()
    let pipeline = ImagePipeline(
      byteLimit: 64 * 1024 * 1024, maximumConcurrentLoads: 1, preparesNearby: true
    ) { url, size in
      if url.lastPathComponent == "broken.jpg" { throw PreviewError.embeddedUnavailable }
      return await gate.load(url, size: size)
    }
    _ = try await pipeline.preview(for: file("a"), maximumPixelSize: 2560, priority: .selected)
    await pipeline.prepareNearby(
      after: file("a"), candidates: [file("broken"), file("b")], sessionID: nil)
    #expect(pipeline.immediateCachedPreview(for: file("a"), maximumPixelSize: 2560) != nil)
    #expect(pipeline.immediateCachedPreview(for: file("b"), maximumPixelSize: 2560) != nil)
    #expect(await pipeline.schedulingStatistics().activeLoads == 0)
  }

}
