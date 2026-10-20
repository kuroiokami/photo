import CSQLite
import Foundation

struct ReviewCopyReceipt: Codable {
  let image: URL
  let identity: String
  let decision: CullingDecision
  let fields: SourceDecisionFields
  let baseline: String
  let intendedDigest: String
  var complete: Bool
}
public struct ReviewTransferStatus: Sendable {
  public let pending: Int
  public let preserved: Int
  public let pendingImages: [URL]
}

extension DecisionStore {
  private func receiptKey(_ plan: UUID, _ target: URL) -> String {
    plan.uuidString + ":" + target.standardizedFileURL.path
  }
  func reviewReceipt(_ plan: UUID, target: URL) throws -> ReviewCopyReceipt? {
    try withDB { db in
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          db, "SELECT payload FROM review_copy_receipts WHERE receipt=?", -1, &statement, nil)
          == SQLITE_OK,
        let statement
      else { throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db))) }
      defer { sqlite3_finalize(statement) }
      sqlite3_bind_text(
        statement, 1, receiptKey(plan, target), -1,
        unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return nil }
      guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      return try JSONDecoder().decode(
        ReviewCopyReceipt.self,
        from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }
  }
  private func putReceipt(_ receipt: ReviewCopyReceipt, plan: UUID) throws {
    let data = try JSONEncoder().encode(receipt)
    try withDB { db in
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          db, "INSERT OR REPLACE INTO review_copy_receipts(receipt,payload) VALUES(?,?)", -1,
          &statement, nil) == SQLITE_OK,
        let statement
      else { throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db))) }
      defer { sqlite3_finalize(statement) }
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      sqlite3_bind_text(statement, 1, receiptKey(plan, receipt.image), -1, transient)
      _ = data.withUnsafeBytes {
        sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient)
      }
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
    }
  }
  private func hasImageEditRecord(_ identity: String) throws -> Bool {
    try withDB { db in
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(db, "SELECT 1 FROM image_edits WHERE identity=?", -1, &statement, nil)
          == SQLITE_OK,
        let statement
      else { throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db))) }
      defer { sqlite3_finalize(statement) }
      sqlite3_bind_text(
        statement, 1, identity, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      let step = sqlite3_step(statement)
      guard step == SQLITE_ROW || step == SQLITE_DONE else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      return step == SQLITE_ROW
    }
  }
  private func putTransferredEdit(_ edit: PhotoEdit, identity: String) throws {
    let data = try JSONEncoder().encode(edit)
    try withDB { db in
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          db, "INSERT OR REPLACE INTO image_edits(identity,payload) VALUES(?,?)", -1, &statement,
          nil) == SQLITE_OK,
        let statement
      else { throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db))) }
      defer { sqlite3_finalize(statement) }
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      sqlite3_bind_text(statement, 1, identity, -1, transient)
      _ = data.withUnsafeBytes {
        sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient)
      }
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
    }
  }

  public func validateReviewCopySources(_ plan: ReviewedCopyPlan, images: [ReviewCopyImage]) throws
  {
    for image in images {
      _ = try validateReview(plan.session, image: image.source, identity: image.identity)
      guard try XMPSidecar.digest(sidecarData(image.source)) == image.sidecarDigest else {
        throw MediaOperationError.invalid(
          "Source metadata changed after the copy list was prepared. Prepare a new list; the saved list was not silently changed."
        )
      }
    }
  }

  private func canSeedReviewedCopy(_ image: URL, identity: String, baseline: String) throws -> Bool
  {
    if let previous = try pathIdentity(image), previous != identity { return false }
    if try hasImageEditRecord(identity) { return false }
    if let metadata = try metadataRecord(identity),
      metadata.pending || !metadata.fields.isEmpty || metadata.changesKeywords
    {
      return false
    }
    guard let existing = try read(identity) else { return true }
    guard existing.userModified == false && !existing.pending && existing.baseline == baseline
    else { return false }
    let original = try sidecarData(image).map(XMPSidecar.read) ?? CullingDecision()
    return existing.decision == original
  }

  /// Both destinations' decisions, edits, pending intent and receipts commit together.
  /// A receipt prevents replay over later destination decisions on every retry.
  public func installReviewCopy(
    _ plan: ReviewedCopyPlan, family: ReviewCopyFamily, expectedImages: [URL: FileFingerprint]
  ) throws {
    let targets = family.images.flatMap { image in
      [plan.primary, plan.backup].map { root in
        let relative = image.source.pathComponents.dropFirst(plan.session.root.pathComponents.count)
          .joined(separator: "/")
        return (image, root.appendingPathComponent(relative))
      }
    }
    try sourceProtection.withWritable(targets.flatMap { [$0.1, XMPSidecar.url(for: $0.1)] }) {
      var pending: [(ReviewCopyReceipt, PhotoEdit)] = []
      for (source, target) in targets {
        guard let expected = expectedImages[target], try FileFingerprint.read(target) == expected
        else {
          throw DecisionStoreError.fileChanged
        }
        let identity = try key(for: target)
        if let receipt = try reviewReceipt(plan.id, target: target) {
          guard identity == receipt.identity else { throw DecisionStoreError.fileChanged }
          continue
        }
        guard try canSeedReviewedCopy(target, identity: identity, baseline: source.sidecarDigest)
        else {
          throw MediaOperationError.invalid(
            "\(target.lastPathComponent) already has local decisions or edits. Resume its saved copy, or choose a new shoot name; existing work was left untouched."
          )
        }
        let data = try sidecarData(target)
        guard XMPSidecar.digest(data) == source.sidecarDigest else { throw SidecarError.conflict }
        let output =
          try source.fields.isEmpty
          ? data : XMPSidecar.merging(source.decision, into: data, fields: source.fields)
        let current = try output.map(XMPSidecar.read) ?? CullingDecision()
        let receipt = ReviewCopyReceipt(
          image: target, identity: identity, decision: current, fields: source.fields,
          baseline: XMPSidecar.digest(data), intendedDigest: XMPSidecar.digest(output),
          complete: source.fields.isEmpty)
        pending.append((receipt, source.edit))
      }
      try withDB { db in
        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
          throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
        }
        do {
          for (receipt, edit) in pending {
            guard try key(for: receipt.image) == receipt.identity,
              try FileFingerprint.read(receipt.image) == expectedImages[receipt.image],
              try canSeedReviewedCopy(
                receipt.image, identity: receipt.identity, baseline: receipt.baseline)
            else {
              throw DecisionStoreError.fileChanged
            }
            try write(
              StoredDecision(
                decision: receipt.decision, pending: !receipt.complete, baseline: receipt.baseline,
                userModified: true),
              key: receipt.identity)
            try putTransferredEdit(edit, identity: receipt.identity)
            _ = try pathIdentity(receipt.image, update: receipt.identity)
            try putReceipt(receipt, plan: plan.id)
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

  /// A copied companion may have since acquired captions/develop settings. Never
  /// replace it with old source bytes once durable destination review state exists.
  public func hasReviewCopyReceipts(_ plan: ReviewedCopyPlan, family: ReviewCopyFamily) throws
    -> Bool
  {
    for image in family.images {
      let relative = image.source.pathComponents.dropFirst(plan.session.root.pathComponents.count)
        .joined(separator: "/")
      for root in [plan.primary, plan.backup] {
        let target = root.appendingPathComponent(relative)
        guard let receipt = try reviewReceipt(plan.id, target: target) else { return false }
        guard try key(for: target) == receipt.identity else { throw DecisionStoreError.fileChanged }
      }
    }
    return true
  }

  public func synchronizeReviewCopy(_ plan: ReviewedCopyPlan, family: ReviewCopyFamily) throws
    -> ReviewTransferStatus
  {
    var pendingImages: [URL] = []
    var preserved = 0
    for image in family.images {
      let relative = image.source.pathComponents.dropFirst(plan.session.root.pathComponents.count)
        .joined(separator: "/")
      for root in [plan.primary, plan.backup] {
        let target = root.appendingPathComponent(relative)
        guard var receipt = try reviewReceipt(plan.id, target: target),
          try key(for: target) == receipt.identity,
          var local = try read(receipt.identity)
        else { throw DecisionStoreError.fileChanged }
        if receipt.complete {
          let entry = try load(for: target)
          let data = try? sidecarData(target)
          if entry.status != "Saved" || (!receipt.fields.isEmpty && data == nil) {
            pendingImages.append(target)
          }
          if entry.decision != receipt.decision { preserved += 1 }
          continue
        }
        if local.decision != receipt.decision
          || (local.baseline != receipt.baseline && local.baseline != receipt.intendedDigest)
        {
          // A user/save/import has established newer destination intent. Preserve it.
          receipt.complete = true
          try putReceipt(receipt, plan: plan.id)
          preserved += 1
          if local.pending { pendingImages.append(target) }
          continue
        }
        var syncedDigest: String?
        do {
          try sourceProtection.withWritable([target, XMPSidecar.url(for: target)]) {
            var coordinationError: NSError?
            var operationError: (any Error)?
            NSFileCoordinator().coordinate(
              writingItemAt: XMPSidecar.url(for: target), options: .forMerging,
              error: &coordinationError
            ) { _ in
              do {
                guard try key(for: target) == receipt.identity else {
                  throw DecisionStoreError.fileChanged
                }
                let current = try sidecarData(target)
                let digest = XMPSidecar.digest(current)
                if digest == receipt.intendedDigest {
                  syncedDigest = digest  // crash after atomic replacement, before acknowledgement
                } else {
                  guard digest == receipt.baseline else { throw SidecarError.conflict }
                  let output = try XMPSidecar.merging(
                    receipt.decision, into: current, fields: receipt.fields)
                  guard XMPSidecar.digest(output) == receipt.intendedDigest else {
                    throw SidecarError.conflict
                  }
                  let sidecar = XMPSidecar.url(for: target)
                  try output.write(to: sidecar, options: .atomic)
                  let handle = try FileHandle(forWritingTo: sidecar)
                  try handle.synchronize()
                  try handle.close()
                  syncedDigest = receipt.intendedDigest
                }
              } catch { operationError = error }
            }
            if let coordinationError { throw coordinationError }
            if let operationError { throw operationError }
          }
        } catch DecisionStoreError.fileChanged { throw DecisionStoreError.fileChanged } catch {
          pendingImages.append(target)
          continue
        }
        guard let syncedDigest else {
          pendingImages.append(target)
          continue
        }
        local.pending = false
        local.baseline = syncedDigest
        try rebaseMetadata(identity: receipt.identity, from: receipt.baseline, to: syncedDigest)
        try write(local, key: receipt.identity)
        receipt.complete = true
        try putReceipt(receipt, plan: plan.id)
      }
    }
    return ReviewTransferStatus(
      pending: pendingImages.count, preserved: preserved, pendingImages: pendingImages)
  }
}
