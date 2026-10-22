import Foundation
import PhotoCore

/// Filesystem payload accounting, not physical device I/O. Polling attributes
/// adds identical callback overhead to the old/new ingest implementations.
private actor IngestWriteProbe {
  private var snapshots: [URL: String] = [:]
  private(set) var snapshotPublications = 0
  private(set) var snapshotPayloadBytes = 0
  private(set) var journalPayloadBytes = 0
  private var journalSizes: [URL: Int] = [:]
  private(set) var arrivals = 0

  func observe(_ roots: [URL], arrivalCount: Int = 0) throws {
    arrivals += arrivalCount
    for root in roots {
      let snapshot = root.appendingPathComponent(".photo-ingest.json")
      let a = try FileManager.default.attributesOfItem(atPath: snapshot.path)
      let stamp = "\(a[.systemFileNumber] ?? ""):\(a[.modificationDate] ?? ""):\(a[.size] ?? "")"
      if snapshots[snapshot] != stamp {
        snapshots[snapshot] = stamp
        snapshotPublications += 1
        snapshotPayloadBytes += (a[.size] as? NSNumber)?.intValue ?? 0
      }
      let events = root.appendingPathComponent(".photo-ingest.events")
      if let b = try? FileManager.default.attributesOfItem(atPath: events.path),
        let size = (b[.size] as? NSNumber)?.intValue
      {
        let previous = journalSizes[events] ?? 0
        journalPayloadBytes += max(0, size - previous)
        journalSizes[events] = size
      }
    }
  }
}

struct IngestJournalBenchmark {
  struct Sample: Codable {
    let files: Int
    let elapsedMilliseconds: Double
    let snapshotPublications: Int
    let snapshotPayloadBytes: Int
    let journalPayloadBytes: Int
    let originalsAndBothCopiesMatch: Bool
    let arrivals: Int
    let resumeAlreadyVerified: Int
    let resumeMilliseconds: Double
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let samples: [Sample]
    let notes: [String]
  }
  static func run() async throws -> Report {
    var samples: [Sample] = []
    for count in [100, 1000] {
      let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("photo-ingest-bench-" + UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let source = root.appendingPathComponent("card")
      let primary = root.appendingPathComponent("primary")
      let backup = root.appendingPathComponent("backup")
      try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
      // Tiny synthetic payloads isolate bookkeeping; these are not decodable
      // photos and are not used for imaging/RAW performance claims.
      let payload = Data(repeating: 0x5A, count: 4096)
      for index in 0..<count {
        try payload.write(to: source.appendingPathComponent(String(format: "photo%05d.jpg", index)))
      }
      let operations = MediaOperations()
      let probe = IngestWriteProbe()
      let start = ContinuousClock.now
      let result = try await operations.ingest(source: source, primary: primary, backup: backup) {
        item in
        do {
          try await probe.observe([primary, backup], arrivalCount: item.verifiedImages.count)
        } catch { preconditionFailure("Disposable benchmark accounting failed: \(error)") }
      }
      let elapsed = milliseconds(start.duration(to: .now))
      try await probe.observe([primary, backup])
      var matches = result.copiedCount == count * 2
      for index in 0..<count {
        let name = String(format: "photo%05d.jpg", index)
        for folder in [source, primary, backup] {
          if try Data(contentsOf: folder.appendingPathComponent(name)) != payload {
            matches = false
          }
        }
      }
      let resumeStart = ContinuousClock.now
      let resumed = try await operations.ingest(source: source, primary: primary, backup: backup)
      let resume = milliseconds(resumeStart.duration(to: .now))
      samples.append(
        await Sample(
          files: count, elapsedMilliseconds: elapsed,
          snapshotPublications: probe.snapshotPublications,
          snapshotPayloadBytes: probe.snapshotPayloadBytes,
          journalPayloadBytes: probe.journalPayloadBytes,
          originalsAndBothCopiesMatch: matches, arrivals: probe.arrivals,
          resumeAlreadyVerified: resumed.alreadyVerifiedCount, resumeMilliseconds: resume))
    }
    return Report(
      samples: samples,
      notes: [
        "100/1000 synthetic 4 KiB marker files, two disposable destinations on one local volume; no image decoding.",
        "Snapshot payload bytes count observed atomic snapshot publications; journal bytes count appended file growth, including headers.",
        "These are encoded filesystem payloads, not physical I/O bytes/fsync latency, RAW throughput, native UI responsiveness or physical-card acceptance.",
        "Attribute polling runs in progress callbacks; OS caches are uncontrolled. Source/copy verification and resume are checked separately from timing.",
      ])
  }
  private static func milliseconds(_ value: Duration) -> Double {
    Double(value.components.seconds) * 1000 + Double(value.components.attoseconds) / 1e15
  }
}
