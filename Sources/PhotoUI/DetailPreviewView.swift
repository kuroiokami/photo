import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI

private struct DetailPresentation {
  var zoom = false
  var image: PhotoPreview?
  var region: DetailRegion?
  var fitPreview: PhotoPreview?
  var viewport = CGSize(width: 600, height: 500)
  var fitSize = CGSize(width: 1, height: 1)
  var focal = CGPoint(x: 0.5, y: 0.5)
  var visible = CGRect(x: 0, y: 0, width: 1, height: 1)
  var error: String?
  var navigation: DetailNavigationRequest?
  var display: (image: CGImage, size: CGSize, bounds: CGRect)? {
    if let image {
      let size = CGSize(width: image.decodedWidth, height: image.decodedHeight)
      return (image.image, size, CGRect(origin: .zero, size: size))
    }
    if let region {
      return (
        region.preview.image,
        CGSize(width: region.preview.originalWidth, height: region.preview.originalHeight),
        region.bounds
      )
    }
    return nil
  }
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
        Picker(
          "Zoom",
          selection: Binding(
            get: { state.zoom },
            set: { zoom in
              if zoom {
                state.error = nil
                state.zoom = true
              } else {
                fit()
              }
            })
        ) {
          Text("Fit").tag(false)
          Text("100%").tag(true)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 128)
          .help(
            "Fit shows the whole photo. 100% maps one image pixel to one display pixel; RAW focus detail appears first."
          )
        Spacer()
        if state.zoom, state.image == nil, state.error == nil {
          ProgressView().controlSize(.small)
          Text(state.region == nil ? "Loading…" : "Finishing…").font(.caption).lineLimit(1)
          Button("Cancel") { fit() }.help("Cancel detail loading and return to Fit.")
        }
      }.buttonStyle(.borderless)
      GeometryReader { geometry in
        ZStack(alignment: .bottomTrailing) {
          if state.zoom, let display = state.display {
            PixelScrollView(
              image: display.image, focal: state.focal,
              canvasSize: display.size, imageBounds: display.bounds, navigation: state.navigation,
              visible: $state.visible, onFit: fit)
            if let thumbnail = state.fitPreview?.image ?? state.image?.image {
              navigator(thumbnail, width: Int(display.size.width), height: Int(display.size.height))
            }
          } else {
            PhotoImageView(
              photo: photo, pipeline: pipeline, maximumPixelSize: 2560,
              detailed: true, sessionID: sessionID,
              onLoaded: { preview in
                state.fitPreview = preview
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
        .onChange(of: geometry.size, initial: true) { state.viewport = geometry.size }
      }
      if state.zoom {
        Text(
          state.image.map {
            "\($0.sourceKind.rawValue) · 100% · \($0.decodedWidth) × \($0.decodedHeight)"
          }
            ?? (state.region != nil
              ? "Rendered RAW · 100% focus region · surrounding detail is loading"
              : "Preparing 100% detail…")
        )
        .font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 28)
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
        let scale = NSApp.keyWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let focus = DetailFocus(
          point: state.focal,
          viewportPixels: CGSize(
            width: state.viewport.width * scale, height: state.viewport.height * scale))
        for try await update in detailPipeline.updates(for: url, focus: focus) {
          try Task.checkCancellation()
          switch update {
          case .region(let region): state.region = region
          case .complete(let image):
            state.region = nil
            state.image = image
          }
        }
      } catch is CancellationError {} catch {
        guard !Task.isCancelled else { return }
        state.error = error.localizedDescription
        state.zoom = false
        state.image = nil
        state.region = nil
      }
    }
    .onDisappear { fit() }
  }

  private func fit() {
    state.zoom = false
    state.image = nil
    state.region = nil
    state.error = nil
    state.navigation = nil
  }

  private func navigator(_ image: CGImage, width imageWidth: Int, height imageHeight: Int)
    -> some View
  {
    DetailNavigator(
      image: image, imageSize: CGSize(width: imageWidth, height: imageHeight),
      visible: state.visible
    ) { point in
      state.navigation = DetailNavigationRequest(center: point)
    }

  }
}

