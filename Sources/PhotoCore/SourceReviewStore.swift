import CSQLite
import Foundation

struct SourceReviewItem: Codable {
  var decision: CullingDecision
  var edit: PhotoEdit
  var reviewed: Bool
  var fields: SourceDecisionFields?
  var revision: Int?
  let baseline: String
  let warning: String?
}

extension DecisionStore {
  public func beginSourceReview(_ root: URL) throws -> SourceReviewSession {
    let path = PhotoPath.canonical(root).pathComponents
    let dataFolder = PhotoPath.canonical(databaseURL.deletingLastPathComponent()).pathComponents
    guard !PhotoPath.canonical(databaseURL).pathComponents.starts(with: path),
      !path.starts(with: dataFolder)
    else {
      throw SourceReviewError.localData
    }
    return try sourceProtection.protect(root)
  }
  public func sourceReview(for url: URL) throws -> SourceReviewSession? {
    try sourceProtection.session(for: url)
  }
  func validateReview(_ session: SourceReviewSession, image: URL, identity: String?) throws
    -> String
  {
    guard try sourceProtection.session(for: image)?.id == session.id else {
      throw SourceReviewError.sourceChanged
    }
    let current = try key(for: image)
    guard identity == nil || identity == current else { throw DecisionStoreError.fileChanged }
    return current
  }
  func reviewItem(_ session: UUID, identity: String) throws -> SourceReviewItem? {
    try withStatement("SELECT payload FROM source_review_items WHERE session=? AND identity=?") {
      db, statement in
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      sqlite3_bind_text(statement, 1, session.uuidString, -1, transient)
      sqlite3_bind_text(statement, 2, identity, -1, transient)
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return nil }
      guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      return try recordDecoder.decode(
        SourceReviewItem.self,
        from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }
  }
  func putReview(_ item: SourceReviewItem, session: UUID, identity: String) throws {
    let payload = try recordEncoder.encode(item)
    try withStatement(
      "INSERT OR REPLACE INTO source_review_items(session,identity,payload) VALUES(?,?,?)"
    ) { db, statement in
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      sqlite3_bind_text(statement, 1, session.uuidString, -1, transient)
      sqlite3_bind_text(statement, 2, identity, -1, transient)
      _ = payload.withUnsafeBytes {
        sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32($0.count), transient)
      }
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
    }
  }
  public func loadSourceReview(_ session: SourceReviewSession, image: URL) throws -> (
    DecisionEntry, PhotoEdit
  ) {
    let identity = try validateReview(session, image: image, identity: nil)
    var item = try reviewItem(session.id, identity: identity)
    if item == nil {
      var decision = CullingDecision()
      var baseline = "unavailable"
      var warning: String?
      do {
        let data = try sidecarData(image)
        decision = try data.map(XMPSidecar.read) ?? CullingDecision()
        baseline = XMPSidecar.digest(data)
      } catch { warning = "Existing metadata unavailable: " + error.localizedDescription }
      let initial = SourceReviewItem(
        decision: decision, edit: PhotoEdit(), reviewed: false, baseline: baseline, warning: warning
      )
      try putReview(initial, session: session.id, identity: identity)
      item = initial
    }
    guard let item else { throw SourceReviewError.unavailable }
    let status =
      item.warning.map { "Review saved on this Mac · " + $0 } ?? "Review saved on this Mac"
    return (
      DecisionEntry(
        decision: item.decision, status: status, identity: identity, reviewed: item.reviewed,
        sourceReview: session, reviewFields: item.fields ?? (item.reviewed ? .all : [])),
      item.edit
    )
  }
  public func saveSourceDecision(
    _ decision: CullingDecision, reviewed: Bool, session: SourceReviewSession, image: URL,
    identity: String, fields: SourceDecisionFields? = nil
  ) throws -> DecisionEntry {
    try saveSourceDecisions(
      [
        SourceDecisionWrite(
          image: image, identity: identity, decision: decision,
          reviewed: reviewed, fields: fields)
      ], session: session)[0].get()
  }
  public func saveSourceEdits(_ writes: [ImageEditWrite], session: SourceReviewSession) throws {
    let items = try writes.map { write -> (ImageEditWrite, SourceReviewItem) in
      let key = try validateReview(session, image: write.image, identity: write.identity)
      guard var item = try reviewItem(session.id, identity: key) else {
        throw SourceReviewError.unavailable
      }
      item.edit = write.edit
      item.revision = (item.revision ?? 0) + 1
      return (write, item)
    }
    try withDB { db in
      guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
        throw SourceReviewError.unavailable
      }
      do {
        for (write, item) in items {
          try putReview(item, session: session.id, identity: write.identity)
        }
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
          throw SourceReviewError.unavailable
        }
      } catch {
        _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
        throw error
      }
    }
  }
}
