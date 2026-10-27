import CoreGraphics
import Foundation
import Testing

@testable import PhotoImaging

private final class CachePublicationGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var entered = false
  private var released = false
  var blocked: Bool {
    condition.lock()
    defer { condition.unlock() }
    return entered && !released
  }
  func pause() -> Bool {
    condition.lock()
    defer { condition.unlock() }
    entered = true
    while !released { condition.wait() }
    return true
  }
  func release() {
    condition.lock()
    defer { condition.unlock() }
    released = true
    condition.broadcast()
  }
}
private final class CacheReadResult: @unchecked Sendable {
  private let lock = NSLock()
  private var complete = false
  private var success = false
  func finish(_ image: PhotoPreview?) {
    lock.withLock {
      complete = true
      success = image != nil
    }
  }
  var succeeded: Bool { lock.withLock { complete && success } }
}
@Suite(.timeLimit(.minutes(1)))
struct CacheContentionTests {
  private enum Timeout: Error { case waiting }
  private func scratch() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
  private func key(_ value: Int) -> String { String(format: "%064x", value) }
  private func image() throws -> PhotoPreview {
    let context = try #require(
      CGContext(
        data: nil, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    return PhotoPreview(
      image: try #require(context.makeImage()), originalWidth: 1, originalHeight: 1)
  }
  private func eventually(_ condition: () -> Bool) async throws {
    let until = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition() {
      guard ContinuousClock.now < until else { throw Timeout.waiting }
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  @Test func diskHitCompletesWhilePublicationLockIsHeld() async throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let disk = ThumbnailDiskCache(directory: root)
    let preview = try image()
    disk.store(preview, key: key(1))
    let gate = CachePublicationGate()
    let writer = Task.detached { disk.store(preview, key: key(2), valid: gate.pause) }
    do {
      try await eventually { gate.blocked }
      let result = CacheReadResult()
      let reader = Task.detached { result.finish(disk.read(key(1))) }
      do { try await eventually { result.succeeded } } catch {
        gate.release()
        await reader.value
        throw error
      }
      #expect(gate.blocked)
      #expect(result.succeeded)
      gate.release()
      await reader.value
      await writer.value
    } catch {
      gate.release()
      await writer.value
      throw error
    }
  }
  @Test func bufferedReadRecencyInfluencesEvictionAndClearDropsHints() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let preview = try image()
    let probe = ThumbnailDiskCache(directory: root.appendingPathComponent("probe"))
    probe.store(preview, key: key(1))
    let attributes = try FileManager.default.attributesOfItem(
      atPath: root.appendingPathComponent("probe/\(key(1)).thumb").path)
    let cost = try #require(attributes[.size] as? Int)
    let disk = ThumbnailDiskCache(
      directory: root.appendingPathComponent("cache"), byteLimit: cost * 3)
    for i in 1...3 { disk.store(preview, key: key(i)) }
    #expect(disk.read(key(1)) != nil)
    #expect(disk.pendingReadTouchCount == 1)
    disk.store(preview, key: key(4))
    // 90% hysteresis keeps two records: the just-read first record and the new one.
    #expect(disk.read(key(1)) != nil)
    #expect(disk.read(key(4)) != nil)
    #expect(disk.read(key(2)) == nil)
    #expect(disk.read(key(3)) == nil)
    disk.clear()
    #expect(disk.pendingReadTouchCount == 0)
    #expect(disk.read(key(1)) == nil)
  }
  @Test func recencyHintsAreCoalescedAndBoundedEvenWithoutNewWrites() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let preview = try image()
    let disk = ThumbnailDiskCache(directory: root)
    for i in 0..<520 { disk.store(preview, key: key(i)) }
    for _ in 0..<100 { #expect(disk.read(key(0)) != nil) }
    #expect(disk.pendingReadTouchCount == 1)
    for i in 0..<520 { #expect(disk.read(key(i)) != nil) }
    #expect(disk.pendingReadTouchCount == 512)
    disk.clear()
    #expect(disk.pendingReadTouchCount == 0)
  }
  @Test func concurrentReadStoreAndClearStayRecoverable() async throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let disk = ThumbnailDiskCache(directory: root)
    let preview = try image()
    await withTaskGroup(of: Void.self) { group in
      for worker in 0..<4 {
        group.addTask {
          for i in 0..<100 {
            let id = key(i % 12)
            if worker == 0 {
              disk.store(preview, key: id)
            } else if worker == 1 && i % 10 == 0 {
              disk.clear()
            } else if let result = disk.read(id) {
              #expect(result.decodedWidth == 1)
            }
          }
        }
      }
    }
    disk.store(preview, key: key(1000))
    #expect(disk.read(key(1000)) != nil)
    #expect(disk.pendingReadTouchCount <= 512)
  }
}
