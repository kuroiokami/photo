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
  public func loadImageState(for image: URL) throws -> (DecisionEntry, PhotoEdit) {
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
    let identity = try key(for: image)
    return try withDB { db in
      var stmt: OpaquePointer?
      guard
        sqlite3_prepare_v2(db, "SELECT payload FROM image_edits WHERE identity=?", -1, &stmt, nil)
          == SQLITE_OK, let stmt
      else { throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db))) }
      defer { sqlite3_finalize(stmt) }
      sqlite3_bind_text(stmt, 1, identity, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      let step = sqlite3_step(stmt)
      if step == SQLITE_DONE { return PhotoEdit() }
      guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      let value = try JSONDecoder().decode(
        PhotoEdit.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
      return PhotoEdit(quarterTurns: value.turns, mirrored: value.mirrored, crop: value.crop)
    }
  }
  /// Local-only edits: original bytes and existing XMP/develop settings are never rewritten.
  public func saveImageEdits(_ writes: [ImageEditWrite]) throws {
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
          let data = try JSONEncoder().encode(write.edit)
          var stmt: OpaquePointer?
          guard
            sqlite3_prepare_v2(
              db, "INSERT OR REPLACE INTO image_edits(identity,payload) VALUES(?,?)", -1, &stmt, nil
            ) == SQLITE_OK, let stmt
          else { throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db))) }
          defer { sqlite3_finalize(stmt) }
          let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
          sqlite3_bind_text(stmt, 1, write.identity, -1, transient)
          _ = data.withUnsafeBytes {
            sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32($0.count), transient)
          }
          guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
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
