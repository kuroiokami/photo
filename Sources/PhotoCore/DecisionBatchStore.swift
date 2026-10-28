import CSQLite
import Foundation

public struct DecisionWrite: Sendable {
  public let image: URL
  public let decision: CullingDecision
  public let expectedIdentity: String?
  public let resolveConflict: Bool
  public init(
    image: URL, decision: CullingDecision, expectedIdentity: String? = nil,
    resolveConflict: Bool = false
  ) {
    self.image = image
    self.decision = decision
    self.expectedIdentity = expectedIdentity
    self.resolveConflict = resolveConflict
  }
}
public struct SourceDecisionWrite: Sendable {
  public let image: URL
  public let identity: String
  public let decision: CullingDecision
  public let reviewed: Bool
  public let fields: SourceDecisionFields?
  public init(
    image: URL, identity: String, decision: CullingDecision, reviewed: Bool,
    fields: SourceDecisionFields? = nil
  ) {
    self.image = image
    self.identity = identity
    self.decision = decision
    self.reviewed = reviewed
    self.fields = fields
  }
}
public struct DecisionWriteStatistics: Codable, Sendable {
  public var intentCommits = 0
  public var acknowledgementCommits = 0
  public var reviewCommits = 0
  public var recoveryCommits = 0
  public var rollbacks = 0
  public var sidecarPublications = 0
  public var maximumPreparedXMPBytes = 0
}
enum DecisionBatchCheckpoint: Sendable {
  case intentCommitted
  case sidecarPublished(Int)
  case beforeAcknowledgement
}
enum DecisionCommitKind { case intent, acknowledgement, review, recovery }

