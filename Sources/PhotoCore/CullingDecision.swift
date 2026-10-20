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

/// Which fields the source review explicitly owns, independently of their values.
public struct SourceDecisionFields: OptionSet, Codable, Equatable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let rating = Self(rawValue: 1)
  public static let flag = Self(rawValue: 2)
  public static let all: Self = [.rating, .flag]
}

public struct CullingDecision: Codable, Equatable, Sendable {
  public var rating: Int
  public var flag: PhotoFlag
  public init(rating: Int = 0, flag: PhotoFlag = .unflagged) {
    self.rating = min(5, max(0, rating))
    self.flag = flag
  }
}

/// Nil values mean the selected files disagree; stars and flags remain independent.
public struct DecisionSelectionSummary: Equatable, Sendable {
  public let fileCount: Int
  public let rating: Int?
  public let flag: PhotoFlag?
  public init(_ decisions: [CullingDecision]) {
    fileCount = decisions.count
    rating = decisions.first.flatMap { first in
      decisions.allSatisfy { $0.rating == first.rating } ? first.rating : nil
    }
    flag = decisions.first.flatMap { first in
      decisions.allSatisfy { $0.flag == first.flag } ? first.flag : nil
    }
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

/// Tracks long file operations without delaying independent culling saves.
@MainActor
public final class WorkflowOperationBarrier {
  public static let shared = WorkflowOperationBarrier()
  private var tasks: [UUID: Task<Void, Never>] = [:]
  public var hasPending: Bool { !tasks.isEmpty }
  public func track(_ task: Task<Void, Never>) {
    let id = UUID()
    tasks[id] = Task {
      await task.value
      tasks[id] = nil
    }
  }
  public func flush() async {
    while let task = tasks.values.first { await task.value }
  }
}
