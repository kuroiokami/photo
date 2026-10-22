import CSQLite
import Foundation

public struct ImageEditWrite: Sendable {
  public let image: URL
  public let identity: String
  public let edit: PhotoEdit
  public init(image: URL, identity: String, edit: PhotoEdit) {
    self.image = image
    self.identity = identity
    self.edit = edit
  }
}
extension DecisionStore {
  /// Small bounded transactions amortize first-discovery cache seeds and path mappings.
  /// This path reads sidecars; it never publishes XMP or changes user decisions.
  public func loadImageStates(for images: [URL]) throws -> [Result<
    (DecisionEntry, PhotoEdit), any Error
  >] {
    var results: [Result<(DecisionEntry, PhotoEdit), any Error>] = []
    for start in stride(from: 0, to: images.count, by: 16) {
      try Task.checkCancellation()
      let batch = images[start..<min(start + 16, images.count)]
      let values = try withDB { db in
        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
          throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
        }
        do {
          var values: [Result<(DecisionEntry, PhotoEdit), any Error>] = []
          for image in batch {
            try Task.checkCancellation()
            values.append(Result { try loadImageState(for: image) })
            // A SQLite error/trigger may roll back the transaction automatically.
            // Stop before any later photo could accidentally run in autocommit mode.
            guard sqlite3_get_autocommit(db) == 0 else {
              throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
            }
          }
          try Task.checkCancellation()
          guard sqlite3_get_autocommit(db) == 0,
            sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK
          else {
            throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
          }
          return values
        } catch {
          _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
          throw error
        }
      }
      results += values
    }
    return results
  }

  public func loadImageState(for image: URL) throws -> (DecisionEntry, PhotoEdit) {
    if let session = try sourceReview(for: image) {
      return try loadSourceReview(session, image: image)
    }
    let entry = try load(for: image)
    do { return (entry, try loadImageEdit(for: image)) } catch {
      return (
        DecisionEntry(
          decision: entry.decision,
          status: entry.status + " · image edits unavailable: " + error.localizedDescription,
          identity: entry.identity), PhotoEdit()
      )
    }
  }
  public func loadImageEdit(for image: URL) throws -> PhotoEdit {
    if let session = try sourceReview(for: image) {
      return try loadSourceReview(session, image: image).1
    }
    let identity = try key(for: image)
    return try withStatement("SELECT payload FROM image_edits WHERE identity=?") { db, stmt in
      sqlite3_bind_text(stmt, 1, identity, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      let step = sqlite3_step(stmt)
      if step == SQLITE_DONE { return PhotoEdit() }
      guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      let value = try recordDecoder.decode(
        PhotoEdit.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
      return PhotoEdit(quarterTurns: value.turns, mirrored: value.mirrored, crop: value.crop)
    }
  }
  /// Local-only edits: original bytes and existing XMP/develop settings are never rewritten.
  public func saveImageEdits(_ writes: [ImageEditWrite]) throws {
    return try sourceProtection.withWritable(writes.map(\.image)) {
      for write in writes {
        guard try key(for: write.image) == write.identity else {
          throw DecisionStoreError.fileChanged
        }
      }
      try withDB { db in
        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
          throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
        }
        do {
          for write in writes {
            let data = try recordEncoder.encode(write.edit)
            try withStatement("INSERT OR REPLACE INTO image_edits(identity,payload) VALUES(?,?)") {
              db, stmt in
              let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
              sqlite3_bind_text(stmt, 1, write.identity, -1, transient)
              _ = data.withUnsafeBytes {
                sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32($0.count), transient)
              }
              guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
              }
            }
          }
          guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
          }
        } catch {
          _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
          throw error
        }
      }

    }
  }
}
