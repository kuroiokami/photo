import Foundation
import Observation

/// Stable per-photo display state. A publication for another photo does not
/// invalidate observers of this photo's pixels, decisions or shooting labels.
@MainActor @Observable
public final class PhotoThumbnailState {
  public internal(set) var selected = false
  public internal(set) var ready = false
  public internal(set) var decision = CullingDecision()
  public internal(set) var edit = PhotoEdit()
  public internal(set) var metadata: PhotoMetadata?
  public internal(set) var pairedCount = 1
}

/// Selection-only dependencies are separate from the workspace and tile records.
/// Unknown decisions remain in the summary as unrated, but disable operations.
@MainActor @Observable
public final class WorkspaceSelectionState {
  private var revision = 0
  @ObservationIgnored private var records: [String: CullingDecision] = [:]
  @ObservationIgnored private var unknown: Set<String> = []
  @ObservationIgnored private var cachedSummary: DecisionSelectionSummary?
  @ObservationIgnored public private(set) var evaluations = 0

  public private(set) var ready = false
  public var summary: DecisionSelectionSummary {
    _ = revision
    if let cachedSummary { return cachedSummary }
    let value = DecisionSelectionSummary(Array(records.values))
    cachedSummary = value
    evaluations += 1
    return value
  }
  func replace(_ targets: [PhotoItem], decisions: [String: CullingDecision], ready: Set<String>) {
    let records = Dictionary(
      targets.map { ($0.id, decisions[$0.id] ?? CullingDecision()) },
      uniquingKeysWith: { first, _ in first })
    let unknown = Set(records.keys).subtracting(ready)
    let changedSummary = records != self.records
    guard changedSummary || unknown != self.unknown else { return }
    self.records = records
    self.unknown = unknown
    updateReady()
    if changedSummary { invalidate() }
  }
  func update(_ id: String, decision: CullingDecision, ready: Bool) {
    guard let previous = records[id] else { return }
    guard previous != decision || unknown.contains(id) == ready else { return }
    records[id] = decision
    if ready { unknown.remove(id) } else { unknown.insert(id) }
    updateReady()
    if previous != decision { invalidate() }
  }
  private func updateReady() {
    let value = !records.isEmpty && unknown.isEmpty
    if ready != value { ready = value }
  }
  private func invalidate() {
    cachedSummary = nil
    revision &+= 1
  }
}
