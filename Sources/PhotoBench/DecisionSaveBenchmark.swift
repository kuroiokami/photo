import Foundation
import PhotoCore

/// Matched singleton/bounded saves using identical production code and generated
/// marker files. Measures durable saves/XMP, not image decoding or display frames.
struct DecisionSaveBenchmark {
  struct Measurement: Encodable {
    let iteration: Int
    let workflow: String
    let batchSize: Int
    let files: Int
    let milliseconds: Double
    let statistics: DecisionWriteStatistics
    let valuesCorrect: Bool
    let originalsUnchanged: Bool
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let measurements: [Measurement]
    let operatingSystem: String
    let logicalCPUCount: Int
    let physicalMemoryGiB: Double
    let notes: [String]
  }
  static func run() async throws -> Report {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent("photo-decision-bench-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var measurements: [Measurement] = []
    let modes: [(String, Int)] = [
      ("ordinary", 1), ("ordinary", 32), ("protected-review", 1), ("protected-review", 32),
    ]
    for iteration in 0..<3 {
      let ordered = iteration == 1 ? Array(modes.reversed()) : modes
      for (workflow, batchSize) in ordered {
        let base = root.appendingPathComponent("\(iteration)-\(workflow)-\(batchSize)")
        let folder = base.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let images = (0..<1000).map {
          folder.appendingPathComponent(String(format: "frame%04d.jpg", $0))
        }
        for (index, image) in images.enumerated() {
          try Data("benchmark original \(index)".utf8).write(to: image)
        }
        let policy = SourceProtection(
          registryURL: base.appendingPathComponent("state/protection.json"))
        let database = base.appendingPathComponent("state/decisions.sqlite")
        let store = DecisionStore(databaseURL: database, sourceProtection: policy)
        let review =
          workflow == "protected-review" ? try await store.beginSourceReview(folder) : nil
        let initial = try await store.loadImageStates(for: images)
        var identities: [String] = []
        for result in initial {
          guard let identity = try result.get().0.identity else {
            throw DecisionStoreError.fileChanged
          }
          identities.append(identity)
        }
        let decision = CullingDecision(rating: 4, flag: .pick)
        let ordinary = zip(images, identities).map {
          DecisionWrite(image: $0.0, decision: decision, expectedIdentity: $0.1)
        }
        let protected = zip(images, identities).map {
          SourceDecisionWrite(
            image: $0.0, identity: $0.1, decision: decision, reviewed: true, fields: .all)
        }
        var correct = true
        let start = ContinuousClock.now
        for offset in stride(from: 0, to: images.count, by: batchSize) {
          let end = min(offset + batchSize, images.count)
          let results: [Result<DecisionEntry, any Error>]
          if let review {
            results = try await store.saveSourceDecisions(
              Array(protected[offset..<end]), session: review)
          } else {
            results = try await store.saveDecisions(Array(ordinary[offset..<end]))
          }
          for result in results {
            let entry = try result.get()
            correct =
              correct && entry.decision == decision
              && (review == nil ? entry.status == "Saved" : entry.reviewed)
          }
          await Task.yield()
        }
        let duration = ContinuousClock.now - start
        let elapsed =
          Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds)
          / 1e15
        let statistics = await store.decisionWriteStatistics
        let reopened = DecisionStore(databaseURL: database, sourceProtection: policy)
        var unchanged = true
        for (index, image) in images.enumerated() {
          if try Data(contentsOf: image) != Data("benchmark original \(index)".utf8) {
            unchanged = false
          }
          let restored = try await reopened.load(for: image)
          if restored.decision != decision { correct = false }
          if review == nil {
            if try XMPSidecar.read(Data(contentsOf: XMPSidecar.url(for: image))) != decision {
              correct = false
            }
          } else if FileManager.default.fileExists(atPath: XMPSidecar.url(for: image).path) {
            unchanged = false
          }
        }
        guard correct, unchanged else {
          throw DecisionStoreError.database("Generated decision benchmark verification failed.")
        }
        measurements.append(
          Measurement(
            iteration: iteration, workflow: workflow, batchSize: batchSize, files: images.count,
            milliseconds: elapsed, statistics: statistics, valuesCorrect: correct,
            originalsUnchanged: unchanged))
      }
    }
    let info = ProcessInfo.processInfo
    return Report(
      measurements: measurements, operatingSystem: info.operatingSystemVersionString,
      logicalCPUCount: info.processorCount,
      physicalMemoryGiB: Double(info.physicalMemory) / pow(1024, 3),
      notes: [
        "Three matched iterations of 1,000 generated marker files per workflow/mode; order reverses in iteration two.",
        "Singleton and 32-file modes use the same final implementation and SQLite synchronous=FULL; this isolates batching rather than historical before/after code.",
        "Timing excludes fixture creation, schema/index seeds and verification; includes identity/protection checks, durable pending writes, atomic ordinary XMP publication, acknowledgements and yields.",
        "Protected review saves are local only; every original is byte-compared and every saved value is checked after reopening the store.",
        "Commit counters cover decision saves only. These are local-filesystem model timings, not camera-card latency, UI frame rates or a durability power-loss test.",
      ])
  }
}
