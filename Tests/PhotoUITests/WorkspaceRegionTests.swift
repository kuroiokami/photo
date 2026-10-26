import Observation
import PhotoCore
import SwiftUI
import Testing

@testable import PhotoUI

@MainActor @Observable
private final class RegionValues {
  var progress = 0
  var grid = 0
}
@MainActor
private final class RegionCounts {
  var header = 0
  var grid = 0
}
private struct RegionProbe: View {
  let values: RegionValues
  let counts: RegionCounts
  var body: some View {
    HStack {
      WorkspaceRegion {
        let value = values.progress
        let _ = { counts.header += 1 }()
        Text("Progress \(value)")
      }
      WorkspaceRegion {
        let value = values.grid
        let _ = { counts.grid += 1 }()
        Text("Grid \(value)")
      }
    }
  }
}
@MainActor
struct WorkspaceRegionTests {
  @Test func headerUpdatesStayLocalWhileGridStillObservesItsOwnChanges() async throws {
    let values = RegionValues()
    let counts = RegionCounts()
    let renderer = ImageRenderer(
      content: RegionProbe(values: values, counts: counts).frame(width: 200, height: 80))
    #expect(renderer.nsImage != nil)
    let header = counts.header
    let grid = counts.grid
    values.progress = 1
    for _ in 0..<20 {
      await Task.yield()
      _ = renderer.nsImage
      if counts.header > header { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(counts.header > header)
    #expect(counts.grid == grid)
    values.grid = 1
    for _ in 0..<20 {
      await Task.yield()
      _ = renderer.nsImage
      if counts.grid > grid { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(counts.grid > grid)
  }
}
