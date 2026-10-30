import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI

private typealias ImageStorage = SwiftUI.State<DisplayedPreview?>
private typealias ErrorStorage = SwiftUI.State<ImageFailure?>
private typealias RetryStorage = SwiftUI.State<Int>

struct ImageRequestIdentity: Equatable {
  let photoID: String
  let pipeline: ObjectIdentifier
  let session: UUID?
  let maximumPixelSize: Int
  let cacheGeneration: Int
  let retry: Int
  func sameImage(as other: Self) -> Bool {
    photoID == other.photoID && pipeline == other.pipeline && session == other.session
      && cacheGeneration == other.cacheGeneration
  }

}

private struct DisplayedPreview {
  let identity: ImageRequestIdentity
  let preview: PhotoPreview
  let pixelSize: Int
}
private struct ImageFailure {
  let identity: ImageRequestIdentity
  let message: String
}

struct PhotoImageView: View {
  let photo: PhotoItem
  let pipeline: ImagePipeline
  let maximumPixelSize: Int
  var edit = PhotoEdit()
  var detailed = false
  var prioritize = false
  var sessionID: UUID?
  var cacheGeneration = 0
  var onLoaded: ((PhotoPreview) -> Void)?
  @ImageStorage private var displayed: DisplayedPreview?
  @ErrorStorage private var failure: ImageFailure?
  @RetryStorage private var retry = 0

  private var request: ImageRequestIdentity {
    ImageRequestIdentity(
      photoID: photo.id, pipeline: ObjectIdentifier(pipeline), session: sessionID,
      maximumPixelSize: maximumPixelSize, cacheGeneration: cacheGeneration, retry: retry)
  }
  private var preview: PhotoPreview? {
    displayed.flatMap { $0.identity.sameImage(as: request) ? $0.preview : nil }
  }
  private var error: String? {
    failure.flatMap { $0.identity.sameImage(as: request) ? $0.message : nil }
  }
  private func show(_ value: PhotoPreview, pixelSize: Int) {
    displayed = DisplayedPreview(identity: request, preview: value, pixelSize: pixelSize)
  }

  var body: some View {
    ZStack {
      Color.black.opacity(0.12)
      if let preview = preview ?? immediatePreview {
        if edit.isEdited {
          EditedBitmap(image: preview.image, edit: edit)
            .accessibilityLabel(photo.filename)
        } else {
          // Most culling frames need no custom AppKit drawing/view bridge.
          Image(decorative: preview.image, scale: 1)
            .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            .accessibilityLabel(photo.filename)
        }
      } else if let error {
        VStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle").font(.title2)
            .accessibilityLabel("Could not load \(photo.filename)")
          if detailed {
            Text("Preview unavailable").font(.headline)
            Text(error).font(.caption).multilineTextAlignment(.center)
            Button("Try Again") { retry += 1 }
          }
        }
        .foregroundStyle(.secondary).padding(12)
        .help(error)
      } else {
        ProgressView().controlSize(detailed ? .regular : .small)
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if detailed, let preview {
        Text("\(preview.sourceKind.rawValue) · \(preview.decodedWidth) × \(preview.decodedHeight)")
          .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
          .padding(8).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
          .padding(12)
      }
    }
    .task(
      id: request,
      priority: detailed || prioritize ? .userInitiated : .utility
    ) { await load() }
    .onChange(of: prioritize) {
      guard prioritize, let url = photo.fileURL ?? SampleResources.url(for: photo) else { return }
      Task {
        await pipeline.prioritizePreview(
          for: url, maximumPixelSize: maximumPixelSize, sessionID: sessionID)
      }
    }
    .onDisappear { displayed = nil }
  }

  private var immediatePreview: PhotoPreview? {
    guard let url = photo.fileURL ?? SampleResources.url(for: photo) else { return nil }
    return pipeline.immediateCachedPreview(
      for: url, maximumPixelSize: maximumPixelSize, sessionID: sessionID)
      ?? pipeline.bestCachedThumbnail(
        for: url, maximumPixelSize: maximumPixelSize,
        sessionID: sessionID)?.preview
  }

  @MainActor
  private func load() async {
    let trace = PhotoTrace.begin(detailed ? "FitRequest" : "ThumbnailRequest")
    defer { PhotoTrace.end(trace) }
    await PhotoTrace.$request.withValue(trace) { await loadResult(trace) }
  }

  @MainActor
  private func loadResult(_ trace: PhotoTrace.Interval) async {
    failure = nil
    do {
      let url: URL
      if let fileURL = photo.fileURL {
        url = fileURL
      } else if let resource = SampleResources.url(for: photo) {
        url = resource
      } else {
        throw PreviewError.unreadable
      }
      if let cached = pipeline.immediateCachedPreview(
        for: url, maximumPixelSize: maximumPixelSize, sessionID: sessionID
      ) {
        try Task.checkCancellation()
        show(cached, pixelSize: maximumPixelSize)
        PhotoTrace.event("RAMResultPublished", in: trace)
        onLoaded?(cached)
        return
      }
      try Task.checkCancellation()
      if let retained = displayed, retained.identity.sameImage(as: request),
        retained.pixelSize >= maximumPixelSize
      {
        onLoaded?(retained.preview)
        return
      }
      if let cached = pipeline.bestCachedThumbnail(
        for: url,
        maximumPixelSize: maximumPixelSize, sessionID: sessionID)
      {
        show(cached.preview, pixelSize: cached.requestedPixelSize)
        if cached.requestedPixelSize >= maximumPixelSize {
          onLoaded?(cached.preview)
          return
        }
      } else if preview == nil {
        displayed = nil
      }
      // A valid smaller preview stays visible until the larger one is ready.
      // Only cold previews need the arrow-repeat debounce. Cached images are immediate.
      if detailed { try await Task.sleep(for: .milliseconds(35)) }
      let result = try await pipeline.preview(
        for: url, maximumPixelSize: maximumPixelSize, sessionID: sessionID,
        priority: detailed || prioritize ? .selected : .visible)
      try Task.checkCancellation()
      show(result, pixelSize: maximumPixelSize)
      PhotoTrace.event("ImageResultPublished", in: trace)
      onLoaded?(result)
    } catch is CancellationError {
      PhotoTrace.event("ImageRequestCancelled", in: trace)
      // A disappearing cell or superseded preview must not publish stale state.
    } catch {
      guard !Task.isCancelled else { return }
      if preview == nil { displayed = nil }
      failure = ImageFailure(identity: request, message: error.localizedDescription)
    }
  }
}
