import Foundation
import PhotoCore

/// Uses the public culling/review database paths, including file-identity and
/// protection checks. Generated marker files are never decoded as pixels.
struct SQLiteStatementBenchmark {
  struct Report: Encodable {
    let schemaVersion = 1
    let filesPerWorkflow = 1000
    let readsPerWorkflow = 10000
    let ordinaryColdIndexMilliseconds: Double
    let ordinaryWarmReadMilliseconds: Double
    let reviewColdIndexMilliseconds: Double
    let reviewWarmReadMilliseconds: Double
    let valuesCorrect: Bool
    let originalsUnchanged: Bool
    let notes: [String]
  }
  static func run() async throws -> Report {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent("photo-sqlite-bench-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library")
    let card = root.appendingPathComponent("card")
    var normalImages: [URL] = []
    var reviewImages: [URL] = []
    for folder in [library, card] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for i in 0..<1000 {
        let file = folder.appendingPathComponent(String(format: "frame%04d.jpg", i))
        try Data("synthetic row \(i)".utf8).write(to: file)
        if folder == library { normalImages.append(file) } else { reviewImages.append(file) }
      }
    }
    let protection = SourceProtection(
      registryURL: root.appendingPathComponent("state/protection.json"))
    let ordinary = DecisionStore(
      databaseURL: root.appendingPathComponent("state/ordinary.sqlite"),
      sourceProtection: protection)
    let normalStart = ContinuousClock.now
    let initial = try await ordinary.loadImageStates(for: normalImages)
    let normalCold = elapsed(normalStart)
    for result in initial { _ = try result.get() }
    var correct = initial.count == 1000
    let readsStart = ContinuousClock.now
    for _ in 0..<10 {
      for image in normalImages {
        let value = try await ordinary.loadImageState(for: image)
        correct = correct && value.0.decision == CullingDecision() && value.1 == PhotoEdit()
      }
    }
    let normalWarm = elapsed(readsStart)
    let reviewed = DecisionStore(
      databaseURL: root.appendingPathComponent("state/review.sqlite"), sourceProtection: protection)
    let session = try await reviewed.beginSourceReview(card)
    let reviewStart = ContinuousClock.now
    for image in reviewImages { _ = try await reviewed.loadSourceReview(session, image: image) }
    let reviewCold = elapsed(reviewStart)
    let reviewReadsStart = ContinuousClock.now
    for _ in 0..<10 {
      for image in reviewImages {
        let value = try await reviewed.loadSourceReview(session, image: image)
        correct =
          correct && value.0.decision == CullingDecision() && !value.0.reviewed
          && value.1 == PhotoEdit()
      }
    }
    let reviewWarm = elapsed(reviewReadsStart)
    var unchanged = true
    for images in [normalImages, reviewImages] {
      for (i, image) in images.enumerated() {
        if try Data(contentsOf: image) != Data("synthetic row \(i)".utf8) { unchanged = false }
        if FileManager.default.fileExists(atPath: XMPSidecar.url(for: image).path) {
          unchanged = false
        }
      }
    }
    return Report(
      ordinaryColdIndexMilliseconds: normalCold, ordinaryWarmReadMilliseconds: normalWarm,
      reviewColdIndexMilliseconds: reviewCold, reviewWarmReadMilliseconds: reviewWarm,
      valuesCorrect: correct, originalsUnchanged: unchanged,
      notes: [
        "1000 synthetic marker files per workflow, 10000 warm image-state/review reads; no pixel decoding or personal libraries.",
        "Ordinary cold indexing retains 16-file transactions; protected review discovery retains existing per-row durability. Warm reads include normal filesystem identity/protection checks.",
        "Fresh disposable databases per run; generation and final byte/sidecar checks are outside timing. OS caches are uncontrolled.",
        "These are service timings, not UI frame rates, RAW decoder speed or select-all decision-save batching.",
      ])
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let value = start.duration(to: .now)
    return Double(value.components.seconds) * 1000 + Double(value.components.attoseconds) / 1e15
  }
}
