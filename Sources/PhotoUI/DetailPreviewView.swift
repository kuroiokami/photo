import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI

private struct NearbyFitRequest: Equatable {
  let ready: Bool
  let files: [URL]
}

private struct DetailRequest: Equatable {
  let photoID: String
  let zoom: Bool
  let source: DetailSource
}
private struct DetailPresentation {
  var zoom = false
  var source: DetailSource = .original
  var image: PhotoPreview?
  var region: DetailRegion?
  var fitPreview: PhotoPreview?
  var viewport = CGSize(width: 600, height: 500)
  var fitSize = CGSize(width: 1, height: 1)
  var error: String?
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
private typealias ViewportStorage = SwiftUI.State<InspectionViewport>
private typealias DetailStorage = SwiftUI.State<DetailPresentation>

struct DetailPreviewView: View {
  let photo: PhotoItem
  let pipeline: ImagePipeline
  let detailPipeline: DetailPipeline
  let sessionID: UUID
  var comparison: ComparisonSession? = nil
  var pane: ComparisonPane = .active
  var edit = PhotoEdit()
  var nearbyFiles: [URL] = []
  var didMeasure: ((CGSize) -> Void)? = nil
  @Environment(\.scenePhase) private var scenePhase
  @ViewportStorage private var viewport = InspectionViewport()
  @DetailStorage private var state = DetailPresentation()

