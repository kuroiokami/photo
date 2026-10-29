import Foundation

/// Cooperative main-actor work target, not a hard frame deadline. Opaque
/// Observation/layout work cannot be preempted; record overshoots honestly.
struct PublicationBudget {
  static let maximumItems = 16
  static let targetMilliseconds = 2.0
  private(set) var limit = maximumItems
  private var quick = 0
  mutating func record(milliseconds: Double) {
    if milliseconds > Self.targetMilliseconds {
      limit = max(1, limit / 2)
      quick = 0
    } else if milliseconds < Self.targetMilliseconds / 4 {
      quick += 1
      if quick == 4 {
        limit = min(Self.maximumItems, limit + 1)
        quick = 0
      }
    } else {
      quick = 0
    }
  }
}
public struct PublicationWork: Codable, Sendable {
  public internal(set) var maximumItems = 0
  public internal(set) var maximumMilliseconds = 0.0
  public internal(set) var overTarget = 0
  mutating func record(items: Int, milliseconds: Double) {
    maximumItems = max(maximumItems, items)
    maximumMilliseconds = max(maximumMilliseconds, milliseconds)
    if milliseconds > PublicationBudget.targetMilliseconds { overTarget += 1 }
  }
}
