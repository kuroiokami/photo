import Darwin
import Foundation

/// A snapshot records exactly which journal prefix it already includes. Keeping
/// this cursor after compaction makes a crash before journal removal harmless.
struct IngestJournalCursor: Codable, Equatable, Sendable {
  let id: UUID
  let offset: UInt64
}
private struct IngestJournalHeader: Codable {
  let version: Int
  let id: UUID
}

enum IngestJournal {
  static func url(for manifest: URL) -> URL {
    manifest.deletingLastPathComponent().appendingPathComponent(".photo-ingest.events")
  }

  static func replay(_ snapshot: IngestManifest, at url: URL) throws -> IngestManifest {
    guard FileManager.default.fileExists(atPath: url.path) else { return snapshot }
    _ = try FileFingerprint.read(url)
    let data = try Data(contentsOf: url)
    var result = snapshot
    // No complete header means creation was interrupted before any record could
    // be acknowledged. Complete malformed headers/records fail closed.
    guard let headerEnd = data.firstIndex(of: 0x0A) else {
      result.journalCheckpoint = nil
      return result
    }
    guard headerEnd <= 1024 else { throw DecisionStoreError.fileChanged }
    let decoder = JSONDecoder()
    let header = try decoder.decode(IngestJournalHeader.self, from: data[..<headerEnd])
    guard header.version == 1 else {
      throw MediaOperationError.invalid("This copy record uses an unsupported version.")
    }
    let start = headerEnd + 1
    let checkpoint = snapshot.journalCheckpoint
    let covered = checkpoint.flatMap { $0.id == header.id ? $0.offset : nil } ?? UInt64(start)
    guard covered >= UInt64(start), covered <= data.count,
      data[Int(covered) - 1] == 0x0A
    else { throw DecisionStoreError.fileChanged }
    var offset = Int(covered)
    while offset < data.count, let end = data[offset...].firstIndex(of: 0x0A) {
      guard end - offset <= 1_048_576 else {
        throw MediaOperationError.invalid("A copy record is too large to read safely.")
      }
      let record = try decoder.decode(IngestRecord.self, from: data[offset..<end])
      result.records[record.relativePath] = record
      offset = end + 1
    }
    // An unterminated last record was never acknowledged. On retry the copied
    // bytes are verified again; only a new complete append can publish arrival.
    result.journalCheckpoint = IngestJournalCursor(id: header.id, offset: UInt64(offset))
    return result
  }
}

/// Confined to MediaOperations' one active operation. Each destination has one
/// open writer; no growing-manifest encoding, scanning or rewriting per file.
final class IngestJournalWriter {
  private let url: URL
  private let protection: SourceProtection
  private let handle: FileHandle
  private let fingerprint: FileFingerprint
  private let encoder = JSONEncoder()
  private(set) var cursor: IngestJournalCursor

  init(manifest: URL, protection: SourceProtection) throws {
    let journalURL = IngestJournal.url(for: manifest)
    url = journalURL
    self.protection = protection
    let id = UUID()
    var header = try JSONEncoder().encode(IngestJournalHeader(version: 1, id: id))
    header.append(0x0A)
    try protection.withWritable([journalURL]) {
      try header.write(to: journalURL, options: .withoutOverwriting)
    }
    fingerprint = try FileFingerprint.read(url)
    let descriptor = Darwin.open(url.path, O_WRONLY | O_APPEND | O_NOFOLLOW)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    cursor = IngestJournalCursor(id: id, offset: UInt64(header.count))
  }

  func append(_ record: IngestRecord) throws -> IngestJournalCursor {
    var data = try encoder.encode(record)
    guard data.count <= 1_048_576 else {
      throw MediaOperationError.invalid("A copy record is too large to save safely.")
    }
    data.append(0x0A)
    try protection.withWritable([url]) {
      let current = try FileFingerprint.read(url)
      guard current.device == fingerprint.device, current.inode == fingerprint.inode,
        current.size == cursor.offset
      else { throw DecisionStoreError.fileChanged }
      try handle.write(contentsOf: data)
      try handle.synchronize()
      try MediaOperations.syncDirectory(url.deletingLastPathComponent())
    }
    cursor = IngestJournalCursor(id: cursor.id, offset: cursor.offset + UInt64(data.count))
    return cursor
  }
}

extension MediaOperations {
  /// Snapshot first, journal removal second. If interrupted between them, replay
  /// skips the covered prefix instead of restoring obsolete rename mappings.
  func checkpointManifest(_ manifest: IngestManifest, at url: URL) throws {
    let events = IngestJournal.url(for: url)
    if FileManager.default.fileExists(atPath: events.path) {
      let current = try IngestJournal.replay(IngestManifest(), at: events)
      guard current.journalCheckpoint == manifest.journalCheckpoint else {
        throw DecisionStoreError.fileChanged
      }
    }
    try durableJSON(manifest, at: url)
    try sourceProtection.withWritable([events]) {
      if FileManager.default.fileExists(atPath: events.path) {
        _ = try FileFingerprint.read(events)
        try FileManager.default.removeItem(at: events)
        try Self.syncDirectory(events.deletingLastPathComponent())
      }
    }
  }
}
