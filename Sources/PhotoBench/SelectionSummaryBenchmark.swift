import Foundation
import PhotoCore

/// Identical public workspace operations can run on the baseline revision.
struct SelectionSummaryBenchmark {
  struct Sample: Encodable {
    let photos: Int
    let queries: Int
    let initializationMilliseconds: Double
    let loadingMilliseconds: Double
    let selectionMilliseconds: Double
    let queryMilliseconds: Double
    let correct: Bool
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let samples: [Sample]
    let notes = [
      "Synthetic in-memory sample items, no image decoding, filesystem, sidecars or personal database writes.",
      "Initialization includes native filename ranks and family/display model setup; decision loading uses the unchanged sample path.",
      "Query timing includes 2000 selection summary and readiness reads; selection construction is timed separately.",
      "Model timings do not measure SwiftUI body evaluations, displayed frame rate or physical-trackpad smoothness.",
      "Additional per-photo observable objects trade memory/initialization work for narrower UI dependencies; representative 40k-shoot RSS acceptance remains open.",
    ]
  }
  @MainActor static func run() async -> Report {
    var samples: [Sample] = []
    for count in [10_000, 40_000] {
      let photos = (0..<count).map {
        PhotoItem(id: String($0), filename: "Frame\($0).jpg", resourceName: "")
      }
      let start = ContinuousClock.now
      let state = WorkspaceState(photos: photos)
      let initialization = elapsed(start)
      let loadingStart = ContinuousClock.now
      await state.loadDecisions()
      let loading = elapsed(loadingStart)
      let selectionStart = ContinuousClock.now
      state.selectAllVisible()
      let selection = elapsed(selectionStart)
      let queryStart = ContinuousClock.now
      var correct = true
      for _ in 0..<2000 {
        let summary = state.selectionSummary
        correct =
          correct && summary.fileCount == count && summary.rating == 0
          && summary.flag == .unflagged && state.decisionSelectionReady
      }
      samples.append(
        Sample(
          photos: count, queries: 2000, initializationMilliseconds: initialization,
          loadingMilliseconds: loading, selectionMilliseconds: selection,
          queryMilliseconds: elapsed(queryStart), correct: correct))
    }
    return Report(samples: samples)
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    return Double(duration.components.seconds) * 1000
      + Double(duration.components.attoseconds) / 1e15
  }
}
