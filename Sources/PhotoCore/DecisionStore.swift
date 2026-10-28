import CSQLite
import Foundation

public struct DecisionEntry: Sendable {
  public let decision: CullingDecision
  public let status: String
  public let identity: String?
  public let reviewFields: SourceDecisionFields
  public let reviewed: Bool
  public let sourceReview: SourceReviewSession?
  public init(
    decision: CullingDecision, status: String, identity: String? = nil, reviewed: Bool = false,
    sourceReview: SourceReviewSession? = nil, reviewFields: SourceDecisionFields = []
  ) {
    self.decision = decision
    self.status = status
    self.identity = identity
    self.reviewFields = reviewFields
    self.reviewed = reviewed
    self.sourceReview = sourceReview
  }
  public var conflict: Bool { status.hasPrefix("XMP conflict") }
}

struct DecisionPublication: Codable {
  let before: String
  let after: String
}
struct StoredDecision: Codable {
  var decision: CullingDecision
  var pending: Bool
  var baseline: String
  // Nil is legacy/unknown intent; only explicit false is a read-only cache seed.
  var userModified: Bool?
  var publication: DecisionPublication? = nil
}

public enum DecisionStoreError: LocalizedError {
  case database(String)
  case fileChanged
  public var errorDescription: String? {
    switch self {
    case .fileChanged: "The image changed since it was opened. Reload before saving decisions."
    case .database(let message): "Local save failed: \(message)"
    }
  }
}

