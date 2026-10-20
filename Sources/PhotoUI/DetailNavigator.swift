import SwiftUI

struct DetailPanActions {
  let pan: @MainActor (CGFloat, CGFloat) -> Void
  let jump: @MainActor (CGPoint) -> Void
}
private struct DetailPanKey: FocusedValueKey {
  typealias Value = DetailPanActions
}
extension FocusedValues {
  var detailPan: DetailPanActions? {
    get { self[DetailPanKey.self] }
    set { self[DetailPanKey.self] = newValue }
  }
}
private typealias NavigatorOffset = SwiftUI.State<CGPoint?>
private typealias NavigatorFocus = SwiftUI.FocusState<Bool>

struct DetailNavigator: View {
  let image: CGImage
  let imageSize: CGSize
  let visible: CGRect
  let navigate: @MainActor (CGPoint) -> Void
  @NavigatorOffset private var grabOffset: CGPoint?
  @NavigatorFocus private var focused: Bool

  var body: some View {
    let size = NavigatorGeometry.thumbnailSize(image: imageSize)
    let rectangle = CGRect(
      x: visible.minX * size.width, y: visible.minY * size.height,
      width: visible.width * size.width, height: visible.height * size.height)
    ZStack(alignment: .topLeading) {
      Image(decorative: image, scale: 1).resizable()
      Path { path in
        path.addRect(CGRect(origin: .zero, size: size))
        path.addRect(rectangle)
      }.fill(.black.opacity(0.35), style: FillStyle(eoFill: true))
      Rectangle().stroke(.white, lineWidth: 2)
        .shadow(color: .black, radius: 1)
        .frame(width: rectangle.width, height: rectangle.height)
        .offset(x: rectangle.minX, y: rectangle.minY)
    }
    .frame(width: size.width, height: size.height)
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          focused = true
          if grabOffset == nil {
            grabOffset =
              rectangle.contains(value.startLocation)
              ? CGPoint(
                x: value.startLocation.x - rectangle.midX, y: value.startLocation.y - rectangle.midY
              ) : .zero
          }
          navigate(
            NavigatorGeometry.target(
              location: value.location, thumbnail: size,
              offset: grabOffset ?? .zero, visible: visible.size))
        }.onEnded { _ in grabOffset = nil }
    )
    .focusable().focused($focused).focusEffectDisabled()
    .focusedValue(\.detailPan, DetailPanActions(pan: pan, jump: navigate))
    .padding(5)
    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6).stroke(
        focused ? Color.accentColor : Color.gray, lineWidth: focused ? 2 : 1)
    )
    .padding(12)
    .help(
      "Click to center the zoomed view. Drag the white frame to pan. When focused, arrow keys pan; Shift moves farther. Home/End jump to opposite corners."
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Zoom navigator")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { navigate(CGPoint(x: 0.5, y: 0.5)) }
    .accessibilityValue(
      "Horizontal \(Int(visible.midX * 100)) percent, vertical \(Int(visible.midY * 100)) percent"
    )
    .accessibilityAction(named: Text("Center image")) { navigate(CGPoint(x: 0.5, y: 0.5)) }
    .accessibilityAction(named: Text("Pan left")) { pan(-0.25, 0) }
    .accessibilityAction(named: Text("Pan right")) { pan(0.25, 0) }
    .accessibilityAction(named: Text("Pan up")) { pan(0, -0.25) }
    .accessibilityAction(named: Text("Pan down")) { pan(0, 0.25) }
  }
  private func pan(_ x: CGFloat, _ y: CGFloat) {
    navigate(
      NavigatorGeometry.center(
        CGPoint(
          x: visible.midX + visible.width * x,
          y: visible.midY + visible.height * y), visible: visible.size))
  }
}
