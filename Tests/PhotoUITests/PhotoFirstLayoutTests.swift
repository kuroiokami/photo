import AppKit
import Observation
import PhotoCore
import SwiftUI
import Testing

@testable import PhotoUI

private final class LayoutTrackingFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var flag = false
  func mark() {
    lock.lock()
    flag = true
    lock.unlock()
  }
  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return flag
  }
}
@MainActor private final class LayoutCounts { var parent = 0 }
private struct NavigatorIsolationProbe: View {
  let counts: LayoutCounts
  let viewport: InspectionViewport
  let image: CGImage
  var body: some View {
    let _ = { counts.parent += 1 }()
    VStack {
      Text("Image controls")
      InspectionScaleLabel(viewport: viewport, source: "Rendered image")
      InspectionNavigatorView(
        viewport: viewport, image: image, edit: PhotoEdit(),
        imageSize: CGSize(width: 640, height: 400), navigate: { _ in })
    }
  }
}
@MainActor
struct PhotoFirstLayoutTests {
  @Test func focusRestoresSidebarAndFilmstripChoices() {
    let layout = WorkspaceLayout()
    layout.sidebar = .detailOnly
    layout.filmstrip = false
    layout.toggleFocus()
    #expect(layout.focused && layout.sidebar == .detailOnly && !layout.showsFilmstrip)
    layout.leaveFocus()
    #expect(!layout.focused && layout.sidebar == .detailOnly && !layout.filmstrip)
    layout.sidebar = .all
    layout.filmstrip = true
    layout.toggleFocus()
    layout.leaveFocus()
    #expect(layout.sidebar == .all && layout.showsFilmstrip)
  }
  @Test func linkedPanOnlyInvalidatesTheReceivingChannel() {
    let comparison = ComparisonSession()
    comparison.pin(SampleLibrary.photos[0])
    let active = LayoutTrackingFlag()
    let reference = LayoutTrackingFlag()
    withObservationTracking {
      _ = comparison.request(for: .active)
    } onChange: {
      active.mark()
    }
    withObservationTracking {
      _ = comparison.request(for: .reference)
    } onChange: {
      reference.mark()
    }
    comparison.pan(CGPoint(x: 0.3, y: 0.7), from: .active)
    #expect(!active.value && reference.value)
  }
  @Test func navigatorUpdatesPixelsWithoutRebuildingImageControls() async throws {
    let viewport = InspectionViewport()
    let counts = LayoutCounts()
    let ns = try #require(SampleResources.image(for: SampleLibrary.photos[0]))
    let image = try #require(ns.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let renderer = ImageRenderer(
      content: NavigatorIsolationProbe(counts: counts, viewport: viewport, image: image).frame(
        width: 240, height: 180))
    let first = try #require(renderer.nsImage?.tiffRepresentation)
    let baseline = counts.parent
    viewport.visible = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.4)
    var changed = false
    for _ in 0..<30 {
      await Task.yield()
      if renderer.nsImage?.tiffRepresentation != first {
        changed = true
        break
      }
      try await Task.sleep(for: .milliseconds(2))
    }
    #expect(changed && counts.parent == baseline)
    let beforeZoom = try #require(renderer.nsImage?.tiffRepresentation)
    viewport.magnification = 2.0
    for _ in 0..<30 {
      await Task.yield()
      if renderer.nsImage?.tiffRepresentation != beforeZoom { break }
      try await Task.sleep(for: .milliseconds(2))
    }
    #expect(renderer.nsImage?.tiffRepresentation != beforeZoom && counts.parent == baseline)
  }
  @Test func nativeReportBurstsCoalesceAndTeardownRejectsLateResults() async {
    let reports = InspectionReports()
    var visible: [CGRect] = []
    var pans: [CGPoint] = []
    reports.onVisible = { visible.append($0) }
    reports.onPan = { pans.append($0) }
    for i in 0..<200 {
      reports.visible(CGRect(x: Double(i) / 1000, y: 0, width: 0.2, height: 0.3))
      reports.pan(CGPoint(x: Double(i) / 1000, y: 0.5))
    }
    for _ in 0..<30 {
      await Task.yield()
      if !visible.isEmpty { break }
    }
    #expect(visible.count == 1 && pans.count == 1)
    #expect(visible.first?.minX == 0.199 && pans.first?.x == 0.199)
    reports.visible(.zero)
    reports.pan(.zero)
    reports.cancel()
    for _ in 0..<10 { await Task.yield() }
    #expect(visible.count == 1 && pans.count == 1)
  }
  @Test func photoCanvasKeepsUsefulSpaceAndFocusExpandsIt() async throws {
    _ = NSApplication.shared
    for size in [CGSize(width: 1200, height: 800), CGSize(width: 960, height: 640)] {
      let layout = WorkspaceLayout()
      var canvas = CGSize.zero
      let root = WorkspaceView(
        workspace: WorkspaceState(), layout: layout, canvasMeasured: { canvas = $0 })
      let host = NSHostingView(rootView: root)
      host.frame = CGRect(origin: .zero, size: size)
      let window = NSWindow(
        contentRect: host.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer { window.close() }
      for _ in 0..<30 {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        if canvas.height > 100 { break }
        try await Task.sleep(for: .milliseconds(2))
      }
      let normal = canvas
      #expect(normal.height > size.height * 0.42)
      #expect(normal.width > size.width * 0.65)
      layout.toggleFocus()
      for _ in 0..<40 {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        if canvas.height > normal.height + 100 { break }
        try await Task.sleep(for: .milliseconds(2))
      }
      #expect(canvas.height > normal.height + 100)
      #expect(canvas.width >= normal.width)
      print(
        "Photo canvas points: window=\(size.width)x\(size.height) normal=\(normal.width)x\(normal.height) focus=\(canvas.width)x\(canvas.height)"
      )
    }
  }
}
