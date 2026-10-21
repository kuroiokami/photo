import Foundation

/// All dictionary/link/session access is serialized by this lock. CGImages are
/// immutable; a RAM hit never performs source-file or disk-cache I/O.
final class PreviewMemoryCache: @unchecked Sendable {
  private struct Key: Hashable {
    let file: URL
    let size: Int
  }
  private struct Entry {
    let preview: PhotoPreview
    var previous: Key?
    var next: Key?
  }
  private let lock = NSLock()
  private let limit: Int
  private var session: UUID?
  private var cache: [Key: Entry] = [:]
  private var oldest: Key?
  private var newest: Key?
  private var bytes = 0
  init(byteLimit: Int) { limit = max(0, byteLimit) }
  var byteCount: Int { lock.withLock { bytes } }

  func startSession(_ value: UUID?) {
    lock.withLock {
      guard session != value else { return }
      session = value
      reset()
    }
  }
  func clear() { lock.withLock { reset() } }
  private func reset() {
    cache.removeAll(keepingCapacity: true)
    oldest = nil
    newest = nil
    bytes = 0
  }
  func lookup(_ file: URL, size: Int, session value: UUID?) -> PhotoPreview? {
    lock.withLock {
      guard session == value else { return nil }
      let key = Key(file: file, size: min(max(size, 1), 2560))
      guard let entry = cache[key] else { return nil }
      touch(key)
      return entry.preview
    }
  }
  func insert(_ preview: PhotoPreview, file: URL, size: Int) {
    lock.withLock {
      guard preview.byteCost <= limit else { return }
      let key = Key(file: file, size: size)
      if cache[key] != nil { remove(key) }
      while bytes + preview.byteCost > limit, let oldest { remove(oldest) }
      cache[key] = Entry(preview: preview, previous: newest)
      if let newest { cache[newest]?.next = key } else { oldest = key }
      newest = key
      bytes += preview.byteCost
    }
  }
  private func touch(_ key: Key) {
    guard newest != key, let entry = cache[key] else { return }
    if let previous = entry.previous {
      cache[previous]?.next = entry.next
    } else {
      oldest = entry.next
    }
    if let next = entry.next { cache[next]?.previous = entry.previous }
    cache[key]?.previous = newest
    cache[key]?.next = nil
    if let newest { cache[newest]?.next = key }
    newest = key
  }
  private func remove(_ key: Key) {
    guard let entry = cache.removeValue(forKey: key) else { return }
    if let previous = entry.previous {
      cache[previous]?.next = entry.next
    } else {
      oldest = entry.next
    }
    if let next = entry.next {
      cache[next]?.previous = entry.previous
    } else {
      newest = entry.previous
    }
    bytes -= entry.preview.byteCost
  }
}

public enum ThumbnailCachePolicy {
  /// ~1.6% of physical RAM, bounded independently from Fit/detail images.
  public static func memoryByteLimit(
    physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
  ) -> Int {
    let minimum: UInt64 = 64 * 1024 * 1024
    let maximum: UInt64 = 256 * 1024 * 1024
    let proposed = physicalMemory / 64
    return Int(min(maximum, max(minimum, proposed)))
  }
}
