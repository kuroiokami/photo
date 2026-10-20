import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI

private struct DetailPresentation {
  var zoom = false
  var magnification = 1.0
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
  var comparison: ComparisonSession? = nil
  var pane: ComparisonPane = .active
  var edit = PhotoEdit()
  @DetailStorage private var state = DetailPresentation()

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Button {
          chooseZoom(false)
        } label: {
          Text("Fit").frame(width: 46, height: 25)
            .background(
              !state.zoom ? Color.accentColor : Color.white.opacity(0.1),
              in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).accessibilityValue(!state.zoom ? "Selected" : "Not selected")
        Button {
          chooseZoom(true)
        } label: {
          Text("100%").frame(width: 58, height: 25)
            .background(
              state.zoom && abs(state.magnification - 1) < 0.005
                ? Color.accentColor : Color.white.opacity(0.1),
              in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
          .accessibilityValue(
            state.zoom && abs(state.magnification - 1) < 0.005 ? "Selected" : "Not selected"
          )
          .help(
            "One image pixel per physical display pixel. Pinch to adjust magnification; two-finger scrolling pans."
          )
        Spacer()
        if state.zoom, state.image == nil, state.error == nil {
          ProgressView().controlSize(.small)
          Text(state.region == nil ? "Loading…" : "Finishing…").font(.caption).lineLimit(1)
          Button("Cancel") { chooseZoom(false) }.help("Cancel detail loading and return to Fit.")
        }
      }.buttonStyle(.borderless)
      GeometryReader { geometry in
        ZStack(alignment: .bottomTrailing) {
          if state.zoom, let display = state.display {
            PixelScrollView(
              image: display.image, focal: state.focal,
              canvasSize: display.size, imageBounds: display.bounds, navigation: state.navigation,
              visible: $state.visible, edit: edit, magnification: state.magnification,
              onMagnify: magnify, onFit: { chooseZoom(false) },
              onPan: { comparison?.pan($0, from: pane) })
            if let thumbnail = state.fitPreview?.image ?? state.image?.image {
              navigator(thumbnail, width: Int(display.size.width), height: Int(display.size.height))
            }
          } else {
            PhotoImageView(
              photo: photo, pipeline: pipeline, maximumPixelSize: 2560, edit: edit,
              detailed: true, sessionID: sessionID,
              onLoaded: { preview in
                state.fitPreview = preview
                state.fitSize = CGSize(width: preview.decodedWidth, height: preview.decodedHeight)
              }
            )
            .simultaneousGesture(
              MagnifyGesture(minimumScaleDelta: 0.03).onChanged { value in
                guard !state.zoom, state.fitPreview != nil, value.magnification > 1.03 else {
                  return
                }
                let frame = CropGeometry.fit(edit.cropBounds(state.fitSize).size, in: geometry.size)
                state.focal = CropGeometry.point(
                  CGPoint(
                    x: value.startAnchor.x * geometry.size.width,
                    y: value.startAnchor.y * geometry.size.height), frame: frame)
                chooseZoom(true, scale: fitMagnification * value.magnification)
              }
            )
            .simultaneousGesture(
              SpatialTapGesture(count: 2).onEnded { event in
                let size = edit.cropBounds(state.fitSize).size
                let scale = min(
                  geometry.size.width / size.width, geometry.size.height / size.height)
                let displayed = CGSize(width: size.width * scale, height: size.height * scale)
                let origin = CGPoint(
                  x: (geometry.size.width - displayed.width) / 2,
                  y: (geometry.size.height - displayed.height) / 2)
                state.focal = CGPoint(
                  x: min(1, max(0, (event.location.x - origin.x) / displayed.width)),
                  y: min(1, max(0, (event.location.y - origin.y) / displayed.height)))
                chooseZoom(true)
              })
          }
        }
        .onChange(of: geometry.size, initial: true) { state.viewport = geometry.size }
      }
      if state.zoom {
        Text(
          state.image.map {
            "\($0.sourceKind.rawValue) · \(Int((state.magnification * 100).rounded()))% · \($0.decodedWidth) × \($0.decodedHeight)"
          }
            ?? (state.region != nil
              ? "Rendered RAW · \(Int((state.magnification * 100).rounded()))% focus region · surrounding detail is loading"
              : "Preparing full detail…")
        )
        .font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 28)
      }
      if let error = state.error {
        Text(error).font(.caption).foregroundStyle(.secondary)
        Button("Retry Full Detail") {
          chooseZoom(true)
        }
      }
    }
    .onChange(of: comparison?.request(for: pane)) { _, request in
      guard let request else { return }
      switch request.action {
      case .fit: fit()
      case .zoom(let point, let scale):
        state.magnification = scale
        state.error = nil
        state.focal = point
        state.navigation = DetailNavigationRequest(center: point)
        state.zoom = true
      case .pan(let point):
        if state.zoom { state.navigation = DetailNavigationRequest(center: point) }
      }
    }
    .onChange(of: edit) {
      fit()
      comparison?.resetViewports()
    }
    .task(id: state.zoom) {
      guard state.zoom else { return }
      do {
        guard let url = photo.fileURL ?? SampleResources.url(for: photo) else {
          throw PreviewError.unreadable
        }
        let scale = NSApp.keyWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let focus = DetailFocus(
          point: edit.originalPoint(state.focal, original: originalSize),
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
        comparison?.zoom(false, center: state.focal, from: pane)
      }
    }
    .onDisappear { fit() }
  }

