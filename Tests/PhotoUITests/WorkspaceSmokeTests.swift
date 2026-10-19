import AppKit
import PhotoCore
import PhotoUI
import SwiftUI
import Testing

@MainActor
struct WorkspaceSmokeTests {
  @Test func bundledFixturesDecode() throws {
    for photo in SampleLibrary.photos {
      let image = try #require(SampleResources.image(for: photo))
      #expect(image.size.width == 640)
      #expect(image.size.height == 400)
    }
  }

  @Test func workspaceRendersWithSamplesAndEmptyState() throws {
    for photos in [SampleLibrary.photos, []] {
      let view = WorkspaceView(workspace: WorkspaceState(photos: photos))
        .frame(width: 1100, height: 760)
      let renderer = ImageRenderer(content: view)
      renderer.proposedSize = ProposedViewSize(width: 1100, height: 760)
      let image = try #require(renderer.nsImage)
      #expect(image.size.width == 1100)
      #expect(image.size.height == 760)
    }
  }
}
