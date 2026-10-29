import Observation
import PhotoCore
import SwiftUI

/// Scroll reports update the navigator without invalidating decoded-image and
/// loading/control state. Navigation commands are observed independently.
@MainActor @Observable
final class InspectionViewport {
  var magnification = 1.0
  var focal = CGPoint(x: 0.5, y: 0.5)
  var visible = CGRect(x: 0, y: 0, width: 1, height: 1)
  var navigation: DetailNavigationRequest?
}
struct InspectionNavigatorView: View {
  let viewport: InspectionViewport
  let image: CGImage
  let edit: PhotoEdit
  let imageSize: CGSize
  let navigate: @MainActor (CGPoint) -> Void
  var body: some View {
    DetailNavigator(
      image: image, edit: edit, imageSize: imageSize, visible: viewport.visible, navigate: navigate)
  }
}

/// At most one deferred publication per native callback burst. The representable
/// rebinds handlers on update and cancels on teardown so late reports cannot
/// update a removed viewport or an obsolete binding.
@MainActor
final class InspectionReports {
  var onVisible: (@MainActor (CGRect) -> Void)?
  var onPan: (@MainActor (CGPoint) -> Void)?
  private var rectangle: CGRect?
  private var point: CGPoint?
  private var task: Task<Void, Never>?
  func visible(_ value: CGRect) {
    rectangle = value
    schedule()
  }
  func pan(_ value: CGPoint) {
    point = value
    schedule()
  }
  func cancel() {
    task?.cancel()
    task = nil
    rectangle = nil
    point = nil
    onVisible = nil
    onPan = nil
  }
  private func schedule() {
    guard task == nil else { return }
    task = Task { @MainActor [weak self] in
      await Task.yield()
      guard !Task.isCancelled, let self else { return }
      let rectangle = self.rectangle
      let point = self.point
      self.rectangle = nil
      self.point = nil
      self.task = nil
      if let rectangle { self.onVisible?(rectangle) }
      if let point { self.onPan?(point) }
    }
  }
}

struct InspectionScaleLabel: View {
  let viewport: InspectionViewport
  let source: String
  var body: some View {
    Text(source + " · \(Int((viewport.magnification*100).rounded()))%")
      .font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(height: 16)
  }
}
