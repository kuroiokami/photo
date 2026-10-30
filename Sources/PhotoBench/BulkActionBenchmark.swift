import Foundation
import PhotoCore

struct BulkActionBenchmark {
  struct Sample: Encodable {
    let photos: Int
    let unicode: Bool
    let selectAllMilliseconds: Double
    let flagMilliseconds: Double
    let undoFlagMilliseconds: Double
    let redoFlagMilliseconds: Double
    let ratingMilliseconds: Double
    let undoRatingMilliseconds: Double
    let redoRatingMilliseconds: Double
    let correct: Bool
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let samples: [Sample]
    let notes = [
      "Synthetic in-memory sample IDs; no image decoding or photo/sidecar/database-record writes.",
      "Identical public workspace actions, varied initial 0–5 stars, full selection and Rating order. Timings cover synchronous model/UI-actor work, not persistence completion or displayed frames.",
      "Selection includes the first summary query. Each action checks focus, independent values and history outside the timed region.",
      "10k/40k are generated stress controls, not representative camera/media, memory-pressure, physical gesture or long-session acceptance.",
    ]
  }
  @MainActor static func run() async -> Report {
    var samples: [Sample] = []
    for unicode in [false, true] {
      for count in [10_000, 40_000] {
        let photos = (0..<count).map { i in
          let n = i * 7919 % count
          let name = (unicode ? "cafe\u{301}-日本語-📷-" : "Frame-") + String(n)
          return PhotoItem(id: name, filename: name + ".jpg", resourceName: "")
        }
        let state = WorkspaceState(photos: photos)
        await state.loadDecisions()
        for rating in 1...5 {
          let ids = Set(
            photos.enumerated().filter { $0.offset % 6 == rating }.map { $0.element.id })
          state.selectGroup(ids)
          state.applyDecision(rating: rating, allowAutoAdvance: false)
        }
        await state.setSort(.rating)
        let initialRatings = state.decisions.mapValues(\.rating)
        let start = ContinuousClock.now
        state.selectAllVisible()
        var correct =
          state.selectionSummary.fileCount == count && state.selectionSummary.rating == nil
        let selection = elapsed(start)
        let focus = state.selectedID
        let flag = measure { state.applyDecision(flag: .pick, allowAutoAdvance: false) }
        correct =
          correct && state.decisions.values.allSatisfy { $0.flag == .pick }
          && state.decisions.mapValues(\.rating) == initialRatings && state.selectedID == focus
        let undoFlag = measure { state.undoDecision() }
        correct =
          correct && state.decisions.values.allSatisfy { $0.flag == .unflagged }
          && state.decisions.mapValues(\.rating) == initialRatings && state.selectedID == focus
        let redoFlag = measure { state.redoDecision() }
        correct =
          correct && state.decisions.values.allSatisfy { $0.flag == .pick }
          && state.decisions.mapValues(\.rating) == initialRatings && state.selectedID == focus
        let rating = measure { state.applyDecision(rating: 3, allowAutoAdvance: false) }
        correct =
          correct && state.selectionSummary.rating == 3
          && state.decisions.values.allSatisfy { $0.rating == 3 && $0.flag == .pick }
          && state.selectedID == focus
        let undoRating = measure { state.undoDecision() }
        correct =
          correct && state.decisions.mapValues(\.rating) == initialRatings
          && state.decisions.values.allSatisfy { $0.flag == .pick } && state.selectedID == focus
        let redoRating = measure { state.redoDecision() }
        correct =
          correct && state.decisions.values.allSatisfy { $0.rating == 3 && $0.flag == .pick }
          && state.selectedID == focus && state.selectedIDs.count == count
        samples.append(
          Sample(
            photos: count, unicode: unicode, selectAllMilliseconds: selection,
            flagMilliseconds: flag, undoFlagMilliseconds: undoFlag, redoFlagMilliseconds: redoFlag,
            ratingMilliseconds: rating, undoRatingMilliseconds: undoRating,
            redoRatingMilliseconds: redoRating, correct: correct))
      }
    }
    return Report(samples: samples)
  }
  @MainActor private static func measure(_ action: () -> Void) -> Double {
    let start = ContinuousClock.now
    action()
    return elapsed(start)
  }
  private static func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let d = start.duration(to: .now)
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
  }
}
