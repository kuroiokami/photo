import CSQLite
import Foundation

struct SQLiteStatementStatistics: Sendable, Equatable {
  let preparations: Int
  let hits: Int
  let retained: Int
  let temporary: Int
}

/// Only the owning DecisionStore actor uses this connection. Synchronous leases
/// never cross an await; the wrapper also owns finalization/close at destruction.
final class SQLiteConnection: @unchecked Sendable {
  let handle: OpaquePointer
  private let capacity = 32
  private var statements: [String: OpaquePointer] = [:]
  private var leased: Set<String> = []
  private var preparations = 0
  private var hits = 0
  private var temporary = 0

  init(_ handle: OpaquePointer) { self.handle = handle }
  deinit {
    for statement in statements.values { sqlite3_finalize(statement) }
    sqlite3_close(handle)
  }
  var statistics: SQLiteStatementStatistics {
    SQLiteStatementStatistics(
      preparations: preparations, hits: hits,
      retained: statements.count, temporary: temporary)
  }

  func withStatement<T>(_ sql: String, _ body: (OpaquePointer, OpaquePointer) throws -> T) throws
    -> T
  {
    let statement: OpaquePointer
    let retained: Bool
    if let cached = statements[sql], !leased.contains(sql) {
      statement = cached
      retained = true
      hits += 1
    } else {
      preparations += 1
      var compiled: OpaquePointer?
      let code = sqlite3_prepare_v2(handle, sql, -1, &compiled, nil)
      guard code == SQLITE_OK, let compiled else {
        if let compiled { sqlite3_finalize(compiled) }
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(handle)))
      }
      statement = compiled
      retained = statements[sql] == nil && statements.count < capacity
      if retained { statements[sql] = statement } else { temporary += 1 }
    }
    if retained { leased.insert(sql) }
    var cleaned = false
    defer {
      if !cleaned {
        // On a failed step reset reports the previous error while still
        // resetting execution. Preserve the original body error for the caller.
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
      }
      if retained { leased.remove(sql) } else { sqlite3_finalize(statement) }
    }
    let value = try body(handle, statement)
    // Reset can surface a late SQLite error even after a successful row. Never
    // acknowledge a successful operation when that cleanup reports failure.
    let reset = sqlite3_reset(statement)
    if reset != SQLITE_OK {
      let message = String(cString: sqlite3_errmsg(handle))
      sqlite3_clear_bindings(statement)
      cleaned = true
      throw DecisionStoreError.database(message)
    }
    let clear = sqlite3_clear_bindings(statement)
    cleaned = true
    guard clear == SQLITE_OK else {
      throw DecisionStoreError.database(String(cString: sqlite3_errmsg(handle)))
    }
    return value
  }
}