  private var originalSize: CGSize {
    state.fitPreview.map { CGSize(width: $0.originalWidth, height: $0.originalHeight) }
      ?? state.fitSize
  }
  private var fitMagnification: Double {
    let pixels = edit.cropBounds(originalSize).size
    let backing = NSApp.keyWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    return min(
      state.viewport.width * backing / max(1, pixels.width),
      state.viewport.height * backing / max(1, pixels.height))
  }
  private func magnify(_ delta: Double, _ center: CGPoint, _ anchor: CGPoint) {
    let scale = InspectionZoom.changed(state.magnification, delta: delta)
    if delta < 0 && fitMagnification < 1 && scale <= fitMagnification * 1.02 {
      chooseZoom(false)
      return
    }
    state.magnification = scale
    state.focal = center
    state.navigation = DetailNavigationRequest(center: center, anchor: anchor)
    let output = edit.cropBounds(originalSize).size
    let backing = NSApp.keyWindow?.backingScaleFactor ?? 1
    let span = CGSize(
      width: state.viewport.width * backing / max(1, output.width * scale),
      height: state.viewport.height * backing / max(1, output.height * scale))
    let linkedCenter = NavigatorGeometry.center(
      CGPoint(
        x: center.x + (0.5 - anchor.x) * span.width, y: center.y + (0.5 - anchor.y) * span.height),
      visible: span)
    comparison?.zoom(true, center: linkedCenter, scale: scale, from: pane)
  }
  private func chooseZoom(_ zoom: Bool, scale: Double = 1) {
    let center = state.zoom ? CGPoint(x: state.visible.midX, y: state.visible.midY) : state.focal
    if zoom {
      state.error = nil
      state.magnification = InspectionZoom.bounded(scale)
      state.zoom = true
    } else {
      fit()
    }
    comparison?.zoom(zoom, center: center, scale: state.magnification, from: pane)
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
      image: image, edit: edit,
      imageSize: edit.cropBounds(CGSize(width: imageWidth, height: imageHeight)).size,
      visible: state.visible
    ) { point in
      state.navigation = DetailNavigationRequest(center: point)
      comparison?.pan(point, from: pane)
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
  var edit = PhotoEdit()
  var magnification = 1.0
  var onMagnify: (@MainActor (Double, CGPoint, CGPoint) -> Void)? = nil
  let onFit: () -> Void
  var onPan: (@MainActor (CGPoint) -> Void)? = nil

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
    view.edit = edit
    view.inspectionScale = magnification
    view.onMagnify = onMagnify
    view.onFit = onFit
    view.onUserPan = { point in Task { @MainActor in onPan?(point) } }
    return view
  }
  func updateNSView(_ view: PixelScroller, context: Context) {
    view.edit = edit
    view.inspectionScale = magnification
    view.onMagnify = onMagnify
    view.onFit = onFit
    view.onUserPan = { point in Task { @MainActor in onPan?(point) } }
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
      needsDisplay = true
    }
  }
  var imageFrame = CGRect.zero
  var originalSize = CGSize.zero
  var edit = PhotoEdit()
  var onFit: (() -> Void)?
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.black.setFill()
    dirtyRect.fill()
    guard let image else { return }
    ImageEditDrawing.draw(
      image, region: imageFrame, original: originalSize, edit: edit, in: bounds,
      interpolation: .none)
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
  var edit = PhotoEdit()
  var inspectionScale = 1.0
  var onMagnify: (@MainActor (Double, CGPoint, CGPoint) -> Void)?
  var pixelSize = CGSize.zero
  var imageBounds = CGRect.zero
  var focal = CGPoint(x: 0.5, y: 0.5)
  var onVisible: ((CGRect) -> Void)?
  var onUserPan: ((CGPoint) -> Void)?
  private var programmatic = false
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
        MainActor.assumeIsolated { self?.reportVisible(user: true) }
      })
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func magnify(with event: NSEvent) {
    let point = canvas.convert(event.locationInWindow, from: nil)
    let anchor = CGPoint(
      x: (point.x - contentView.bounds.minX) / max(1, contentSize.width),
      y: (point.y - contentView.bounds.minY) / max(1, contentSize.height))
    onMagnify?(
      Double(event.magnification),
      CGPoint(x: point.x / max(1, canvas.bounds.width), y: point.y / max(1, canvas.bounds.height)),
      anchor)
  }
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
    programmatic = true
    defer { programmatic = false }
    guard let pixelImage else { return }
    if canvas.image !== pixelImage { canvas.image = pixelImage }
    canvas.onFit = onFit
    let newScale = (window?.backingScaleFactor ?? 1) / InspectionZoom.bounded(inspectionScale)
    let cropped = edit.cropBounds(pixelSize).size
    let desiredSize = CGSize(width: cropped.width / newScale, height: cropped.height / newScale)
    if canvas.edit != edit || canvas.originalSize != pixelSize {
      canvas.edit = edit
      canvas.originalSize = pixelSize
      canvas.needsDisplay = true
    }
    if scale != newScale || canvas.frame.size != desiredSize {
      scale = newScale
      canvas.frame.size = desiredSize
      canvas.needsDisplay = true
      initialPosition = false
    }
    let frame = imageBounds
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
    programmatic = true
    defer { programmatic = false }
    initialPosition = true
    contentView.scroll(
      to: NavigatorGeometry.origin(
        center: request.center,
        image: canvas.bounds.size, viewport: contentSize, anchor: request.anchor))
    reflectScrolledClipView(contentView)
    reportVisible()
  }
  private func reportVisible(user: Bool = false) {
    let size = canvas.bounds.size
    guard size.width > 0, size.height > 0 else { return }
    let rect = contentView.bounds.intersection(canvas.bounds)
    guard !rect.isNull else { return }
    onVisible?(
      CGRect(
        x: rect.minX / size.width, y: rect.minY / size.height,
        width: rect.width / size.width, height: rect.height / size.height))
    if user && !programmatic && initialPosition {
      onUserPan?(CGPoint(x: rect.midX / size.width, y: rect.midY / size.height))
    }
  }
}
