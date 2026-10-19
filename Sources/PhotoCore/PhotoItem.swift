import Foundation

public struct PhotoItem: Identifiable, Hashable, Sendable {
  public let id: String
  public let filename: String
  public let resourceName: String
  public let fileURL: URL?

  public init(id: String, filename: String, resourceName: String) {
    self.id = id
    self.filename = filename
    self.resourceName = resourceName
    fileURL = nil
  }

  public init(fileURL: URL) {
    self.fileURL = fileURL
    id = fileURL.standardizedFileURL.path
    filename = fileURL.lastPathComponent
    resourceName = ""
  }
}

public enum SampleLibrary {
  public static let photos: [PhotoItem] = [
    PhotoItem(id: "dawn", filename: "Dawn.png", resourceName: "dawn"),
    PhotoItem(id: "coast", filename: "Coast.png", resourceName: "coast"),
    PhotoItem(id: "dusk", filename: "Dusk.png", resourceName: "dusk"),
  ]
}
