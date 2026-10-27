import CoreGraphics
import Foundation
import Testing

@testable import PhotoImaging

actor GatedPreviewDecoder {
  let image: PhotoPreview
  private(set) var names: [String] = []
  private(set) var active = 0
  private(set) var maximumActive = 0
  private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
  private var released: Set<Int> = []
  private var open = false
  init() throws {
    let context = try #require(
      CGContext(
        data: nil, width: 32, height: 20,
        bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    image = PhotoPreview(
      image: try #require(context.makeImage()), originalWidth: 32, originalHeight: 20)
  }
  // Deliberately ignores cancellation while "inside ImageIO". The scheduling
  // slot must remain occupied until this work really finishes.
  func load(_ url: URL, size: Int) async -> PhotoPreview {
    names.append(url.lastPathComponent)
    let number = names.count
    active += 1
    maximumActive = max(maximumActive, active)
    if !open && !released.contains(number) {
      await withCheckedContinuation { gates[number] = $0 }
    }
    active -= 1
    return image
  }
  func release(_ number: Int) {
    released.insert(number)
    gates.removeValue(forKey: number)?.resume()
  }
  func releaseAll() {
    open = true
    for gate in gates.values { gate.resume() }
    gates.removeAll()
  }
}

@Suite(.timeLimit(.minutes(1)))
struct PreviewSchedulingTests {
  private enum Timeout: Error { case waiting }
  private func file(_ name: String) -> URL { URL(fileURLWithPath: "/synthetic/\(name).jpg") }
  private func eventually(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
      guard ContinuousClock.now < deadline else { throw Timeout.waiting }
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  private func cancelled(_ task: Task<PhotoPreview, any Error>) async {
    do {
      _ = try await task.value
      Issue.record("Cancelled request succeeded")
    } catch { #expect(error is CancellationError) }
  }

  @Test func cancelledRunningWorkKeepsItsSlotUntilTheDecoderReturns() async throws {
    let gate = try GatedPreviewDecoder()
    let pipeline = ImagePipeline(byteLimit: 4096, maximumConcurrentLoads: 2) {
      await gate.load($0, size: $1)
    }
    defer { Task { await gate.releaseAll() } }
    let a = Task { try await pipeline.preview(for: file("a"), maximumPixelSize: 32) }
    try await eventually { await gate.names.count == 1 }
    let b = Task { try await pipeline.preview(for: file("b"), maximumPixelSize: 32) }
    try await eventually { await gate.names.count == 2 }
    let c = Task { try await pipeline.preview(for: file("c"), maximumPixelSize: 32) }
    try await eventually { await pipeline.schedulingStatistics().queuedLoads == 1 }
    a.cancel()
    await cancelled(a)
    #expect(await gate.active == 2)
    #expect(await pipeline.schedulingStatistics().activeLoads == 2)
    #expect(await pipeline.schedulingStatistics().queuedLoads == 1)
    await gate.release(1)
    try await eventually { await gate.names.count == 3 }
    #expect(await gate.maximumActive == 2)
    await gate.release(2)
    await gate.release(3)
    _ = try await b.value
    _ = try await c.value
    #expect(await pipeline.schedulingStatistics().maximumActiveLoads == 2)
    #expect(await pipeline.schedulingStatistics().activeLoads == 0)
  }

  @Test func disappearingQueuedPhotoNeverReachesTheDecoder() async throws {
    let gate = try GatedPreviewDecoder()
    let pipeline = ImagePipeline(byteLimit: 4096, maximumConcurrentLoads: 1) {
      await gate.load($0, size: $1)
    }
    defer { Task { await gate.releaseAll() } }
    let a = Task { try await pipeline.preview(for: file("a"), maximumPixelSize: 32) }
    try await eventually { await gate.names.count == 1 }
    let b = Task { try await pipeline.preview(for: file("b"), maximumPixelSize: 32) }
    try await eventually { await pipeline.schedulingStatistics().queuedLoads == 1 }
    let c = Task { try await pipeline.preview(for: file("c"), maximumPixelSize: 32) }
    try await eventually { await pipeline.schedulingStatistics().queuedLoads == 2 }
    b.cancel()
    await gate.release(1)
    await cancelled(b)
    try await eventually { await gate.names.count == 2 }
    #expect(await gate.names == ["a.jpg", "c.jpg"])
    await gate.release(2)
    _ = try await a.value
    _ = try await c.value
    #expect(await pipeline.cachedPreview(for: file("b"), maximumPixelSize: 32) == nil)
  }

  @Test func cancellingOneSharedWaiterDoesNotCancelAnother() async throws {
    let gate = try GatedPreviewDecoder()
    let pipeline = ImagePipeline(byteLimit: 4096, maximumConcurrentLoads: 2) {
      await gate.load($0, size: $1)
    }
    defer { Task { await gate.releaseAll() } }
    let a = Task { try await pipeline.preview(for: file("same"), maximumPixelSize: 32) }
    try await eventually { await gate.names.count == 1 }
    let b = Task { try await pipeline.preview(for: file("same"), maximumPixelSize: 32) }
    try await eventually { await pipeline.schedulingStatistics().coalescedRequests == 1 }
    a.cancel()
    await cancelled(a)
    await gate.release(1)
    #expect(try await b.value.image.width == 32)
    #expect(await pipeline.decodedImageCount == 1)
    #expect(await gate.names.count == 1)
  }

  @Test func focusedPhotoOvertakesVisibleQueueWithoutDuplicateWork() async throws {
    let gate = try GatedPreviewDecoder()
    let pipeline = ImagePipeline(byteLimit: 4096, maximumConcurrentLoads: 1) {
      await gate.load($0, size: $1)
    }
    defer { Task { await gate.releaseAll() } }
    let a = Task { try await pipeline.preview(for: file("a"), maximumPixelSize: 32) }
    try await eventually { await gate.names.count == 1 }
    let b = Task { try await pipeline.preview(for: file("b"), maximumPixelSize: 32) }
    try await eventually { await pipeline.schedulingStatistics().queuedLoads == 1 }
    let c = Task { try await pipeline.preview(for: file("c"), maximumPixelSize: 32) }
    try await eventually { await pipeline.schedulingStatistics().queuedLoads == 2 }
    await pipeline.prioritizePreview(for: file("c"), maximumPixelSize: 32, sessionID: nil)
    await gate.release(1)
    try await eventually { await gate.names.count == 2 }
    #expect(await gate.names == ["a.jpg", "c.jpg"])
    await gate.release(2)
    try await eventually { await gate.names.count == 3 }
    #expect(await gate.names == ["a.jpg", "c.jpg", "b.jpg"])
    await gate.release(3)
    _ = try await a.value
    _ = try await b.value
    _ = try await c.value
    #expect(await pipeline.decodedImageCount == 3)
  }

  @Test func clearAndSessionChangesRejectLateResultsFromAnUninterruptibleDecoder() async throws {
    let gate = try GatedPreviewDecoder()
    let pipeline = ImagePipeline(byteLimit: 4096, maximumConcurrentLoads: 1) {
      await gate.load($0, size: $1)
    }
    defer { Task { await gate.releaseAll() } }
    let first = UUID()
    let next = UUID()
    let url = file("same")
    let a = Task { try await pipeline.preview(for: url, maximumPixelSize: 32, sessionID: first) }
    try await eventually { await gate.names.count == 1 }
    await pipeline.startSession(next)
    await cancelled(a)
    await #expect(throws: CancellationError.self) {
      try await pipeline.preview(for: url, maximumPixelSize: 32, sessionID: first)
    }
    await pipeline.startSession(first)
    #expect(await pipeline.schedulingStatistics().queuedLoads == 0)
    let b = Task { try await pipeline.preview(for: url, maximumPixelSize: 32, sessionID: next) }
    try await eventually { await pipeline.schedulingStatistics().queuedLoads == 1 }
    await gate.release(1)
    try await eventually { await gate.names.count == 2 }
    #expect(pipeline.immediateCachedPreview(for: url, maximumPixelSize: 32, sessionID: next) == nil)
    await pipeline.clearThumbnailCache()
    await cancelled(b)
    let c = Task { try await pipeline.preview(for: url, maximumPixelSize: 32, sessionID: next) }
    try await eventually { await pipeline.schedulingStatistics().queuedLoads == 1 }
    await gate.release(2)
    try await eventually { await gate.names.count == 3 }
    #expect(await pipeline.cachedByteCount == 0)
    await gate.release(3)
    _ = try await c.value
    #expect(
      pipeline.immediateCachedPreview(for: url, maximumPixelSize: 32, sessionID: first) == nil)
    #expect(pipeline.immediateCachedPreview(for: url, maximumPixelSize: 32, sessionID: next) != nil)
  }

  @Test func separateFitLaneRemainsAvailableWhileThumbnailWorkersAreBlocked() async throws {
    let gate = try GatedPreviewDecoder()
    let thumbnails = ImagePipeline(byteLimit: 4096, maximumConcurrentLoads: 1) {
      await gate.load($0, size: $1)
    }
    defer { Task { await gate.releaseAll() } }
    let thumbnail = Task { try await thumbnails.preview(for: file("a"), maximumPixelSize: 32) }
    try await eventually { await gate.names.count == 1 }
    let image = gate.image
    let fit = ImagePipeline(byteLimit: 4096, maximumConcurrentLoads: 1) { _, _ in image }
    #expect(
      try await fit.preview(for: file("fit"), maximumPixelSize: 2560, priority: .selected).image
        .width == 32)
    #expect(await gate.active == 1)
    await gate.release(1)
    _ = try await thumbnail.value
  }
}
