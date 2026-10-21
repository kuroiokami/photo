import CSQLite
import Foundation

public struct MetadataEntry: Sendable {
  public let value: DescriptiveMetadata
  public let identity: String
  public let baseline: String
  public let status: String
}
public struct MetadataFilePlan: Codable, Sendable, Identifiable {
  public var id: String { image.path }
  public let image: URL
  public let identity: String
  public let baseline: String
  public let before: DescriptiveMetadata
  public let after: DescriptiveMetadata
  public let fields: Set<MetadataField>
  public let changesKeywords: Bool
  public let embedded: Data?
}
struct StoredMetadata: Codable {
  var value: DescriptiveMetadata
  var baseline: String
  var pending: Bool
  var fields: Set<MetadataField>
  var changesKeywords: Bool
  var embedded: Data? = nil
}

extension DecisionStore {
  public func loadMetadata(for image: URL, embedded: Data? = nil) throws -> MetadataEntry {
    let decision = try load(for: image)
    let identity = try key(for: image)
    let local = try metadataRecord(identity)
    do {
      let data = try sidecarData(image)
      let baseline = XMPSidecar.digest(data)
      if var local, local.pending {
        if data != nil, !local.baseline.hasPrefix("replacement:"),
          let external = try? XMPSidecar.combinedDescriptive(
            sidecar: data, embedded: embedded ?? local.embedded),
          local.fields.allSatisfy({ (external.fields[$0] ?? "") == (local.value.fields[$0] ?? "") }
          ),
          !local.changesKeywords
            || (external.keywords == local.value.keywords
              && external.hierarchy == local.value.hierarchy)
        {
          local.pending = false
          local.baseline = baseline
          try putMetadata(local, identity: identity)
          return MetadataEntry(
            value: local.value, identity: identity, baseline: baseline, status: "Saved")
        }
        return MetadataEntry(
          value: local.value, identity: identity, baseline: local.baseline,
          status: local.baseline == baseline
            ? "Saved locally · metadata XMP pending" : "XMP conflict")
      }
      if decision.status.hasPrefix("XMP conflict · image replaced") {
        return MetadataEntry(
          value: DescriptiveMetadata(), identity: identity, baseline: "replacement:" + baseline,
          status: decision.status)
      }
      let value = try XMPSidecar.combinedDescriptive(
        sidecar: data, embedded: embedded ?? local?.embedded)
      try putMetadata(
        StoredMetadata(
          value: value, baseline: baseline, pending: false, fields: [], changesKeywords: false,
          embedded: embedded ?? local?.embedded),
        identity: identity)
      return MetadataEntry(value: value, identity: identity, baseline: baseline, status: "Saved")
    } catch {
      if let local {
        return MetadataEntry(
          value: local.value, identity: identity, baseline: local.baseline,
          status: "Saved locally · \(error.localizedDescription)")
      }
      throw error
    }
  }

  public func prepareMetadata(_ patch: MetadataPatch, images: [URL], embedded: [String: Data] = [:])
    throws -> [MetadataFilePlan]
  {
    try images.map { image in
      let entry = try loadMetadata(for: image, embedded: embedded[image.path])
      return MetadataFilePlan(
        image: image, identity: entry.identity, baseline: entry.baseline,
        before: entry.value, after: try patch.applying(to: entry.value),
        fields: Set(patch.fields.keys), changesKeywords: patch.keywordAction != .leave,
        embedded: embedded[image.path])
    }
  }

  public func saveMetadata(_ plan: MetadataFilePlan) throws -> MetadataEntry {
    return try sourceProtection.withWritable([plan.image, XMPSidecar.url(for: plan.image)]) {
      guard try key(for: plan.image) == plan.identity else { throw DecisionStoreError.fileChanged }
      let previous = try metadataRecord(plan.identity)
      let pending = previous?.pending == true
      let record = StoredMetadata(
        value: plan.after, baseline: plan.baseline, pending: true,
        fields: pending ? plan.fields.union(previous?.fields ?? []) : plan.fields,
        changesKeywords: plan.changesKeywords || (pending && previous?.changesKeywords == true),
        embedded: plan.embedded ?? previous?.embedded)
      try putMetadata(record, identity: plan.identity)
      return try syncMetadata(record, image: plan.image, identity: plan.identity, useLocal: false)

    }
  }

