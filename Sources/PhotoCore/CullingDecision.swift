import Foundation

public enum PhotoFlag: Int, Codable, CaseIterable, Sendable {
  case reject = -1
  case unflagged = 0
  case pick = 1
  public var title: String {
    switch self {
    case .reject: "Reject"
    case .unflagged: "Unflagged"
    case .pick: "Pick"
    }
  }
  public var symbol: String {
    switch self {
    case .reject: "xmark.circle.fill"
    case .unflagged: "flag"
    case .pick: "flag.fill"
    }
  }
}

public struct CullingDecision: Codable, Equatable, Sendable {
  public var rating: Int
  public var flag: PhotoFlag
  public init(rating: Int = 0, flag: PhotoFlag = .unflagged) {
    self.rating = min(5, max(0, rating))
    self.flag = flag
  }
}

public enum FlagFilter: String, CaseIterable, Sendable {
  case all = "All flags"
  case pick = "Picks"
  case reject = "Rejects"
  case unflagged = "Unflagged"
  public func includes(_ flag: PhotoFlag) -> Bool {
    switch self {
    case .all: true
    case .pick: flag == .pick
    case .reject: flag == .reject
    case .unflagged: flag == .unflagged
    }
  }
}

/// Serializes durable work across all windows and provides a termination barrier.
@MainActor
public final class DecisionSaveQueue {
  public static let shared = DecisionSaveQueue()
  private var tail: Task<Void, Never>?
  private var count = 0
  public var hasPending: Bool { count > 0 }
  public func enqueue(_ work: @escaping @MainActor () async -> Void) {
    let previous = tail
    count += 1
    tail = Task {
      await previous?.value
      await work()
      count -= 1
    }
  }
  public func flush() async { while count > 0 { await tail?.value } }
}
