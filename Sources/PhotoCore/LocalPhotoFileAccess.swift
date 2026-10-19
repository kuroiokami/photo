import Foundation

/// Shallow, read-only enumeration on an actor executor, away from the main actor.
public actor LocalPhotoFileAccess: PhotoFileAccess {
  public init() {}

  public func photos(in directory: URL) async throws -> [URL] {
    try Task.checkCancellation()
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
    guard values.isDirectory == true else {
      throw CocoaError(
        .fileReadUnknown,
        userInfo: [NSLocalizedDescriptionKey: "Choose a folder containing JPEG or PNG images."])
    }
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
    let contents = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
    var photos: [URL] = []
    for url in contents {
      try Task.checkCancellation()
      guard ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) else { continue }
      // A file can disappear during enumeration. Keep its place so its tile can
      // explain the read failure; never follow symbolic links out of the folder.
      if let attributes = try? url.resourceValues(forKeys: keys) {
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { continue }
      }
      photos.append(url)
    }
    photos.sort {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
    try Task.checkCancellation()
    return photos
  }
}
