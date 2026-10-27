import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI

private typealias ImageStorage = SwiftUI.State<PhotoPreview?>
private typealias ErrorStorage = SwiftUI.State<String?>
private typealias RetryStorage = SwiftUI.State<Int>

private struct ImageRequestIdentity: Equatable {
  let photoID: String
  let pipeline: ObjectIdentifier
  let session: UUID?
  let maximumPixelSize: Int
  let cacheGeneration: Int
  let retry: Int
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
  @ImageStorage private var preview: PhotoPreview?
  @ErrorStorage private var error: String?
  @RetryStorage private var retry = 0

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
      id: ImageRequestIdentity(
        photoID: photo.id, pipeline: ObjectIdentifier(pipeline), session: sessionID,
        maximumPixelSize: maximumPixelSize, cacheGeneration: cacheGeneration, retry: retry),
      priority: detailed || prioritize ? .userInitiated : .utility
    ) { await load() }
    .onChange(of: prioritize) {
      guard prioritize, let url = photo.fileURL ?? SampleResources.url(for: photo) else { return }
      Task {
        await pipeline.prioritizePreview(
          for: url, maximumPixelSize: maximumPixelSize, sessionID: sessionID)
      }
    }
    .onDisappear { preview = nil }
  }

  private var immediatePreview: PhotoPreview? {
    guard let url = photo.fileURL ?? SampleResources.url(for: photo) else { return nil }
    return pipeline.immediateCachedPreview(
      for: url, maximumPixelSize: maximumPixelSize, sessionID: sessionID)
  }

  @MainActor
  private func load() async {
    let trace = PhotoTrace.begin(detailed ? "FitRequest" : "ThumbnailRequest")
    defer { PhotoTrace.end(trace) }
    await PhotoTrace.$request.withValue(trace) { await loadResult(trace) }
  }

  @MainActor
  private func loadResult(_ trace: PhotoTrace.Interval) async {
    error = nil
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
        preview = cached
        PhotoTrace.event("RAMResultPublished", in: trace)
        onLoaded?(cached)
        return
      }
      preview = nil
      // Only cold previews need the arrow-repeat debounce. Cached images are immediate.
      if detailed { try await Task.sleep(for: .milliseconds(35)) }
      let result = try await pipeline.preview(
        for: url, maximumPixelSize: maximumPixelSize, sessionID: sessionID,
        priority: detailed || prioritize ? .selected : .visible)
      try Task.checkCancellation()
      preview = result
      PhotoTrace.event("ImageResultPublished", in: trace)
      onLoaded?(result)
    } catch is CancellationError {
      PhotoTrace.event("ImageRequestCancelled", in: trace)
      // A disappearing cell or superseded preview must not publish stale state.
    } catch {
      guard !Task.isCancelled else { return }
      preview = nil
      self.error = error.localizedDescription
    }
  }
}
