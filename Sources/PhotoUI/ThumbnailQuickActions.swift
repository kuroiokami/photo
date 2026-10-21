import SwiftUI

private typealias ThumbnailHover = SwiftUI.State<Bool>

enum ThumbnailAction {
  case rotateLeft, rotateRight, mirrorHorizontal, mirrorVertical, metadata, crop, preview
}

/// Keep hover state local to a tile so pointer movement does not invalidate the grid.
struct ThumbnailQuickActions<Content: View>: View {

  let filename: String
  let selected: Bool
  let canEdit: Bool
  let action: (ThumbnailAction) -> Void
  @ViewBuilder let content: () -> Content
  @ThumbnailHover private var hovered = false

  private var showsControls: Bool { hovered || selected }

  var body: some View {
    content()
      .overlay {
        if showsControls {
          controls
        }
      }
      .onHover { hovered = $0 }
  }

  private var controls: some View {
    VStack {
      HStack {
        control(
          "Rotate Left", symbol: "rotate.left", action: .rotateLeft,
          help: "Rotate this photo left ([), or the selected group if it is selected.")
        Spacer(minLength: 0)
        Menu {
          Button("Flip Left / Right") { action(.mirrorHorizontal) }
          Button("Flip Top / Bottom") { action(.mirrorVertical) }
        } label: {
          icon("arrow.left.and.right.righttriangle.left.righttriangle.right")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .frame(width: 24, height: 24)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel("Mirror \(filename)")
        .help("Mirror this photo, or the selected group if it is selected. Photo-only edits.")
        .disabled(!canEdit)
        Spacer(minLength: 0)
        control(
          "Rotate Right", symbol: "rotate.right", action: .rotateRight,
          help: "Rotate this photo right (]), or the selected group if it is selected.")
      }
      Spacer(minLength: 0)
      HStack {
        control(
          "Edit IPTC", symbol: "info.circle", action: .metadata,
          help:
            "Open IPTC and keywords for this photo, or the selected group if it is selected.")
        Spacer(minLength: 0)
        control(
          "Crop", symbol: "crop", action: .crop,
          help: "Crop this photo (⇧⌘C crops the current photo). Saved in Photo only.")
        Spacer(minLength: 0)
        control(
          "Open Preview", symbol: "magnifyingglass", action: .preview,
          help: "Open this photo in Preview. Space switches views; Z checks focus at 100%.")
      }
    }
    .padding(4)
  }

  private func control(_ title: String, symbol: String, action value: ThumbnailAction, help: String)
    -> some View
  {
    Button {
      action(value)
    } label: {
      icon(symbol)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(title) \(filename)")
    .help(help)
    .disabled(value != .preview && !canEdit)
  }

  private func icon(_ symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 24, height: 24)
      .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 5))
      .contentShape(Rectangle())
  }
}