extension DecisionStore {
  /// Small chunks bound database/protection admission and status-publication work.
  public static let decisionBatchLimit = 32
  private static let preparedXMPByteLimit = 1024 * 1024
  private struct PreparedDecision {
    let index: Int
    let request: DecisionWrite
    let identity: String
    let record: StoredDecision
    let output: Data?
    let failureStatus: String?
  }
  private struct PublishedDecision {
    let prepared: PreparedDecision
    let publication: DecisionPublication
  }
  func withDecisionTransaction<T>(_ kind: DecisionCommitKind, _ work: () throws -> T) throws -> T {
    let db = try withDB { $0 }
    let outer = sqlite3_get_autocommit(db) != 0
    try decisionSQL(db, outer ? "BEGIN IMMEDIATE" : "SAVEPOINT photo_decision_save")
    do {
      let value = try work()
      guard sqlite3_get_autocommit(db) == 0 else {
        throw DecisionStoreError.database("The decision transaction was rolled back.")
      }
      try decisionSQL(db, outer ? "COMMIT" : "RELEASE photo_decision_save")
      if outer {
        switch kind {
        case .intent: decisionWriteCounters.intentCommits += 1
        case .acknowledgement: decisionWriteCounters.acknowledgementCommits += 1
        case .review: decisionWriteCounters.reviewCommits += 1
        case .recovery: decisionWriteCounters.recoveryCommits += 1
        }
      }
      return value
    } catch {
      if outer {
        _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
      } else {
        _ = sqlite3_exec(db, "ROLLBACK TO photo_decision_save", nil, nil, nil)
        _ = sqlite3_exec(db, "RELEASE photo_decision_save", nil, nil, nil)
      }
      decisionWriteCounters.rollbacks += 1
      throw error
    }
  }
  func acknowledgeDecision(_ local: StoredDecision, identity: String, digest: String) throws
    -> StoredDecision
  {
    let record = StoredDecision(
      decision: local.decision, pending: false, baseline: digest, userModified: local.userModified)
    try withDecisionTransaction(.recovery) {
      if let publication = local.publication {
        try rebaseMetadata(identity: identity, from: publication.before, to: digest)
      }
      try write(record, key: identity)
    }
    return record
  }
  private func decisionSQL(_ db: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
    }
  }
  private func checkBatchCount(_ count: Int) throws {
    guard count <= Self.decisionBatchLimit else {
      throw DecisionStoreError.database("Decision save chunk exceeds its bounded capacity.")
    }
  }
  private func writableDecision(_ request: DecisionWrite) throws -> String {
    try sourceProtection.withWritable([request.image, XMPSidecar.url(for: request.image)]) {
      let identity = try key(for: request.image)
      guard request.expectedIdentity == nil || request.expectedIdentity == identity else {
        throw DecisionStoreError.fileChanged
      }
      return identity
    }
  }
  private func prepareDecision(_ request: DecisionWrite, index: Int, remainingBytes: Int) throws
    -> PreparedDecision
  {
    let identity = try writableDecision(request)
    var local = try read(identity)
    let sidecar = Result { try sidecarData(request.image) }
    if let pending = local, pending.pending, !pending.baseline.hasPrefix("replacement:"),
      let publication = pending.publication, case .success(let current) = sidecar, let current,
      XMPSidecar.digest(current) == publication.after,
      let decision = try? XMPSidecar.read(current), decision == pending.decision
    {
      // Finish a previous durable publication before a retry/Undo replaces its
      // receipt. Otherwise its descriptive baseline could be stranded behind.
      local = try acknowledgeDecision(pending, identity: identity, digest: publication.after)
    }
    let baseline = local?.baseline ?? "absent"
    var record = StoredDecision(
      decision: request.decision, pending: true, baseline: baseline, userModified: true)
    var retained: Data?
    var status: String?
    do {
      let current = try sidecar.get()
      let before = XMPSidecar.digest(current)
      guard request.resolveConflict || before == baseline else { throw SidecarError.conflict }
      let output = try XMPSidecar.merging(request.decision, into: current)
      record.publication = DecisionPublication(before: before, after: XMPSidecar.digest(output))
      if output.count <= remainingBytes { retained = output }
    } catch SidecarError.conflict { status = "XMP conflict" } catch {
      status = "Saved locally · " + error.localizedDescription
    }
    return PreparedDecision(
      index: index, request: request, identity: identity, record: record,
      output: retained, failureStatus: status)
  }
  /// Durable intent for all valid files precedes every sidecar publication.
  /// Per-file failures stay independent; local transaction failures roll back the chunk.
  public func saveDecisions(_ writes: [DecisionWrite]) throws -> [Result<DecisionEntry, any Error>]
  {
    try checkBatchCount(writes.count)
    guard !writes.isEmpty else { return [] }
    try Task.checkCancellation()
    let trace = PhotoTrace.begin("SaveDecisionBatch")
    defer { PhotoTrace.end(trace) }
    return try sourceProtection.withLockedRegistry {
      // Multiple names of one physical file retain ordered single-save semantics.
      let keys = writes.compactMap { try? key(for: $0.image) }
      if Set(keys).count != keys.count {
        return writes.map { request in
          Result {
            try save(
              request.decision, for: request.image, resolveConflict: request.resolveConflict,
              expectedIdentity: request.expectedIdentity)
          }
        }
      }
      var results = writes.map { _ in
        Result<DecisionEntry, any Error>.failure(DecisionStoreError.fileChanged)
      }
      var prepared: [PreparedDecision] = []
      var retainedBytes = 0
      for (index, request) in writes.enumerated() {
        try Task.checkCancellation()
        do {
          let value = try prepareDecision(
            request, index: index,
            remainingBytes: Self.preparedXMPByteLimit - retainedBytes)
          retainedBytes += value.output?.count ?? 0
          prepared.append(value)
        } catch { results[index] = .failure(error) }
      }
      decisionWriteCounters.maximumPreparedXMPBytes = max(
        decisionWriteCounters.maximumPreparedXMPBytes, retainedBytes)
      guard !prepared.isEmpty else { return results }
      try withDecisionTransaction(.intent) {
        for value in prepared {
          try Task.checkCancellation()
          guard try key(for: value.request.image) == value.identity else {
            throw DecisionStoreError.fileChanged
          }
          try write(value.record, key: value.identity)
        }
        try Task.checkCancellation()
      }
      PhotoTrace.event("LocalDecisionBatchCommitted", in: trace)
      try decisionBatchProbe?(.intentCommitted)
      var published: [PublishedDecision] = []
      for value in prepared {
        if let status = value.failureStatus {
          results[value.index] = .success(
            DecisionEntry(decision: value.request.decision, status: status))
          continue
        }
        do {
          let publication = try publishDecision(value)
          published.append(PublishedDecision(prepared: value, publication: publication))
          decisionWriteCounters.sidecarPublications += 1
        } catch SidecarError.conflict {
          results[value.index] = .success(
            DecisionEntry(decision: value.request.decision, status: "XMP conflict"))
        } catch {
          results[value.index] = .success(
            DecisionEntry(
              decision: value.request.decision,
              status: "Saved locally · " + error.localizedDescription))
        }
        if published.last?.prepared.index == value.index {
          try decisionBatchProbe?(.sidecarPublished(value.index))
        }
      }
      guard !published.isEmpty else { return results }
      try decisionBatchProbe?(.beforeAcknowledgement)
      do {
        try withDecisionTransaction(.acknowledgement) {
          for value in published {
            let prepared = value.prepared
            try rebaseMetadata(
              identity: prepared.identity, from: value.publication.before,
              to: value.publication.after)
            var record = prepared.record
            record.pending = false
            record.baseline = value.publication.after
            record.publication = nil
            try write(record, key: prepared.identity)
          }
        }
        for value in published {
          results[value.prepared.index] = .success(
            DecisionEntry(decision: value.prepared.request.decision, status: "Saved"))
        }
      } catch {
        for value in published {
          results[value.prepared.index] = .success(
            DecisionEntry(
              decision: value.prepared.request.decision,
              status: "Saved locally · XMP pending · " + error.localizedDescription)
          )
        }
      }
      return results
    }
  }
  private func publishDecision(_ value: PreparedDecision) throws -> DecisionPublication {
    guard let publication = value.record.publication else { throw SidecarError.malformed }
    let trace = PhotoTrace.begin("DecisionXMP")
    defer { PhotoTrace.end(trace) }
    var coordinationError: NSError?
    var operationError: (any Error)?
    NSFileCoordinator().coordinate(
      writingItemAt: XMPSidecar.url(for: value.request.image), options: .forMerging,
      error: &coordinationError
    ) { _ in
      do {
        guard try key(for: value.request.image) == value.identity else {
          throw DecisionStoreError.fileChanged
        }
        let current = try sidecarData(value.request.image)
        guard XMPSidecar.digest(current) == publication.before else { throw SidecarError.conflict }
        let output = try value.output ?? XMPSidecar.merging(value.request.decision, into: current)
        guard XMPSidecar.digest(output) == publication.after else { throw SidecarError.conflict }
        try output.write(to: XMPSidecar.url(for: value.request.image), options: .atomic)
      } catch { operationError = error }
    }
    if let error = coordinationError { throw error }
    if let error = operationError { throw error }
    return publication
  }
  public func saveSourceDecisions(_ writes: [SourceDecisionWrite], session: SourceReviewSession)
    throws -> [Result<DecisionEntry, any Error>]
  {
    try checkBatchCount(writes.count)
    guard !writes.isEmpty else { return [] }
    try Task.checkCancellation()
    return try sourceProtection.withLockedRegistry {
      if Set(writes.map(\.identity)).count != writes.count {
        return writes.map { request in
          Result {
            try saveSourceDecision(
              request.decision, reviewed: request.reviewed, session: session,
              image: request.image, identity: request.identity, fields: request.fields)
          }
        }
      }
      var results = writes.map { _ in
        Result<DecisionEntry, any Error>.failure(SourceReviewError.unavailable)
      }
      var prepared: [(Int, SourceDecisionWrite, SourceReviewItem)] = []
      for (index, request) in writes.enumerated() {
        try Task.checkCancellation()
        do {
          let key = try validateReview(session, image: request.image, identity: request.identity)
          guard var item = try reviewItem(session.id, identity: key) else {
            throw SourceReviewError.unavailable
          }
          item.decision = request.decision
          item.reviewed = request.reviewed
          item.fields = request.fields ?? (request.reviewed ? .all : [])
          item.revision = (item.revision ?? 0) + 1
          prepared.append((index, request, item))
        } catch { results[index] = .failure(error) }
      }
      guard !prepared.isEmpty else { return results }
      try withDecisionTransaction(.review) {
        for (_, request, item) in prepared {
          try Task.checkCancellation()
          _ = try validateReview(session, image: request.image, identity: request.identity)
          try putReview(item, session: session.id, identity: request.identity)
        }
        try Task.checkCancellation()
      }
      PhotoTrace.event("LocalReviewBatchCommitted")
      for (index, request, item) in prepared {
        results[index] = .success(
          DecisionEntry(
            decision: item.decision, status: "Review saved on this Mac",
            identity: request.identity, reviewed: item.reviewed, sourceReview: session,
            reviewFields: item.fields ?? []))
      }
      return results
    }
  }
}