  var body: some View {
    VStack(spacing: 0) {
      InspectionControls(
        viewport: viewport, zoom: state.zoom, loading: state.image == nil && state.error == nil,
        hasRegion: state.region != nil, camera: state.source == .cameraPreview,
        hasCamera: photo.fileURL.map(PhotoFormats.isRaw) ?? false,
        choose: { chooseZoom($0, source: .original) },
        chooseCamera: { chooseZoom(true, source: .cameraPreview) })
      GeometryReader { geometry in
        ZStack(alignment: .bottomTrailing) {
          if state.zoom, let display = state.display {
            InspectionSurface(
              viewport: viewport,

              image: display.image,
              canvasSize: display.size, imageBounds: display.bounds, edit: edit,
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
                viewport.focal = CropGeometry.point(
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
                viewport.focal = CGPoint(
                  x: min(1, max(0, (event.location.x - origin.x) / displayed.width)),
                  y: min(1, max(0, (event.location.y - origin.y) / displayed.height)))
                chooseZoom(true)
              })
          }
        }
        .onChange(of: geometry.size, initial: true) {
          state.viewport = geometry.size
          didMeasure?(geometry.size)
        }
      }
      if state.zoom {
        InspectionScaleLabel(
          viewport: viewport, source: detailSource, previewPixels: state.source == .cameraPreview)
      }
      if let error = state.error {
        Text(error).font(.caption).foregroundStyle(.secondary)
        Button(state.source == .cameraPreview ? "Retry Camera Preview" : "Retry Full Detail") {
          chooseZoom(true)
        }
      }
    }
    .background {
      ComparisonCommandRelay(channel: comparison?.channel(for: pane)) { request in
        switch request.action {
        case .fit: fit()
        case .zoom(let point, let scale), .cameraPreview(let point, let scale):
          let source: DetailSource
          if case .cameraPreview = request.action, photo.fileURL.map(PhotoFormats.isRaw) == true {
            source = .cameraPreview
          } else {
            source = .original
          }
          if state.source != source {
            state.image = nil
            state.region = nil
            state.source = source
          }
          viewport.magnification = scale
          if state.error != nil { state.error = nil }
          viewport.focal = point
          viewport.navigation = DetailNavigationRequest(center: point)
          if !state.zoom { state.zoom = true }
        case .pan(let point):
          if state.zoom { viewport.navigation = DetailNavigationRequest(center: point) }
        }
      }
    }
    .onChange(of: edit) {
      fit()
      comparison?.resetViewports()
    }
    .task(id: DetailRequest(photoID: photo.id, zoom: state.zoom, source: state.source)) {
      guard state.zoom, !Task.isCancelled else { return }
      do {
        guard let url = photo.fileURL ?? SampleResources.url(for: photo) else {
          throw PreviewError.unreadable
        }
        let scale = NSApp.keyWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let focus = DetailFocus(
          point: edit.originalPoint(viewport.focal, original: originalSize),
          viewportPixels: CGSize(
            width: state.viewport.width * scale, height: state.viewport.height * scale))
        for try await update in detailPipeline.updates(for: url, focus: focus, source: state.source)
        {
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
        comparison?.zoom(false, center: viewport.focal, from: pane)
      }
    }
    .task(
      id: NearbyFitRequest(
        ready: scenePhase == .active && !state.zoom && state.fitPreview != nil, files: nearbyFiles),
      priority: .background
    ) {
      guard scenePhase == .active, !state.zoom, state.fitPreview != nil, !nearbyFiles.isEmpty,
        let file = photo.fileURL ?? SampleResources.url(for: photo)
      else { return }
      await pipeline.prepareNearby(after: file, candidates: nearbyFiles, sessionID: sessionID)
    }
    .onDisappear { fit() }
  }

  private var detailSource: String {
    if let image = state.image {
      return "\(image.sourceKind.rawValue) · \(image.decodedWidth) × \(image.decodedHeight)"
    }
    return state.region != nil
      ? "Rendered RAW · focus region · surrounding detail is loading"
      : (state.source == .cameraPreview ? "Preparing camera preview…" : "Preparing full detail…")
  }
  private var originalSize: CGSize {
    if state.source == .cameraPreview, let image = state.image {
      return CGSize(width: image.decodedWidth, height: image.decodedHeight)
    }
    return state.fitPreview.map { CGSize(width: $0.originalWidth, height: $0.originalHeight) }
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
    let scale = InspectionZoom.changed(viewport.magnification, delta: delta)
    if delta < 0 && fitMagnification < 1 && scale <= fitMagnification * 1.02 {
      chooseZoom(false)
      return
    }
    viewport.magnification = scale
    viewport.focal = center
    viewport.navigation = DetailNavigationRequest(center: center, anchor: anchor)
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
  private func chooseZoom(_ zoom: Bool, scale: Double = 1, source: DetailSource? = nil) {
    let center =
      state.zoom ? CGPoint(x: viewport.visible.midX, y: viewport.visible.midY) : viewport.focal
    if zoom {
      if let source, state.source != source {
        state.image = nil
        state.region = nil
        state.source = source
      }
      if state.error != nil { state.error = nil }
      viewport.magnification = InspectionZoom.bounded(scale)
      if !state.zoom { state.zoom = true }
    } else {
      fit()
    }
    comparison?.zoom(
      zoom, center: center, scale: viewport.magnification, source: state.source, from: pane)
  }

  private func fit() {
    state.zoom = false
    state.source = .original
    state.image = nil
    state.region = nil
    state.error = nil
    viewport.navigation = nil
  }

  private func navigator(_ image: CGImage, width imageWidth: Int, height imageHeight: Int)
    -> some View
  {
    InspectionNavigatorView(
      viewport: viewport,
      image: image, edit: edit,
      imageSize: edit.cropBounds(CGSize(width: imageWidth, height: imageHeight)).size
    ) { point in
      viewport.navigation = DetailNavigationRequest(center: point)
      comparison?.pan(point, from: pane)
    }

  }
}

/// Ordinary scroll reports go through the binding without registering image
/// controls on the visible rectangle. Only commands update the native surface.
private struct InspectionSurface: View {
  let viewport: InspectionViewport
  let image: CGImage
  let canvasSize: CGSize
  let imageBounds: CGRect
  let edit: PhotoEdit
  let onMagnify: @MainActor (Double, CGPoint, CGPoint) -> Void
  let onFit: @MainActor () -> Void
  let onPan: @MainActor (CGPoint) -> Void
  var body: some View {
    PixelScrollView(
      image: image, focal: viewport.focal, canvasSize: canvasSize, imageBounds: imageBounds,
      navigation: viewport.navigation,
      visible: Binding(get: { viewport.visible }, set: { viewport.visible = $0 }),
      edit: edit, magnification: viewport.magnification, onMagnify: onMagnify, onFit: onFit,
      onPan: onPan)
  }
}
private struct InspectionControls: View {
  let viewport: InspectionViewport
  let zoom: Bool
  let loading: Bool
  let hasRegion: Bool
  let camera: Bool
  let hasCamera: Bool
  let choose: (Bool) -> Void
  let chooseCamera: () -> Void
  var body: some View {
    HStack {
      Button {
        choose(false)
      } label: {
        Text("Fit").frame(width: 46, height: 25)
          .background(
            !zoom ? Color.accentColor : Color.white.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 5))
      }.buttonStyle(.plain).accessibilityValue(!zoom ? "Selected" : "Not selected")
      Button {
        choose(true)
      } label: {
        Text("100%").frame(width: 58, height: 25)
          .background(
            !camera && zoom && abs(viewport.magnification - 1) < 0.005
              ? Color.accentColor : Color.white.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 5))
      }.buttonStyle(.plain)
        .accessibilityValue(
          !camera && zoom && abs(viewport.magnification - 1) < 0.005 ? "Selected" : "Not selected"
        )
        .help(
          "Z toggles Fit / 100%. One image pixel per physical display pixel. Pinch to adjust magnification; two-finger scrolling pans."
        )
      if hasCamera {
        Button(action: chooseCamera) {
          Text("Camera Preview").frame(height: 25).padding(.horizontal, 8)
            .background(
              camera && zoom ? Color.accentColor : Color.white.opacity(0.1),
              in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).accessibilityValue(camera && zoom ? "Selected" : "Not selected")
          .help(
            "Inspect the camera JPEG or embedded preview (⌥Z). One preview pixel per display pixel; Z requests rendered RAW."
          )
      }
      Spacer()
      if zoom, loading {
        ProgressView().controlSize(.small)
        Text(!hasRegion ? "Loading…" : "Finishing…").font(.caption).lineLimit(1)
        Button("Cancel") { choose(false) }.help("Cancel detail loading and return to Fit.")
      }
    }.buttonStyle(.borderless)
  }
}

private struct ComparisonCommandRelay: View {
  let channel: ComparisonChannel?
  let apply: (ComparisonRequest) -> Void
  var body: some View {
    Color.clear.frame(width: 0, height: 0).onChange(of: channel?.request, initial: true) {
      _, request in
      if let request { apply(request) }
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

  func makeCoordinator() -> InspectionReports { InspectionReports() }
  private func bindReports(_ reports: InspectionReports) {
    reports.onVisible = { rect in if visible != rect { visible = rect } }
    reports.onPan = onPan
  }
  static func dismantleNSView(_ view: PixelScroller, coordinator: InspectionReports) {
    view.onVisible = nil
    view.onUserPan = nil
    coordinator.cancel()
  }
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
    let reports = context.coordinator
    bindReports(reports)
    view.onVisible = { [weak reports] rect in reports?.visible(rect) }
    view.edit = edit
    view.inspectionScale = magnification
    view.onMagnify = onMagnify
    view.onFit = onFit
    view.onUserPan = { [weak reports] point in reports?.pan(point) }
    return view
  }
  func updateNSView(_ view: PixelScroller, context: Context) {
    let reports = context.coordinator
    bindReports(reports)
    view.edit = edit
    view.inspectionScale = magnification
    view.onMagnify = onMagnify
    view.onFit = onFit
    view.onUserPan = { [weak reports] point in reports?.pan(point) }
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
