import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceState {
  public let photos: [PhotoItem]
  public private(set) var selectedID: PhotoItem.ID?

  public var selectedPhoto: PhotoItem? {
    photos.first { $0.id == selectedID }
  }

  public init(photos: [PhotoItem] = SampleLibrary.photos) {
    self.photos = photos
    selectedID = photos.first?.id
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
    let current = photos.firstIndex { $0.id == selectedID } ?? 0
    // Clamp before addition so even extreme offsets cannot overflow.
    let movement = min(max(offset, -current), photos.count - 1 - current)
    selectedID = photos[current + movement].id
  }
}
