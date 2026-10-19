import CSQLite
import Foundation

public struct DecisionEntry: Sendable {
  public let decision: CullingDecision
  public let status: String
  public let identity: String?
  public init(decision: CullingDecision, status: String, identity: String? = nil) {
    self.decision = decision
    self.status = status
    self.identity = identity
  }
  public var conflict: Bool { status == "XMP conflict" }
}

private struct StoredDecision: Codable {
  var decision: CullingDecision
  var pending: Bool
  var baseline: String
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
  private let databaseURL: URL
  public init(databaseURL: URL) { self.databaseURL = databaseURL }

  private func key(for image: URL) throws -> String {
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

  private func withDB<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
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
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 3000)
    guard
      sqlite3_exec(
        db,
        "PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS decisions (identity TEXT PRIMARY KEY, payload BLOB NOT NULL)",
        nil, nil, nil) == SQLITE_OK
    else {
      throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
    }
    return try body(db)
  }

  private func read(_ key: String) throws -> StoredDecision? {
    try withDB { db in
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          db, "SELECT payload FROM decisions WHERE identity = ?", -1, &statement, nil) == SQLITE_OK,
        let statement
      else { throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db))) }
      defer { sqlite3_finalize(statement) }
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      sqlite3_bind_text(statement, 1, key, -1, transient)
      let result = sqlite3_step(statement)
      if result == SQLITE_DONE { return nil }
      guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      return try JSONDecoder().decode(
        StoredDecision.self,
        from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }
  }

  private func write(_ value: StoredDecision, key: String) throws {
    let data = try JSONEncoder().encode(value)
    try withDB { db in
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          db, "INSERT OR REPLACE INTO decisions(identity,payload) VALUES(?,?)", -1, &statement, nil)
          == SQLITE_OK,
        let statement
      else { throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db))) }
      defer { sqlite3_finalize(statement) }
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

  private func sidecarData(_ image: URL) throws -> Data? {
    let url = XMPSidecar.url(for: image)
    if image.pathExtension.lowercased() == "arw" {
      let peers = try FileManager.default.contentsOfDirectory(
        at: image.deletingLastPathComponent(), includingPropertiesForKeys: nil)
      let matches = peers.filter {
        $0.pathExtension.lowercased() == "arw"
          && $0.deletingPathExtension().lastPathComponent
            == image.deletingPathExtension().lastPathComponent
      }
      guard matches.count <= 1 else { throw SidecarError.ambiguous }
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
    let identity = try key(for: image)
    let entry = try loadValue(for: image)
    return DecisionEntry(decision: entry.decision, status: entry.status, identity: identity)
  }

  private func loadValue(for image: URL) throws -> DecisionEntry {
    let identity = try key(for: image)
    let local = try read(identity)
    do {
      let data = try sidecarData(image)
      let digest = XMPSidecar.digest(data)
      if let local, local.pending {
        // Recover a crash after atomic XMP publication but before the SQLite
        // acknowledgement. Matching decisions need no further sidecar write.
        if let data, try XMPSidecar.read(data) == local.decision {
          try write(
            StoredDecision(decision: local.decision, pending: false, baseline: digest),
            key: identity)
          return DecisionEntry(decision: local.decision, status: "Saved")
        }
        return DecisionEntry(
          decision: local.decision,
          status: local.baseline == digest ? "Saved locally · XMP pending" : "XMP conflict")
      }
      if let local, local.baseline == digest {
        return DecisionEntry(decision: local.decision, status: "Saved")
      }
      let decision = try data.map(XMPSidecar.read) ?? local?.decision ?? CullingDecision()
      try write(StoredDecision(decision: decision, pending: false, baseline: digest), key: identity)
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
    let identity = try key(for: image)
    guard expectedIdentity == nil || expectedIdentity == identity else {
      throw DecisionStoreError.fileChanged
    }
    let local = try read(identity)
    // Baseline must come from load: an external edit after loading is a conflict.
    let baseline = local?.baseline ?? "absent"
    var record = StoredDecision(decision: decision, pending: true, baseline: baseline)
    try write(record, key: identity)
    do {
      var coordinationError: NSError?
      var operationError: (any Error)?
      let coordinator = NSFileCoordinator()
      coordinator.coordinate(
        writingItemAt: XMPSidecar.url(for: image), options: .forMerging, error: &coordinationError
      ) { _ in
        do {
          let current = try sidecarData(image)
          guard resolveConflict || XMPSidecar.digest(current) == baseline else {
            throw SidecarError.conflict
          }
          let output = try XMPSidecar.merging(decision, into: current)
          try output.write(to: XMPSidecar.url(for: image), options: .atomic)
          record.baseline = XMPSidecar.digest(output)
        } catch { operationError = error }
      }
      if let error = coordinationError { throw error }
      if let error = operationError { throw error }
      record.pending = false
      try write(record, key: identity)
      return DecisionEntry(decision: decision, status: "Saved")
    } catch SidecarError.conflict {
      return DecisionEntry(decision: decision, status: "XMP conflict")
    } catch {
      return DecisionEntry(
        decision: decision, status: "Saved locally · \(error.localizedDescription)")
    }
  }

  public func useExternal(for image: URL, expectedIdentity: String? = nil) throws -> DecisionEntry {
    let currentIdentity = try key(for: image)
    guard expectedIdentity == nil || expectedIdentity == currentIdentity else {
      throw DecisionStoreError.fileChanged
    }
    let data = try sidecarData(image)
    let decision = try data.map(XMPSidecar.read) ?? CullingDecision()
    try write(
      StoredDecision(decision: decision, pending: false, baseline: XMPSidecar.digest(data)),
      key: key(for: image))
    return DecisionEntry(decision: decision, status: "Saved")
  }
}
