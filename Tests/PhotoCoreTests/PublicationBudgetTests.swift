import Foundation
import Testing

@testable import PhotoCore

private struct BudgetMetadataReader: PhotoMetadataReading {
  func metadata(for file: URL) async throws -> PhotoMetadata {
    PhotoMetadata(pixelWidth: 100, pixelHeight: 80)
  }
}
struct PublicationBudgetTests {
  @Test func overshootsReduceWorkAndSustainedHeadroomRecoversSlowly() {
    var budget = PublicationBudget()
    #expect(budget.limit == 16)
    for expected in [8, 4, 2, 1, 1] {
      budget.record(milliseconds: 5)
      #expect(budget.limit == expected)
    }
    for _ in 0..<3 { budget.record(milliseconds: 0.1) }
    #expect(budget.limit == 1)
    budget.record(milliseconds: 0.1)
    #expect(budget.limit == 2)
    for _ in 0..<100 { budget.record(milliseconds: 0.1) }
    #expect(budget.limit == 16)
  }
  @MainActor @Test func indexingDrainsBoundedPublicationsBeforeFinalOrdering() async {
    let photos = (0..<257).map { PhotoItem(fileURL: URL(fileURLWithPath: "/budget/\($0).jpg")) }
    let state = WorkspaceState(photos: photos)
    await state.indexMetadata(using: BudgetMetadataReader())
    #expect(state.metadata.count == 257 && state.indexedCount == 257 && !state.indexing)
    #expect(state.publicationMetrics.metadataWork.maximumItems <= 16)
    #expect(state.publicationMetrics.metadata > 16)
  }
  @MainActor @Test func decisionIndexPublishesBoundedCompleteResultsWithoutSidecars() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let photosFolder = root.appendingPathComponent("photos")
    try FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)
    let images = (0..<257).map { photosFolder.appendingPathComponent("\($0).jpg") }
    for image in images { try Data("original".utf8).write(to: image) }
    let policy = SourceProtection(registryURL: root.appendingPathComponent("state/protection.json"))
    let store = DecisionStore(
      databaseURL: root.appendingPathComponent("state/decisions.sqlite"), sourceProtection: policy)
    let state = WorkspaceState(photos: images.map(PhotoItem.init(fileURL:)), decisionStore: store)
    await state.loadDecisions()
    #expect(state.decisionsReady.count == 257 && !state.decisionsLoading)
    #expect(state.publicationMetrics.decisionWork.maximumItems <= 16)
    #expect(state.decisionSelectionReady && state.photos.count == 257)
    for image in images {
      #expect(try Data(contentsOf: image) == Data("original".utf8))
      #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: image).path))
    }
  }

}
