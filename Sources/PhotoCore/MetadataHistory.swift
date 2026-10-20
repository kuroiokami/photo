import CSQLite
import Foundation

public struct MetadataHistoryState: Sendable {
  public let undoCount: Int
  public let redoCount: Int
  public let undoSummary: String?
  public let redoSummary: String?
}

extension DecisionStore {
  /// One durable local transaction commits all intent and its Undo history before
  /// sidecar synchronization. Interrupted/failed sync remains retryable locally.
  public func saveMetadataBatch(_ plans: [MetadataFilePlan]) throws -> [String: MetadataEntry] {
    try commitMetadataBatch(plans, history: nil)
  }
  public func metadataHistoryState() throws -> MetadataHistoryState {
    let undo = try metadataHistory(undone: false)
    let redo = try metadataHistory(undone: true)
    return MetadataHistoryState(
      undoCount: undo?.plans.count ?? 0, redoCount: redo?.plans.count ?? 0,
      undoSummary: undo.map { Self.historySummary($0.plans) },
      redoSummary: redo.map { Self.historySummary($0.plans) })
  }
  private static func historySummary(_ plans: [MetadataFilePlan]) -> String {
    var fields = Set(plans.flatMap { $0.fields }).map(\.rawValue).sorted()
    if plans.contains(where: \.changesKeywords) { fields.append("Keywords") }
    let names = fields.prefix(2).joined(separator: ", ") + (fields.count > 2 ? ", …" : "")
    return names + " · \(plans.count) " + (plans.count == 1 ? "file" : "files")
  }
  private static func historyProjection(_ plan: MetadataFilePlan) -> MetadataFilePlan {
    func project(_ source: DescriptiveMetadata) -> DescriptiveMetadata {
      var value = DescriptiveMetadata()
      for field in plan.fields { value.fields[field] = source.fields[field] ?? "" }
      if plan.changesKeywords {
        value.keywords = source.keywords
        value.hierarchy = source.hierarchy
        value.keywordsPresent = source.keywordsPresent
        value.hierarchyPresent = source.hierarchyPresent
      }
      return value
    }
    return MetadataFilePlan(
      image: plan.image, identity: plan.identity, baseline: plan.baseline,
      before: project(plan.before), after: project(plan.after), fields: plan.fields,
      changesKeywords: plan.changesKeywords, embedded: nil)
  }
  public func undoMetadataBatch() throws -> [String: MetadataEntry] {
    try replayMetadata(undo: true)
  }
  public func redoMetadataBatch() throws -> [String: MetadataEntry] {
    try replayMetadata(undo: false)
  }

  private struct HistoryBatch {
    let sequence: Int64
    let plans: [MetadataFilePlan]
  }
  private func replayMetadata(undo: Bool) throws -> [String: MetadataEntry] {
    guard let batch = try metadataHistory(undone: !undo) else { return [:] }
    let plans = try batch.plans.map { plan in
      let current = try loadMetadata(for: plan.image, embedded: plan.embedded)
      guard current.identity == plan.identity else { throw DecisionStoreError.fileChanged }
      let expected = undo ? plan.after : plan.before
      guard Self.ownedMetadataMatches(current.value, expected, plan: plan) else {
        throw MediaOperationError.invalid(
          "Metadata Undo/Redo stopped: a field changed after this batch. Review the current metadata first."
        )
      }
      let target = Self.replacingOwned(
        current.value, from: undo ? plan.before : plan.after, plan: plan)
      return MetadataFilePlan(
        image: plan.image, identity: current.identity, baseline: current.baseline,
        before: current.value, after: target, fields: plan.fields,
        changesKeywords: plan.changesKeywords,
        embedded: plan.embedded)
    }
    return try commitMetadataBatch(plans, history: (batch.sequence, undo))
  }

  private static func ownedMetadataMatches(
    _ a: DescriptiveMetadata, _ b: DescriptiveMetadata, plan: MetadataFilePlan
  ) -> Bool {
    plan.fields.allSatisfy { (a.fields[$0] ?? "") == (b.fields[$0] ?? "") }
      && (!plan.changesKeywords || (a.keywords == b.keywords && a.hierarchy == b.hierarchy))
  }
  private static func replacingOwned(
    _ current: DescriptiveMetadata, from target: DescriptiveMetadata, plan: MetadataFilePlan
  ) -> DescriptiveMetadata {
    var value = current
    for field in plan.fields { value.fields[field] = target.fields[field] ?? "" }
    if plan.changesKeywords {
      value.keywords = target.keywords
      value.hierarchy = target.hierarchy
      value.keywordsPresent = target.keywordsPresent
      value.hierarchyPresent = target.hierarchyPresent
    }
    return value
  }

