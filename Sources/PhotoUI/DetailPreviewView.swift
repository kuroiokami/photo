import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI

private struct DetailPresentation {
  var zoom = false
  var image: PhotoPreview?
  var fitSize = CGSize(width: 1, height: 1)
  var focal = CGPoint(x: 0.5, y: 0.5)
  var visible = CGRect(x: 0, y: 0, width: 1, height: 1)
  var error: String?
}
private typealias DetailStorage = SwiftUI.State<DetailPresentation>

struct DetailPreviewView: View {
  let photo: PhotoItem
  let pipeline: ImagePipeline
  let detailPipeline: DetailPipeline
  let sessionID: UUID
  @DetailStorage private var state = DetailPresentation()

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Button("Fit") { fit() }.disabled(!state.zoom)
        Button("100%") { state.zoom = true }.disabled(state.zoom)
        Spacer()
        if state.zoom, state.image == nil, state.error == nil {
          ProgressView().controlSize(.small)
          Text("Loading full detail…").font(.caption)
        }
      }.buttonStyle(.borderless)
      GeometryReader { geometry in
        ZStack(alignment: .bottomTrailing) {
          if state.zoom, let detail = state.image {
            PixelScrollView(
              image: detail.image, focal: state.focal,
              visible: $state.visible, onFit: fit)
            navigator(detail)
          } else {
            PhotoImageView(
              photo: photo, pipeline: pipeline, maximumPixelSize: 2560,
              detailed: true, sessionID: sessionID,
              onLoaded: { preview in
                state.fitSize = CGSize(width: preview.decodedWidth, height: preview.decodedHeight)
              }
            )
            .simultaneousGesture(
              SpatialTapGesture(count: 2).onEnded { event in
                let size = state.fitSize
                let scale = min(
                  geometry.size.width / size.width, geometry.size.height / size.height)
                let displayed = CGSize(width: size.width * scale, height: size.height * scale)
                let origin = CGPoint(
                  x: (geometry.size.width - displayed.width) / 2,
                  y: (geometry.size.height - displayed.height) / 2)
                state.focal = CGPoint(
                  x: min(1, max(0, (event.location.x - origin.x) / displayed.width)),
                  y: min(1, max(0, (event.location.y - origin.y) / displayed.height)))
                state.zoom = true
              })
          }
        }
      }
      if let detail = state.image {
        Text(
          "\(detail.sourceKind.rawValue) · 100% · \(detail.decodedWidth) × \(detail.decodedHeight)"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if let error = state.error {
        Text(error).font(.caption).foregroundStyle(.secondary)
        Button("Retry Full Detail") {
          state.error = nil
          state.zoom = true
        }
      }
    }
    .task(id: state.zoom) {
      guard state.zoom else { return }
      do {
        guard let url = photo.fileURL ?? SampleResources.url(for: photo) else {
          throw PreviewError.unreadable
        }
        let image = try await detailPipeline.detail(for: url)
        try Task.checkCancellation()
        state.image = image
      } catch is CancellationError {} catch {
        guard !Task.isCancelled else { return }
        state.error = error.localizedDescription
        state.zoom = false
        state.image = nil
      }
    }
    .onDisappear { fit() }
  }

  private func fit() {
    state.zoom = false
    state.image = nil
    state.error = nil
  }

  private func navigator(_ detail: PhotoPreview) -> some View {
    let width: CGFloat = 120
    let height = width * CGFloat(detail.decodedHeight) / CGFloat(detail.decodedWidth)
    return ZStack(alignment: .topLeading) {
      Image(decorative: detail.image, scale: 1).resizable()
      Rectangle().stroke(.white, lineWidth: 1)
        .frame(width: width * state.visible.width, height: height * state.visible.height)
        .offset(x: width * state.visible.minX, y: height * state.visible.minY)
    }.frame(width: width, height: height)
      .background(.black).border(.gray).padding(12)
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Navigator showing the visible full-detail region")
  }
}

