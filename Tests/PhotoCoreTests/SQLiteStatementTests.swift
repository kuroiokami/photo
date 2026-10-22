import CSQLite
import Foundation
import Testing

@testable import PhotoCore

private enum LeaseFailure: Error { case injected }
private final class CloseProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  func record() { lock.withLock { value = true } }
  var closed: Bool { lock.withLock { value } }
}
struct SQLiteStatementTests {
  private func memory() throws -> SQLiteConnection {
    var pointer: OpaquePointer?
    let code = sqlite3_open(":memory:", &pointer)
    guard code == SQLITE_OK, let pointer else {
      if let pointer { sqlite3_close(pointer) }
      throw DecisionStoreError.database("Cannot open disposable test database")
    }
    return SQLiteConnection(pointer)
  }
  private func execute(_ db: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
    }
  }

  @Test func cachedLeaseResetsRowsBindingsAndThrowingBodies() throws {
    let connection = try memory()
    let sql = "SELECT ?1, ?2"
    try connection.withStatement(sql) { _, statement in
      sqlite3_bind_int(statement, 1, 7)
      sqlite3_bind_int(statement, 2, 9)
      #expect(sqlite3_step(statement) == SQLITE_ROW)
      #expect(sqlite3_column_int(statement, 1) == 9)
    }
    try connection.withStatement(sql) { _, statement in
      sqlite3_bind_int(statement, 1, 42)
      #expect(sqlite3_step(statement) == SQLITE_ROW)
      #expect(sqlite3_column_int(statement, 0) == 42)
      #expect(sqlite3_column_type(statement, 1) == SQLITE_NULL)
    }
    #expect(throws: LeaseFailure.self) {
      try connection.withStatement(sql) { _, statement in
        sqlite3_bind_int(statement, 1, 99)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        throw LeaseFailure.injected
      }
    }
    try connection.withStatement(sql) { _, statement in
      #expect(sqlite3_step(statement) == SQLITE_ROW)
      #expect(sqlite3_column_type(statement, 0) == SQLITE_NULL)
    }
    #expect(connection.statistics.preparations == 1)
    #expect(connection.statistics.hits == 3)
  }

  @Test func nestedSameSQLUsesTemporaryLeaseAndCapacityIsBounded() throws {
    let connection = try memory()
    let sql = "SELECT ?"
    try connection.withStatement(sql) { _, outer in
      sqlite3_bind_int(outer, 1, 42)
      #expect(sqlite3_step(outer) == SQLITE_ROW)
      try connection.withStatement(sql) { _, inner in
        #expect(inner != outer)
        sqlite3_bind_int(inner, 1, 7)
        #expect(sqlite3_step(inner) == SQLITE_ROW)
        #expect(sqlite3_column_int(inner, 0) == 7)
      }
      #expect(sqlite3_column_int(outer, 0) == 42)
    }
    #expect(connection.statistics.temporary == 1)
    for i in 0..<40 {
      try connection.withStatement("SELECT \(i)") { _, statement in
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == i)
      }
    }
    #expect(connection.statistics.retained == 32)
    var count = 0
    var statement = sqlite3_next_stmt(connection.handle, nil)
    while let current = statement {
      #expect(sqlite3_stmt_busy(current) == 0)
      count += 1
      statement = sqlite3_next_stmt(connection.handle, current)
    }
    #expect(count == 32)
  }

  @Test func rollbackPrepareErrorsAndSchemaChangesDoNotPoisonReuse() throws {
    let connection = try memory()
    try execute(
      connection.handle,
      "CREATE TABLE entries(value INTEGER); CREATE TRIGGER fail BEFORE INSERT ON entries WHEN NEW.value=2 BEGIN SELECT RAISE(ROLLBACK,'injected rollback'); END"
    )
    let insert = "INSERT INTO entries(value) VALUES(?)"
    try execute(connection.handle, "BEGIN IMMEDIATE")
    try connection.withStatement(insert) { db, statement in
      sqlite3_bind_int(statement, 1, 1)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
    }
    #expect(throws: (any Error).self) {
      try connection.withStatement(insert) { db, statement in
        sqlite3_bind_int(statement, 1, 2)
        guard sqlite3_step(statement) == SQLITE_DONE else {
          throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
        }
      }
    }
    #expect(sqlite3_get_autocommit(connection.handle) != 0)
    // Even a body that forgets to throw a failing step must not receive a
    // successful result when sqlite3_reset reports that execution error.
    #expect(throws: (any Error).self) {
      try connection.withStatement(insert) { _, statement in
        sqlite3_bind_int(statement, 1, 2)
        #expect(sqlite3_step(statement) != SQLITE_DONE)
      }
    }
    try execute(connection.handle, "DROP TRIGGER fail")
    try connection.withStatement(insert) { _, statement in
      sqlite3_bind_int(statement, 1, 3)
      #expect(sqlite3_step(statement) == SQLITE_DONE)
    }
    let select = "SELECT value FROM entries"
    try connection.withStatement(select) { _, statement in
      #expect(sqlite3_step(statement) == SQLITE_ROW)
      #expect(sqlite3_column_int(statement, 0) == 3)
    }
    try execute(
      connection.handle,
      "DROP TABLE entries; CREATE TABLE entries(value INTEGER); INSERT INTO entries VALUES(4)")
    try connection.withStatement(select) { _, statement in
      #expect(sqlite3_step(statement) == SQLITE_ROW)
      #expect(sqlite3_column_int(statement, 0) == 4)
    }
    #expect(throws: (any Error).self) {
      try connection.withStatement("SELECT missing FROM entries") { _, _ in }
    }
    #expect(connection.statistics.retained == 2)
  }

  @Test func cachedStatementsAreFinalizedBeforeConnectionCloses() throws {
    var connection: SQLiteConnection? = try memory()
    let probe = CloseProbe()
    let context = Unmanaged.passRetained(probe).toOpaque()
    let db = try #require(connection).handle
    let code = sqlite3_create_function_v2(
      db, "close_probe", 0, SQLITE_UTF8, context,
      { context, _, _ in sqlite3_result_null(context) }, nil, nil,
      { context in
        if let context { Unmanaged<CloseProbe>.fromOpaque(context).takeRetainedValue().record() }
      })
    #expect(code == SQLITE_OK)
    try connection?.withStatement("SELECT close_probe()") { _, statement in
      #expect(sqlite3_step(statement) == SQLITE_ROW)
    }
    #expect(!probe.closed)
    connection = nil
    #expect(probe.closed)
  }

  @Test func realStoreReusesStatementsAndReopensWithIndependentBindings() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = DecisionStore(databaseURL: root.appendingPathComponent("decisions.sqlite"))
    let paths = [root.appendingPathComponent("one.jpg"), root.appendingPathComponent("two.jpg")]
    for i in 0..<20 {
      let key = String(i)
      try await store.write(
        StoredDecision(
          decision: CullingDecision(rating: i % 6), pending: false, baseline: "digest-" + key),
        key: key)
      _ = try await store.pathIdentity(paths[i % 2], update: key)
      #expect(try await store.read(key)?.decision.rating == i % 6)
      #expect(try await store.pathIdentity(paths[i % 2]) == key)
    }
    let statistics = try #require(await store.statementStatistics)
    #expect(statistics.preparations == 4)
    #expect(statistics.hits == 76)
    let reopened = DecisionStore(databaseURL: root.appendingPathComponent("decisions.sqlite"))
    #expect(try await reopened.read("19")?.decision.rating == 1)
    #expect(try await reopened.pathIdentity(paths[0]) == "18")
    #expect(try await reopened.pathIdentity(paths[1]) == "19")
  }
  @Test func sourceReviewBindingsAndCodersStayIndependentAcrossSessionsAndDecodeFailure()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let protection = SourceProtection(
      registryURL: root.appendingPathComponent("state/protection.json"))
    let database = root.appendingPathComponent("state/decisions.sqlite")
    let store = DecisionStore(databaseURL: database, sourceProtection: protection)
    let a = root.appendingPathComponent("card-one/café.jpg")
    let b = root.appendingPathComponent("card-two/日本.jpg")
    for image in [a, b] {
      try FileManager.default.createDirectory(
        at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(image.lastPathComponent.utf8).write(to: image)
    }
    let first = try await store.beginSourceReview(a.deletingLastPathComponent())
    let second = try await store.beginSourceReview(b.deletingLastPathComponent())
    let entry = try await store.loadSourceReview(first, image: a).0
    _ = try await store.loadSourceReview(second, image: b)
    let identity = try #require(entry.identity)
    let decision = CullingDecision(rating: 5, flag: .pick)
    _ = try await store.saveSourceDecision(
      decision, reviewed: true, session: first, image: a, identity: identity)
    for _ in 0..<20 {
      #expect(try await store.loadSourceReview(first, image: a).0.decision == decision)
      #expect(try await store.loadSourceReview(second, image: b).0.decision == CullingDecision())
      #expect(try await store.reviewItem(second.id, identity: identity) == nil)
    }
    #expect(await store.statementStatistics?.preparations == 2)
    try await store.withStatement("UPDATE source_review_items SET payload=x'FF' WHERE identity=?") {
      db, statement in
      sqlite3_bind_text(
        statement, 1, identity, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
    }
    await #expect(throws: (any Error).self) { try await store.loadSourceReview(first, image: a) }
    #expect(try await store.loadSourceReview(second, image: b).0.decision == CullingDecision())
    let reopened = DecisionStore(databaseURL: database, sourceProtection: protection)
    #expect(try await reopened.loadSourceReview(second, image: b).0.reviewed == false)
    for image in [a, b] {
      #expect(try Data(contentsOf: image) == Data(image.lastPathComponent.utf8))
      #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: image).path))
    }
  }

}
