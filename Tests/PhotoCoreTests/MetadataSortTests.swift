import Foundation
import PhotoCore
import Testing

struct MetadataSortTests {
  @Test func numericOrderingMissingValuesAndNaturalTies() {
    let photos = ["10", "2", "1", "missing"].map {
      PhotoItem(id: $0, filename: "Photo\($0).jpg", resourceName: "")
    }
    var low = PhotoMetadata(pixelWidth: 1, pixelHeight: 1)
    low.iso = 100
    low.exposureTime = 1 / 1000
    var high = low
    high.iso = 800
    high.exposureTime = 1 / 60
    let metadata = ["10": low, "2": low, "1": high]
    #expect(
      PhotoSort.iso.ordered(photos, metadata: metadata).map(\.id) == ["2", "10", "1", "missing"])
    #expect(
      PhotoSort.exposureTime.ordered(photos, metadata: metadata).map(\.id) == [
        "2", "10", "1", "missing",
      ])
  }
  @Test func captureTimeUsesInstants() {
    var a = PhotoMetadata(pixelWidth: 1, pixelHeight: 1)
    var b = a
    a.captureTime = Date(timeIntervalSince1970: 200)
    b.captureTime = Date(timeIntervalSince1970: 100)
    let photos = [
      PhotoItem(id: "a", filename: "a", resourceName: ""),
      PhotoItem(id: "b", filename: "b", resourceName: ""),
    ]
    #expect(
      PhotoSort.captureTime.ordered(photos, metadata: ["a": a, "b": b]).map(\.id) == ["b", "a"])
  }
}

private actor DelayedMetadata: PhotoMetadataReading {
  private var pending: CheckedContinuation<PhotoMetadata, Never>?
  private var waiting: CheckedContinuation<Void, Never>?

  func metadata(for file: URL) async throws -> PhotoMetadata {
    await withCheckedContinuation { continuation in
      pending = continuation
      waiting?.resume()
      waiting = nil
    }
  }

  func waitForRead() async {
    if pending != nil { return }
    await withCheckedContinuation { waiting = $0 }
  }

  func finish() {
    var value = PhotoMetadata(pixelWidth: 100, pixelHeight: 100)
    value.iso = 800
    pending?.resume(returning: value)
    pending = nil
  }
}

@MainActor
struct MetadataSessionTests {
  @Test func navigationAndSessionSwitchRejectLateMetadata() async {
    let photos = (0..<10_000).map {
      PhotoItem(fileURL: URL(fileURLWithPath: "/benchmark/Photo\($0).ARW"))
    }
    let state = WorkspaceState(photos: photos)
    let reader = DelayedMetadata()
    let indexing = Task { await state.indexMetadata(using: reader) }
    await reader.waitForRead()
    state.select(photos.last?.id)
    #expect(state.selectedID == photos.last?.id)
    state.showSamples()
    let session = state.sessionID
    await reader.finish()
    await indexing.value
    #expect(state.sessionID == session)
    #expect(state.metadata.isEmpty)
    #expect(state.indexedCount == 0)
    #expect(!state.indexing)
    #expect(state.photos == SampleLibrary.photos)
  }
}
