import Foundation
import Observation

public enum FolderLoadState: Hashable, Sendable {
  case ready
  case loading
  case failed(String)
}

@MainActor
@Observable
public final class WorkspaceState {
  public private(set) var photos: [PhotoItem]
  public private(set) var selectedID: PhotoItem.ID?
  public private(set) var directory: URL?
  public private(set) var loadState: FolderLoadState = .ready
  public private(set) var sessionID = UUID()
  @ObservationIgnored private let fileAccess: any PhotoFileAccess
  @ObservationIgnored private var folderTask: Task<[URL], Error>?

  public var selectedPhoto: PhotoItem? { photos.first { $0.id == selectedID } }
  public var selectedIndex: Int? { photos.firstIndex { $0.id == selectedID } }
  public var title: String { directory?.lastPathComponent ?? "Sample collection" }

  public init(
    photos: [PhotoItem] = SampleLibrary.photos,
    fileAccess: any PhotoFileAccess = LocalPhotoFileAccess()
  ) {
    self.photos = photos
    self.fileAccess = fileAccess
    selectedID = photos.first?.id
  }

  public func openFolder(_ directory: URL) async {
    let previousID = self.directory == directory ? selectedID : nil
    folderTask?.cancel()
    sessionID = UUID()
    let session = sessionID
    self.directory = directory
    photos = []
    selectedID = nil
    loadState = .loading
    let fileAccess = fileAccess
    let task = Task { try await fileAccess.photos(in: directory) }
    folderTask = task
    do {
      let urls = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      guard sessionID == session else { return }
      try Task.checkCancellation()
      photos = urls.map(PhotoItem.init(fileURL:))
      selectedID = photos.first(where: { $0.id == previousID })?.id ?? photos.first?.id
      loadState = .ready
      folderTask = nil
    } catch {
      guard sessionID == session else { return }
      loadState = .failed(
        error is CancellationError
          ? "Folder loading was cancelled. Reload to try again." : error.localizedDescription)
      folderTask = nil
    }
  }

  public func showSamples() {
    folderTask?.cancel()
    folderTask = nil
    sessionID = UUID()
    directory = nil
    photos = SampleLibrary.photos
    selectedID = photos.first?.id
    loadState = .ready
  }

  public func select(_ id: PhotoItem.ID?) {
    guard let id else {
      selectedID = nil
      return
    }
    guard photos.contains(where: { $0.id == id }) else { return }
    selectedID = id
  }

  public func moveSelection(by offset: Int) {
    guard !photos.isEmpty else { return }
    let current = selectedIndex ?? 0
    let movement = min(max(offset, -current), photos.count - 1 - current)
    selectedID = photos[current + movement].id
  }
}