  public func retryMetadata(for image: URL, useLocal: Bool = false) throws -> MetadataEntry {
    return try sourceProtection.withWritable([image, XMPSidecar.url(for: image)]) {
      let identity = try key(for: image)
      guard let record = try metadataRecord(identity) else { return try loadMetadata(for: image) }
      return try syncMetadata(record, image: image, identity: identity, useLocal: useLocal)

    }
  }

  public func useExternalMetadata(for image: URL) throws -> MetadataEntry {
    return try sourceProtection.withWritable([image]) {
      let identity = try key(for: image)
      let data = try sidecarData(image)
      let embedded = try metadataRecord(identity)?.embedded
      let value = try XMPSidecar.combinedDescriptive(sidecar: data, embedded: embedded)
      let baseline = XMPSidecar.digest(data)
      try putMetadata(
        StoredMetadata(
          value: value, baseline: baseline, pending: false, fields: [], changesKeywords: false,
          embedded: embedded),
        identity: identity)
      return MetadataEntry(value: value, identity: identity, baseline: baseline, status: "Saved")

    }
  }

  func syncMetadata(
    _ original: StoredMetadata, image: URL, identity: String, useLocal: Bool
  ) throws -> MetadataEntry {
    return try sourceProtection.withWritable([image, XMPSidecar.url(for: image)]) {
      var record = original
      do {
        var failure: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
          writingItemAt: XMPSidecar.url(for: image), options: .forMerging, error: &coordinationError
        ) { _ in
          do {
            guard try key(for: image) == identity else { throw DecisionStoreError.fileChanged }
            let data = try sidecarData(image)
            let old = XMPSidecar.digest(data)
            guard useLocal || old == record.baseline else { throw SidecarError.conflict }
            let output = try XMPSidecar.mergingMetadata(
              record.value, fields: record.fields, keywords: record.changesKeywords,
              into: data ?? record.embedded)
            try output.write(to: XMPSidecar.url(for: image), options: .atomic)
            let new = XMPSidecar.digest(output)
            if var decision = try read(identity), decision.baseline == old {
              decision.baseline = new
              try write(decision, key: identity)
            }
            record.baseline = new
          } catch { failure = error }
        }
        if let error = coordinationError { throw error }
        if let error = failure { throw error }
        record.pending = false
        try putMetadata(record, identity: identity)
        return MetadataEntry(
          value: record.value, identity: identity, baseline: record.baseline, status: "Saved")
      } catch {
        return MetadataEntry(
          value: record.value, identity: identity, baseline: record.baseline,
          status: error is SidecarError && (error as? SidecarError) == .conflict
            ? "XMP conflict" : "Saved locally · \(error.localizedDescription)")
      }

    }
  }

  func rebaseMetadata(identity: String, from old: String, to new: String) throws {
    if var record = try metadataRecord(identity), record.baseline == old {
      record.baseline = new
      try putMetadata(record, identity: identity)
    }
  }

  func metadataRecord(_ identity: String) throws -> StoredMetadata? {
    try withDB { db in
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          db, "SELECT payload FROM descriptive WHERE identity=?", -1, &statement, nil) == SQLITE_OK,
        let statement
      else { throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db))) }
      defer { sqlite3_finalize(statement) }
      sqlite3_bind_text(
        statement, 1, identity, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return nil }
      guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
        throw DecisionStoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      return try recordDecoder.decode(
        StoredMetadata.self,
        from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }
  }
  func putMetadata(_ value: StoredMetadata, identity: String) throws {
    let data = try recordEncoder.encode(value)
    try withDB { db in
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          db, "INSERT OR REPLACE INTO descriptive(identity,payload) VALUES(?,?)", -1, &statement,
          nil) == SQLITE_OK, let statement
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
}
