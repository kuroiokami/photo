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
  public private(set) var selectedIndex: Int?
  @ObservationIgnored private var indicesByID: [PhotoItem.ID: Int]
  public private(set) var directory: URL?
  public private(set) var loadState: FolderLoadState = .ready
  public private(set) var sessionID = UUID()
  @ObservationIgnored private let fileAccess: any PhotoFileAccess
  @ObservationIgnored private var folderTask: Task<LoadedPhotos, Error>?

  public var selectedPhoto: PhotoItem? { selectedIndex.map { photos[$0] } }
  public var selectedID: PhotoItem.ID? { selectedPhoto?.id }
  public var title: String { directory?.lastPathComponent ?? "Sample collection" }

  public init(
    photos: [PhotoItem] = SampleLibrary.photos,
    fileAccess: any PhotoFileAccess = LocalPhotoFileAccess()
  ) {
    self.photos = photos
    self.fileAccess = fileAccess
    indicesByID = Self.makeIndex(photos)
    selectedIndex = photos.isEmpty ? nil : 0
  }

  public func openFolder(_ directory: URL) async {
    let previousID = self.directory == directory ? selectedID : nil
    folderTask?.cancel()
    sessionID = UUID()
    let session = sessionID
    self.directory = directory
    selectedIndex = nil
    photos = []
    indicesByID = [:]
    loadState = .loading
    let fileAccess = fileAccess
    // Build models and the lookup table away from the main actor as well as IO.
    let task = Task.detached(priority: .userInitiated) {
      let urls = try await fileAccess.photos(in: directory)
      try Task.checkCancellation()
      let photos = urls.map(PhotoItem.init(fileURL:))
      let indices = Self.makeIndex(photos)
      try Task.checkCancellation()
      return LoadedPhotos(photos: photos, indices: indices)
    }
    folderTask = task
    do {
      let loaded = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      guard sessionID == session else { return }
      try Task.checkCancellation()
      photos = loaded.photos
      indicesByID = loaded.indices
      selectedIndex = previousID.flatMap { indicesByID[$0] } ?? (photos.isEmpty ? nil : 0)
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
    selectedIndex = nil
    photos = SampleLibrary.photos
    indicesByID = Self.makeIndex(photos)
    selectedIndex = photos.isEmpty ? nil : 0
    loadState = .ready
  }

  public func select(_ id: PhotoItem.ID?) {
    guard let id else {
      selectedIndex = nil
      return
    }
    guard let index = indicesByID[id] else { return }
    selectedIndex = index
  }

  public func moveSelection(by offset: Int) {
    guard !photos.isEmpty else { return }
    let current = selectedIndex ?? 0
    let movement = min(max(offset, -current), photos.count - 1 - current)
    selectedIndex = current + movement
  }

  private struct LoadedPhotos: Sendable {
    let photos: [PhotoItem]
    let indices: [PhotoItem.ID: Int]
  }

  private nonisolated static func makeIndex(_ photos: [PhotoItem]) -> [PhotoItem.ID: Int] {
    var indices: [PhotoItem.ID: Int] = [:]
    indices.reserveCapacity(photos.count)
    for (index, photo) in photos.enumerated() where indices[photo.id] == nil {
      indices[photo.id] = index
    }
    return indices
  }

}
