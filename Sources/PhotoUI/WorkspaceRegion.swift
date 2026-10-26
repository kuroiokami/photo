import SwiftUI

/// Evaluate observed content in its own body. Header/progress, selected preview
/// and saving-status dependencies must not invalidate the collection's parent.
struct WorkspaceRegion<Content: View>: View {
  @ViewBuilder let content: () -> Content
  var body: some View { content() }
}
