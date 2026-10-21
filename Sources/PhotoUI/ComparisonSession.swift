import Foundation
import Observation
import PhotoCore

enum ComparisonPane: Hashable {
  case reference, active
  var other: Self { self == .reference ? .active : .reference }
}
struct ComparisonRequest: Equatable {
  enum Action: Equatable {
    case fit
    case zoom(CGPoint, scale: Double = 1)
    case pan(CGPoint)
  }
  let id = UUID()
  let action: Action
}

/// Routes intent between panes, never decoded images or echoed scroll results.
@MainActor @Observable
final class ComparisonSession {
  private(set) var reference: PhotoItem?
  private(set) var linked = true
  private var requests: [ComparisonPane: ComparisonRequest] = [:]
  private struct Viewport {
    var zoom = false
    var scale = 1.0
    var center = CGPoint(x: 0.5, y: 0.5)
  }
  private var viewports: [ComparisonPane: Viewport] = [:]
  var enabled: Bool { reference != nil }
  func request(for pane: ComparisonPane) -> ComparisonRequest? { requests[pane] }
  func toggleInspection() {
    let viewport = viewports[.active] ?? Viewport()
    zoom(!viewport.zoom, center: viewport.center, from: .active)
    requests[.active] = ComparisonRequest(
      action: viewport.zoom ? .fit : .zoom(viewport.center))
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
    requests = [
      .active: ComparisonRequest(action: .fit), .reference: ComparisonRequest(action: .fit),
    ]
  }
  func setLinked(_ value: Bool) {
    linked = value
    guard value, enabled else { return }
    let active = viewports[.active] ?? Viewport()
    requests[.reference] = ComparisonRequest(
      action: active.zoom ? .zoom(active.center, scale: active.scale) : .fit)
  }
  func zoom(_ value: Bool, center: CGPoint, scale: Double = 1, from pane: ComparisonPane) {
    let point = bounded(center)
    viewports[pane] = Viewport(zoom: value, scale: InspectionZoom.bounded(scale), center: point)
    guard enabled, linked else { return }
    viewports[pane.other] = Viewport(
      zoom: value, scale: InspectionZoom.bounded(scale), center: point)
    requests[pane.other] = ComparisonRequest(
      action: value ? .zoom(point, scale: InspectionZoom.bounded(scale)) : .fit)
  }
  func pan(_ point: CGPoint, from pane: ComparisonPane) {
    let point = bounded(point)
    viewports[pane, default: Viewport()].center = point
    guard enabled, linked else { return }
    viewports[pane.other, default: Viewport()].center = point
    requests[pane.other] = ComparisonRequest(action: .pan(point))
  }
  private func bounded(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: point.x.isFinite ? min(1, max(0, point.x)) : 0.5,
      y: point.y.isFinite ? min(1, max(0, point.y)) : 0.5)
  }
}
