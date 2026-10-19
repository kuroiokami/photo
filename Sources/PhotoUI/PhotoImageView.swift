import AppKit
import PhotoCore
import PhotoImaging
import SwiftUI

private typealias ImageStorage = SwiftUI.State<PhotoPreview?>
private typealias ErrorStorage = SwiftUI.State<String?>
private typealias RetryStorage = SwiftUI.State<Int>

struct PhotoImageView: View {
  let photo: PhotoItem
  let pipeline: ImagePipeline
  let maximumPixelSize: Int
  var detailed = false
  var sessionID: UUID?
  @ImageStorage private var preview: PhotoPreview?
  @ErrorStorage private var error: String?
  @RetryStorage private var retry = 0

  var body: some View {
    ZStack {
      Color.black.opacity(0.12)
      if let preview {
        Image(decorative: preview.image, scale: 1)
          .resizable().aspectRatio(contentMode: .fit)
          .accessibilityLabel(photo.filename)
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
      id: "\(photo.id)-\(ObjectIdentifier(pipeline))-\(String(describing: sessionID))-\(retry)",
      priority: detailed ? .userInitiated : .utility
    ) { await load() }
    .onDisappear { preview = nil }
  }

  @MainActor
  private func load() async {
    preview = nil
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
      if detailed,
        let cached = await pipeline.cachedPreview(
          for: url, maximumPixelSize: maximumPixelSize, sessionID: sessionID
        )
      {
        try Task.checkCancellation()
        preview = cached
        return
      }
      // Only cold previews need the arrow-repeat debounce. Cached images are immediate.
      if detailed { try await Task.sleep(for: .milliseconds(35)) }
      let result = try await pipeline.preview(
        for: url, maximumPixelSize: maximumPixelSize, sessionID: sessionID)
      try Task.checkCancellation()
      preview = result
    } catch is CancellationError {
      // A disappearing cell or superseded preview must not publish stale state.
    } catch {
      guard !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
  }
}
