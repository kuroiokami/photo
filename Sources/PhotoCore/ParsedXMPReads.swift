import Foundation

/// Fixed counters; no filenames, packet bytes or descriptive values in diagnostics.
public struct XMPReadStatistics: Codable, Sendable {
  public var decisionParses = 0
  public var descriptiveParses = 0
  public var decisionHits = 0
  public var descriptiveHits = 0
  public var evictions = 0
  public var entries = 0
  public var accountedBytes = 0
}

/// Owned exclusively by DecisionStore's actor. Cache immutable values, never mutable XML trees.
/// Every caller still reads and validates current sidecar bytes. Writes always parse fresh XML.
final class ParsedXMPReads {
  private struct Entry {
    let packet: Data
    var decision: CullingDecision?
    var descriptive: DescriptiveMetadata?
    var accessed: UInt64 = 0
    var cost: Int {
      var result = 192 + packet.count
      if let value = descriptive {
        for text in value.fields.values { result += text.utf8.count }
        for text in value.keywords { result += text.utf8.count }
        for text in value.hierarchy { result += text.utf8.count }
      }
      return result
    }
  }
  private let entryLimit: Int
  private let byteLimit: Int
  private var entries: [String: Entry] = [:]
  private var bytes = 0
  private var access: UInt64 = 0
  private var counters = XMPReadStatistics()
  init(entryLimit: Int = 128, byteLimit: Int = 4 * 1024 * 1024) {
    self.entryLimit = max(0, entryLimit)
    self.byteLimit = max(0, byteLimit)
  }
  var statistics: XMPReadStatistics {
    var value = counters
    value.entries = entries.count
    value.accountedBytes = bytes
    return value
  }
  private func entry(_ data: Data, _ key: String) -> Entry {
    guard let value = entries[key], value.packet == data else { return Entry(packet: data) }
    return value
  }
  private func store(_ value: Entry, _ key: String) {
    if let old = entries.removeValue(forKey: key) { bytes -= old.cost }
    guard entryLimit > 0, value.cost <= byteLimit else { return }
    while entries.count >= entryLimit || value.cost > byteLimit - bytes {
      guard let victim = entries.min(by: { $0.value.accessed < $1.value.accessed })?.key,
        let old = entries.removeValue(forKey: victim)
      else { break }
      bytes -= old.cost
      counters.evictions += 1
    }
    var value = value
    access &+= 1
    value.accessed = access
    entries[key] = value
    bytes += value.cost
  }
  func decision(_ data: Data, digest: String? = nil) throws -> CullingDecision {
    try Task.checkCancellation()
    let key = digest ?? XMPSidecar.digest(data)
    var value = entry(data, key)
    try Task.checkCancellation()
    if let decision = value.decision {
      counters.decisionHits += 1
      store(value, key)
      return decision
    }
    counters.decisionParses += 1
    let result = try XMPSidecar.read(data)
    try Task.checkCancellation()
    value.decision = result
    store(value, key)
    return result
  }
  func descriptive(_ data: Data?, digest: String? = nil) throws -> DescriptiveMetadata {
    try Task.checkCancellation()
    guard let data else { return DescriptiveMetadata() }
    let key = digest ?? XMPSidecar.digest(data)
    var value = entry(data, key)
    try Task.checkCancellation()
    if let metadata = value.descriptive {
      counters.descriptiveHits += 1
      store(value, key)
      return metadata
    }
    counters.descriptiveParses += 1
    let result = try XMPSidecar.descriptive(data)
    try Task.checkCancellation()
    value.descriptive = result
    store(value, key)
    return result
  }
  func combined(sidecar: Data?, embedded: Data?, sidecarDigest: String? = nil) throws
    -> DescriptiveMetadata
  {
    var result = try descriptive(embedded)
    let overlay = try descriptive(sidecar, digest: sidecarDigest)
    result.fields.merge(overlay.fields) { _, new in new }
    if overlay.keywordsPresent {
      result.keywords = overlay.keywords
      result.keywordsPresent = true
    }
    if overlay.hierarchyPresent {
      result.hierarchy = overlay.hierarchy
      result.hierarchyPresent = true
    }
    return result
  }
}