/// NSScrollView supplies native trackpad/wheel scrolling and drag panning.
/// Document dimensions are pixels / backingScaleFactor, never SwiftUI points = pixels.
private struct PixelScrollView: NSViewRepresentable {
  let image: CGImage
  let focal: CGPoint
  @Binding var visible: CGRect
  let onFit: () -> Void

  func makeNSView(context: Context) -> PixelScroller {
    let view = PixelScroller()
    view.hasHorizontalScroller = true
    view.hasVerticalScroller = true
    view.autohidesScrollers = true
    view.drawsBackground = true
    view.backgroundColor = .black
    view.contentView.postsBoundsChangedNotifications = true
    view.pixelImage = image
    view.focal = focal
    view.onVisible = { rect in
      // AppKit layout callbacks cannot synchronously mutate SwiftUI state.
      Task { @MainActor in visible = rect }
    }
    view.onFit = onFit
    return view
  }
  func updateNSView(_ view: PixelScroller, context: Context) {
    view.onFit = onFit
    view.updateScale()
  }
}

private final class PixelCanvas: NSView {
  var image: CGImage?
  var onFit: (() -> Void)?
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    guard let image else { return }
    NSImage(cgImage: image, size: bounds.size).draw(
      in: bounds,
      from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
      hints: [.interpolation: NSImageInterpolation.none])
  }
  private var dragStart: CGPoint?
  private var dragOrigin = CGPoint.zero
  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      onFit?()
      return
    }
    dragStart = event.locationInWindow
    dragOrigin = enclosingScrollView?.contentView.bounds.origin ?? .zero
  }
  override func mouseDragged(with event: NSEvent) {
    guard let start = dragStart, let scroll = enclosingScrollView else { return }
    let point = event.locationInWindow
    scroll.contentView.scroll(
      to: CGPoint(
        x: dragOrigin.x - point.x + start.x,
        y: dragOrigin.y + point.y - start.y))
    scroll.reflectScrolledClipView(scroll.contentView)
  }
  override func mouseUp(with event: NSEvent) { dragStart = nil }

}

private final class BoundsObserver: @unchecked Sendable {
  let token: NSObjectProtocol
  init(_ token: NSObjectProtocol) { self.token = token }
  deinit { NotificationCenter.default.removeObserver(token) }
}

private final class PixelScroller: NSScrollView {
  var pixelImage: CGImage?
  var focal = CGPoint(x: 0.5, y: 0.5)
  var onVisible: ((CGRect) -> Void)?
  var onFit: (() -> Void)?
  private let canvas = PixelCanvas()
  private var scale: CGFloat = 0
  private var initialPosition = false
  private var observer: BoundsObserver?
  override init(frame: NSRect) {
    super.init(frame: frame)
    documentView = canvas
    observer = BoundsObserver(
      NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification,
        object: contentView, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.reportVisible() }
      })
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateScale()
  }
  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateScale()
  }
  override func layout() {
    super.layout()
    updateScale()
    reportVisible()
  }
  func updateScale() {
    guard let pixelImage else { return }
    canvas.image = pixelImage
    canvas.onFit = onFit
    let newScale = window?.backingScaleFactor ?? 1
    if scale != newScale {
      scale = newScale
      canvas.frame.size = CGSize(
        width: CGFloat(pixelImage.width) / scale,
        height: CGFloat(pixelImage.height) / scale)
      canvas.needsDisplay = true
      initialPosition = false
    }
    if !initialPosition, contentSize.width > 0, contentSize.height > 0 {
      initialPosition = true
      contentView.scroll(
        to: CGPoint(
          x: canvas.frame.width * focal.x - contentSize.width / 2,
          y: canvas.frame.height * focal.y - contentSize.height / 2))
      reflectScrolledClipView(contentView)
    }
  }
  private func reportVisible() {
    let size = canvas.bounds.size
    guard size.width > 0, size.height > 0 else { return }
    let rect = contentView.bounds.intersection(canvas.bounds)
    guard !rect.isNull else { return }
    onVisible?(
      CGRect(
        x: rect.minX / size.width, y: rect.minY / size.height,
        width: rect.width / size.width, height: rect.height / size.height))
  }
}