/// NSScrollView supplies native trackpad/wheel scrolling and drag panning.
/// Document dimensions are pixels / backingScaleFactor, never SwiftUI points = pixels.
struct PixelScrollView: NSViewRepresentable {
  let image: CGImage
  let focal: CGPoint
  let canvasSize: CGSize
  let imageBounds: CGRect
  let navigation: DetailNavigationRequest?
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
    view.pixelSize = canvasSize
    view.imageBounds = imageBounds
    view.focal = focal
    view.onVisible = { rect in
      // AppKit layout callbacks cannot synchronously mutate SwiftUI state.
      Task { @MainActor in
        if visible != rect { visible = rect }
      }
    }
    view.onFit = onFit
    return view
  }
  func updateNSView(_ view: PixelScroller, context: Context) {
    view.onFit = onFit
    view.pixelImage = image
    view.pixelSize = canvasSize
    view.imageBounds = imageBounds
    view.updateScale()
    if let navigation { view.navigate(navigation) }
  }
}

private final class PixelCanvas: NSView {
  var image: CGImage? {
    didSet {
      guard image !== oldValue else { return }
      drawable = image.map { NSImage(cgImage: $0, size: .zero) }
      needsDisplay = true
    }
  }
  var imageFrame = CGRect.zero
  private var drawable: NSImage?
  var onFit: (() -> Void)?
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.black.setFill()
    dirtyRect.fill()
    guard let drawable else { return }
    drawable.draw(
      in: imageFrame,
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

private final class CenteredPixelClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var result = super.constrainBoundsRect(proposedBounds)
    if let documentView {
      if documentView.frame.width < result.width {
        result.origin.x = (documentView.frame.width - result.width) / 2
      }
      if documentView.frame.height < result.height {
        result.origin.y = (documentView.frame.height - result.height) / 2
      }
    }
    return result
  }
}

final class PixelScroller: NSScrollView {
  var pixelImage: CGImage?
  var pixelSize = CGSize.zero
  var imageBounds = CGRect.zero
  var focal = CGPoint(x: 0.5, y: 0.5)
  var onVisible: ((CGRect) -> Void)?
  var onFit: (() -> Void)?
  private let canvas = PixelCanvas()
  private var scale: CGFloat = 0
  private var initialPosition = false
  private var lastNavigation: UUID?
  private var observer: BoundsObserver?
  override init(frame: NSRect) {
    super.init(frame: frame)
    contentView = CenteredPixelClipView(frame: contentView.frame)
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
    if canvas.image !== pixelImage { canvas.image = pixelImage }
    canvas.onFit = onFit
    let newScale = window?.backingScaleFactor ?? 1
    let desiredSize = CGSize(width: pixelSize.width / newScale, height: pixelSize.height / newScale)
    if scale != newScale || canvas.frame.size != desiredSize {
      scale = newScale
      canvas.frame.size = desiredSize
      canvas.needsDisplay = true
      initialPosition = false
    }
    let frame = CGRect(
      x: imageBounds.minX / scale, y: imageBounds.minY / scale,
      width: imageBounds.width / scale, height: imageBounds.height / scale)
    if canvas.imageFrame != frame {
      canvas.imageFrame = frame
      canvas.needsDisplay = true
    }
    if !initialPosition, contentSize.width > 0, contentSize.height > 0 {
      initialPosition = true
      contentView.scroll(
        to: NavigatorGeometry.origin(center: focal, image: canvas.frame.size, viewport: contentSize)
      )
      reflectScrolledClipView(contentView)
    }
  }
  func navigate(_ request: DetailNavigationRequest) {
    guard request.id != lastNavigation, contentSize.width > 0, contentSize.height > 0 else {
      return
    }
    lastNavigation = request.id
    initialPosition = true
    contentView.scroll(
      to: NavigatorGeometry.origin(
        center: request.center,
        image: canvas.bounds.size, viewport: contentSize))
    reflectScrolledClipView(contentView)
    reportVisible()
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
