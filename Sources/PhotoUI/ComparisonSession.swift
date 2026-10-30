import Foundation
import Observation
import PhotoCore
import PhotoImaging

enum ComparisonPane: Hashable {
  case reference, active
  var other: Self { self == .reference ? .active : .reference }
}
struct ComparisonRequest: Equatable {
  enum Action: Equatable {
    case fit
    case zoom(CGPoint, scale: Double = 1)
    case cameraPreview(CGPoint, scale: Double = 1)
    case pan(CGPoint)
  }
  let id = UUID()
  let action: Action
}

@MainActor @Observable
final class ComparisonChannel {
  var request: ComparisonRequest?
}

/// Routes intent between panes, never decoded images or echoed scroll results.
@MainActor @Observable
final class ComparisonSession {
  private(set) var reference: PhotoItem?
  private(set) var linked = true
  let activeChannel = ComparisonChannel()
  let referenceChannel = ComparisonChannel()
  func channel(for pane: ComparisonPane) -> ComparisonChannel {
    pane == .active ? activeChannel : referenceChannel
  }
  private struct Viewport {
    var zoom = false
    var source: DetailSource = .original
    var scale = 1.0
    var center = CGPoint(x: 0.5, y: 0.5)
  }
  @ObservationIgnored private var viewports: [ComparisonPane: Viewport] = [:]
  var enabled: Bool { reference != nil }
  func request(for pane: ComparisonPane) -> ComparisonRequest? { channel(for: pane).request }
  func toggleInspection() {
    let viewport = viewports[.active] ?? Viewport()
    let inspect = !viewport.zoom || viewport.source == .cameraPreview
    zoom(inspect, center: viewport.center, source: .original, from: .active)
    activeChannel.request = ComparisonRequest(action: inspect ? .zoom(viewport.center) : .fit)
  }
  func inspectCameraPreview() {
    let viewport = viewports[.active] ?? Viewport()
    zoom(true, center: viewport.center, source: .cameraPreview, from: .active)
    activeChannel.request = ComparisonRequest(action: .cameraPreview(viewport.center))
  }
  private func action(_ viewport: Viewport) -> ComparisonRequest.Action {
    guard viewport.zoom else { return .fit }
    return viewport.source == .cameraPreview
      ? .cameraPreview(viewport.center, scale: viewport.scale)
      : .zoom(viewport.center, scale: viewport.scale)
  }
  func pin(_ photo: PhotoItem) {
    reference = photo
    resetViewports()
  }
  func close() {
    reference = nil
    resetViewports()
  }
  func resetViewports() {
    viewports = [:]
    activeChannel.request = ComparisonRequest(action: .fit)
    referenceChannel.request = ComparisonRequest(action: .fit)
  }
  func setLinked(_ value: Bool) {
    linked = value
    guard value, enabled else { return }
    let active = viewports[.active] ?? Viewport()
    viewports[.reference] = active
    referenceChannel.request = ComparisonRequest(action: action(active))
  }
  func zoom(
    _ value: Bool, center: CGPoint, scale: Double = 1, source: DetailSource? = nil,
    from pane: ComparisonPane
  ) {
    let point = bounded(center)
    let chosen = source ?? viewports[pane]?.source ?? .original
    viewports[pane] = Viewport(
      zoom: value, source: chosen, scale: InspectionZoom.bounded(scale), center: point)
    guard enabled, linked else { return }
    viewports[pane.other] = Viewport(
      zoom: value, source: chosen, scale: InspectionZoom.bounded(scale), center: point)
    channel(for: pane.other).request = ComparisonRequest(
      action: action(viewports[pane.other]!))
  }
  func pan(_ point: CGPoint, from pane: ComparisonPane) {
    let point = bounded(point)
    viewports[pane, default: Viewport()].center = point
    guard enabled, linked else { return }
    viewports[pane.other, default: Viewport()].center = point
    channel(for: pane.other).request = ComparisonRequest(action: .pan(point))
  }
  private func bounded(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: point.x.isFinite ? min(1, max(0, point.x)) : 0.5,
      y: point.y.isFinite ? min(1, max(0, point.y)) : 0.5)
  }
}
