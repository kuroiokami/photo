import Foundation
import Testing

@testable import PhotoImaging

struct BufferedContainerReaderTests {
  private func fixture() throws -> (URL, Data) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let data = Data((0..<100_000).map { UInt8($0 % 251) })
    try data.write(to: url)
    return (url, data)
  }
  @Test func adjacentHeadersAndWindowBoundaryMatchOriginalBytes() throws {
    let (url, data) = try fixture()
    defer { try? FileManager.default.removeItem(at: url) }
    let reader = try BufferedContainerReader(url: url)
    for position in stride(from: 0, to: BufferedContainerReader.windowSize / 2, by: 8) {
      #expect(try reader.read(UInt64(position), 8) == data.subdata(in: position..<(position + 8)))
    }
    #expect(reader.statistics.reads == 1)
    let start = BufferedContainerReader.windowSize - 3
    #expect(try reader.read(UInt64(start), 8) == data.subdata(in: start..<(start + 8)))
    #expect(reader.statistics.reads == 2)
    #expect(try reader.read(UInt64.max, 8) == nil)
    #expect(try reader.read(0, -1) == nil)
    #expect(try reader.read(reader.length, 1) == nil)
    #expect(try reader.read(reader.length, 0) == Data())
  }
  @Test func speculativeReadBudgetBoundsSparseLayouts() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let writer = try FileHandle(forWritingTo: url)
    try writer.truncate(atOffset: 256 * 1024 * 1024)
    try writer.close()
    let reader = try BufferedContainerReader(url: url)
    for index in 0..<1000 {
      #expect(try reader.read(UInt64(index * 65_536), 8)?.count == 8)
    }
    #expect(reader.statistics.speculativeBytes == BufferedContainerReader.speculativeLimit)
    #expect(reader.statistics.bytesRead <= UInt64(BufferedContainerReader.speculativeLimit + 8000))
    #expect(reader.statistics.largestRead <= BufferedContainerReader.windowSize)
  }
  private final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func check() throws { if lock.withLock({ cancelled }) { throw CancellationError() } }
  }
  @Test func cacheHitsStillObserveCancellationAndLargePayloadBypassesReadAhead() throws {
    let (url, data) = try fixture()
    defer { try? FileManager.default.removeItem(at: url) }
    let cancellation = Cancellation()
    let reader = try BufferedContainerReader(
      url: url, checkCancellation: { try cancellation.check() })
    #expect(try reader.read(0, 8) == data.prefix(8))
    cancellation.cancel()
    #expect(throws: CancellationError.self) { try reader.read(0, 8) }
    #expect(reader.statistics.reads == 1)
    let payloadReader = try BufferedContainerReader(url: url)
    #expect(try payloadReader.read(0, 80_000) == data.prefix(80_000))
    #expect(payloadReader.statistics.bytesRead == 80_000)
    #expect(payloadReader.statistics.speculativeBytes == 0)
  }
}
