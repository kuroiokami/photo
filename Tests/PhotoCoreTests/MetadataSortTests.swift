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