/// SQLite and sidecar work never runs on the main actor or an image worker.
public actor DecisionStore {
  public static let shared = DecisionStore(
    databaseURL: FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Photo/decisions.sqlite"))
  let databaseURL: URL
  public nonisolated let sourceProtection: SourceProtection
  private var connection: SQLiteConnection?
  // Actor-owned, default configuration shared by decision and metadata records.
  let recordEncoder = JSONEncoder()
  let recordDecoder = JSONDecoder()
  var decisionWriteCounters = DecisionWriteStatistics()
  var decisionBatchProbe: (@Sendable (DecisionBatchCheckpoint) throws -> Void)?
  public var decisionWriteStatistics: DecisionWriteStatistics { decisionWriteCounters }
  func setDecisionBatchProbe(_ probe: (@Sendable (DecisionBatchCheckpoint) throws -> Void)?) {
    decisionBatchProbe = probe
  }
  public init(databaseURL: URL, sourceProtection: SourceProtection = .shared) {
    self.databaseURL = databaseURL
    self.sourceProtection = sourceProtection
  }

  var statementStatistics: SQLiteStatementStatistics? { connection?.statistics }

  func withStatement<T>(_ sql: String, _ body: (OpaquePointer, OpaquePointer) throws -> T) throws
    -> T
  {
    // Initialize separately: forwarding an actor-bound body through another
    // actor-bound closure is rejected by older supported Swift compilers.
    if connection == nil { try withDB { _ in () } }
    guard let connection else { throw DecisionStoreError.database("Connection unavailable") }
    return try connection.withStatement(sql, body)
  }

  func key(for image: URL) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(atPath: image.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      throw CocoaError(.fileReadUnsupportedScheme)
    }
    let size = (attributes[.size] as? NSNumber)?.stringValue ?? "?"
    let created = (attributes[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let identity: String
    if let volume = attributes[.systemNumber] as? NSNumber,
      let inode = attributes[.systemFileNumber] as? NSNumber
    {
      identity = "\(volume):\(inode)"
    } else {
      identity = image.standardizedFileURL.path
    }
    return "\(identity):\(created):\(modified):\(size)"
  }

  func withDB<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
    if let connection { return try body(connection.handle) }
    try FileManager.default.createDirectory(
      at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var handle: OpaquePointer?
    guard
      sqlite3_open_v2(
        databaseURL.path, &handle,
        SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
      let db = handle
    else {
      if let handle { sqlite3_close(handle) }
      throw DecisionStoreError.database("Cannot open decisions database")
    }
    let opened = SQLiteConnection(db)
    sqlite3_busy_timeout(db, 3000)
    guard
      sqlite3_exec(
        db,
        "PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS decisions (identity TEXT PRIMARY KEY, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS paths (path TEXT PRIMARY KEY, identity TEXT NOT NULL); CREATE TABLE IF NOT EXISTS descriptive (identity TEXT PRIMARY KEY, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS image_edits (identity TEXT PRIMARY KEY, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS review_copy_receipts (receipt TEXT PRIMARY KEY, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS source_review_items (session TEXT NOT NULL, identity TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(session,identity)); CREATE TABLE IF NOT EXISTS metadata_history (seq INTEGER PRIMARY KEY AUTOINCREMENT, undone INTEGER NOT NULL DEFAULT 0, payload BLOB NOT NULL)",
        nil, nil, nil) == SQLITE_OK
    else {
      throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
    }
    connection = opened
    return try body(db)
  }

  func read(_ key: String) throws -> StoredDecision? {
    try withStatement("SELECT payload FROM decisions WHERE identity = ?") { db, statement in
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      sqlite3_bind_text(statement, 1, key, -1, transient)
      let result = sqlite3_step(statement)
      if result == SQLITE_DONE { return nil }
      guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      return try recordDecoder.decode(
        StoredDecision.self,
        from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }
  }

  func write(_ value: StoredDecision, key: String) throws {
    let data = try recordEncoder.encode(value)
    try withStatement("INSERT OR REPLACE INTO decisions(identity,payload) VALUES(?,?)") {
      db, statement in
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      sqlite3_bind_text(statement, 1, key, -1, transient)
      _ = data.withUnsafeBytes {
        sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient)
      }
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
    }
  }

  func pathIdentity(_ image: URL, update: String? = nil) throws -> String? {
    let sql =
      update == nil
      ? "SELECT identity FROM paths WHERE path = ?"
      : "INSERT OR REPLACE INTO paths(path,identity) VALUES(?,?)"
    return try withStatement(sql) { db, statement in
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      sqlite3_bind_text(statement, 1, image.standardizedFileURL.path, -1, transient)
      if let update { sqlite3_bind_text(statement, 2, update, -1, transient) }
      let result = sqlite3_step(statement)
      if result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) {
        return String(cString: text)
      }
      guard result == SQLITE_DONE else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      return nil
    }
  }

  func sidecarData(_ image: URL) throws -> Data? {
    let url = XMPSidecar.url(for: image)
    if PhotoFormats.isRaw(image) {
      // Check the supported RAW extension spellings directly rather
      // than scanning the entire folder for every photo. The actual on-disk
      // name deduplicates aliases on case-insensitive volumes, while distinct
      // case-only files on case-sensitive volumes still count as collisions.
      var names: Set<String> = []
      for ext in PhotoFormats.rawExtensionSpellings {
        let peer = image.deletingPathExtension().appendingPathExtension(ext)
        do {
          if let name = try peer.resourceValues(forKeys: [.nameKey]).name { names.insert(name) }
        } catch let error as CocoaError
          where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
        {
          continue
        }
      }
      guard names.count <= 1 else { throw SidecarError.ambiguous }
    }
    if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
      throw SidecarError.malformed
    }
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 16 * 1024 * 1024
    else { throw SidecarError.malformed }
    return try Data(contentsOf: url)
  }

  public func load(for image: URL) throws -> DecisionEntry {
    if let session = try sourceReview(for: image) {
      return try loadSourceReview(session, image: image).0
    }
    let identity = try key(for: image)
    let previous = try pathIdentity(image)
    let entry = try loadValue(for: image, identity: identity, previousIdentity: previous)
    if previous != identity { _ = try pathIdentity(image, update: identity) }
    return DecisionEntry(decision: entry.decision, status: entry.status, identity: identity)
  }

  private func loadValue(for image: URL, identity: String, previousIdentity: String?) throws
    -> DecisionEntry
  {
    let local = try read(identity)
    do {
      let data = try sidecarData(image)
      let digest = XMPSidecar.digest(data)
      if local == nil, let previousIdentity, previousIdentity != identity, data != nil {
        // A sidecar left behind at a reused pathname must not silently apply
        // the previous image's decisions to its replacement.
        try write(
          StoredDecision(
            decision: CullingDecision(), pending: true,
            baseline: "replacement:" + digest), key: identity)
        return DecisionEntry(decision: CullingDecision(), status: "XMP conflict · image replaced")
      }
      if let local, local.pending {
        // Recover a crash after atomic XMP publication but before the SQLite
        // acknowledgement. Matching decisions need no further sidecar write.
        if !local.baseline.hasPrefix("replacement:"), let data,
          try XMPSidecar.read(data) == local.decision
        {
          if let publication = local.publication, publication.after != digest {
            return DecisionEntry(
              decision: local.decision,
              status: local.baseline == digest ? "Saved locally · XMP pending" : "XMP conflict")
          }
          _ = try acknowledgeDecision(local, identity: identity, digest: digest)
          return DecisionEntry(decision: local.decision, status: "Saved")
        }
        return DecisionEntry(
          decision: local.decision,
          status: local.baseline.hasPrefix("replacement:")
            ? "XMP conflict · image replaced"
            : local.baseline == digest ? "Saved locally · XMP pending" : "XMP conflict")
      }
      if let local, local.baseline == digest {
        return DecisionEntry(decision: local.decision, status: "Saved")
      }
      let decision = try data.map(XMPSidecar.read) ?? local?.decision ?? CullingDecision()
      try write(
        StoredDecision(
          decision: decision, pending: false, baseline: digest,
          userModified: local == nil ? false : local?.userModified), key: identity)
      return DecisionEntry(decision: decision, status: "Saved")
    } catch {
      if let local {
        return DecisionEntry(
          decision: local.decision, status: "Saved locally · \(error.localizedDescription)")
      }
      throw error
    }
  }

  public func save(
    _ decision: CullingDecision, for image: URL, resolveConflict: Bool = false,
    expectedIdentity: String? = nil
  )
    throws -> DecisionEntry
  {
    try saveDecisions([
      DecisionWrite(
        image: image, decision: decision,
        expectedIdentity: expectedIdentity, resolveConflict: resolveConflict)
    ])[0].get()
  }

  public func useExternal(for image: URL, expectedIdentity: String? = nil) throws -> DecisionEntry {
    return try sourceProtection.withWritable([image]) {
      let currentIdentity = try key(for: image)
      guard expectedIdentity == nil || expectedIdentity == currentIdentity else {
        throw DecisionStoreError.fileChanged
      }
      let data = try sidecarData(image)
      let decision = try data.map(XMPSidecar.read) ?? CullingDecision()
      try write(
        StoredDecision(
          decision: decision, pending: false, baseline: XMPSidecar.digest(data), userModified: true),
        key: currentIdentity)
      return DecisionEntry(decision: decision, status: "Saved")

    }
  }
}