  private func commitMetadataBatch(_ plans: [MetadataFilePlan], history: (Int64, Bool)?) throws
    -> [String: MetadataEntry]
  {
    try Task.checkCancellation()
    guard !plans.isEmpty else { return [:] }
    guard Set(plans.map(\.identity)).count == plans.count else {
      throw MediaOperationError.invalid("A metadata batch must contain each physical file once.")
    }
    var normalized: [MetadataFilePlan] = []
    var records: [StoredMetadata] = []
    // Preflight the whole batch before recording any new local intent.
    for plan in plans {
      let current = try loadMetadata(for: plan.image, embedded: plan.embedded)
      guard current.identity == plan.identity else { throw DecisionStoreError.fileChanged }
      guard Self.ownedMetadataMatches(current.value, plan.before, plan: plan) else {
        throw MediaOperationError.invalid(
          "Metadata changed since the preview. Preview this batch again.")
      }
      let previous = try metadataRecord(plan.identity)
      let value = Self.replacingOwned(current.value, from: plan.after, plan: plan)
      normalized.append(
        MetadataFilePlan(
          image: plan.image, identity: plan.identity, baseline: plan.baseline,
          before: current.value, after: value, fields: plan.fields,
          changesKeywords: plan.changesKeywords,
          embedded: plan.embedded ?? previous?.embedded))
      records.append(
        StoredMetadata(
          value: value, baseline: plan.baseline, pending: true,
          fields: previous?.pending == true
            ? plan.fields.union(previous?.fields ?? []) : plan.fields,
          changesKeywords: plan.changesKeywords
            || (previous?.pending == true && previous?.changesKeywords == true),
          embedded: plan.embedded ?? previous?.embedded))
    }
    try Task.checkCancellation()
    try withDB { db in
      try Self.metadataSQL(db, "BEGIN IMMEDIATE")
      do {
        for (plan, record) in zip(normalized, records) {
          try putMetadata(record, identity: plan.identity)
        }
        if let history {
          try Self.metadataSQL(
            db, "UPDATE metadata_history SET undone=\(history.1 ? 1 : 0) WHERE seq=\(history.0)")
        } else {
          try Self.metadataSQL(db, "DELETE FROM metadata_history WHERE undone=1")
          let payload = try JSONEncoder().encode(normalized.map(Self.historyProjection))
          var statement: OpaquePointer?
          guard
            sqlite3_prepare_v2(
              db, "INSERT INTO metadata_history(payload) VALUES(?)", -1, &statement, nil)
              == SQLITE_OK,
            let statement
          else { throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db))) }
          defer { sqlite3_finalize(statement) }
          _ = payload.withUnsafeBytes {
            sqlite3_bind_blob(
              statement, 1, $0.baseAddress, Int32($0.count),
              unsafeBitCast(-1, to: sqlite3_destructor_type.self))
          }
          guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
          }
          try Self.metadataSQL(
            db,
            "DELETE FROM metadata_history WHERE seq NOT IN (SELECT seq FROM metadata_history ORDER BY seq DESC LIMIT 20)"
          )
        }
        try Self.metadataSQL(db, "COMMIT")
      } catch {
        _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
        throw error
      }
    }
    var result: [String: MetadataEntry] = [:]
    for (plan, record) in zip(normalized, records) {
      if Task.isCancelled {
        result[plan.image.path] = MetadataEntry(
          value: record.value, identity: plan.identity,
          baseline: record.baseline, status: "Saved locally · metadata XMP pending")
      } else {
        result[plan.image.path] = try syncMetadata(
          record, image: plan.image, identity: plan.identity, useLocal: false)
      }
    }
    return result
  }

  private static func metadataSQL(_ db: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
    }
  }
  private func metadataHistory(undone: Bool) throws -> HistoryBatch? {
    try withDB { db in
      var statement: OpaquePointer?
      let sql =
        "SELECT seq,payload FROM metadata_history WHERE undone=\(undone ? 1 : 0) ORDER BY seq \(undone ? "ASC" : "DESC") LIMIT 1"
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      defer { sqlite3_finalize(statement) }
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return nil }
      guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 1) else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
      return HistoryBatch(
        sequence: sqlite3_column_int64(statement, 0),
        plans: try JSONDecoder().decode([MetadataFilePlan].self, from: data))
    }
  }
}
