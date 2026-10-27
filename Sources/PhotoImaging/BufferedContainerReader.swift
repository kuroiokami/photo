import Foundation

/// One small read window for container headers. Large JPEG payloads bypass the
/// window; box offsets skip sensor data. Speculative reads have a total budget
/// so sparse/adversarial layouts cannot amplify I/O without limit.
final class BufferedContainerReader {
  struct Statistics: Equatable {
    var reads = 0
    var bytesRead: UInt64 = 0
    var speculativeBytes = 0
    var largestRead = 0
  }
  static let windowSize = 4 * 1024
  static let speculativeLimit = 1024 * 1024
  let length: UInt64
  private let speculativeBudget: Int
  private let file: FileHandle
  private let checkCancellation: @Sendable () throws -> Void
  private var window = Data()
  private var windowStart: UInt64 = 0
  private(set) var statistics = Statistics()

  init(
    url: URL, buffering: Bool = true,
    checkCancellation: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() }
  ) throws {
    speculativeBudget = buffering ? Self.speculativeLimit : 0
    file = try FileHandle(forReadingFrom: url)
    do { length = try file.seekToEnd() } catch {
      try? file.close()
      throw error
    }
    self.checkCancellation = checkCancellation
  }
  deinit { try? file.close() }

  func read(_ position: UInt64, _ count: Int) throws -> Data? {
    guard count >= 0, position <= length, UInt64(count) <= length - position else { return nil }
    try checkCancellation()
    guard count > 0 else { return Data() }
    if position >= windowStart {
      let offset = position - windowStart
      if offset <= UInt64(window.count), UInt64(count) <= UInt64(window.count) - offset {
        return window.subdata(in: Int(offset)..<(Int(offset) + count))
      }
    }
    let remaining = speculativeBudget - statistics.speculativeBytes
    let extra =
      count <= Self.windowSize
      ? Int(
        min(
          UInt64(Self.windowSize - count), min(length - position - UInt64(count), UInt64(remaining))
        )) : 0
    let requested = count + extra
    try file.seek(toOffset: position)
    let data = try file.read(upToCount: requested)
    statistics.reads += 1
    statistics.bytesRead += UInt64(data?.count ?? 0)
    statistics.largestRead = max(statistics.largestRead, requested)
    statistics.speculativeBytes += max(0, (data?.count ?? 0) - count)
    try checkCancellation()
    guard let data, data.count >= count else { return nil }
    guard extra > 0 else { return data }
    windowStart = position
    window = data
    return data.subdata(in: 0..<count)
  }
}
