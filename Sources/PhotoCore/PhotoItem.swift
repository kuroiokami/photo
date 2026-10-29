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
    // Foundation paths may be foreign UTF-16 storage. Repeated Set/Dictionary
    // access otherwise re-enters the bridged Unicode hashing path. Copy once
    // without changing any scalar, spelling, normalization or filesystem URL.
    var identity = fileURL.standardizedFileURL.path
    identity.makeContiguousUTF8()
    id = identity
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
