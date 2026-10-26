import Foundation

/// Read-only folder enumeration on an actor executor, away from the main actor.
public actor LocalPhotoFileAccess: PhotoFileAccess {
  public init() {}

  public func photos(in directory: URL) async throws -> [URL] {
    try inventory(in: directory, includingSubfolders: false)
  }

  public func photos(in directory: URL, includingSubfolders: Bool) async throws -> [URL] {
    try inventory(in: directory, includingSubfolders: includingSubfolders)
  }

  private func inventory(in directory: URL, includingSubfolders: Bool) throws -> [URL] {
    try Task.checkCancellation()
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
    guard values.isDirectory == true else {
      throw CocoaError(
        .fileReadUnknown,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Choose a folder containing JPEG, PNG, Sony, Canon, or Olympus RAW images."
        ])
    }
    let keys: Set<URLResourceKey> = [
      .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .isPackageKey,
    ]
    var contents: [URL] = []
    if includingSubfolders {
      var failure: (any Error)?
      guard
        let iterator = FileManager.default.enumerator(
          at: directory, includingPropertiesForKeys: Array(keys),
          options: [.skipsHiddenFiles, .skipsPackageDescendants],
          errorHandler: { _, error in
            failure = error
            return false
          })
      else {
        throw CocoaError(.fileReadUnknown)
      }
      for case let url as URL in iterator {
        try Task.checkCancellation()
        let attributes = try url.resourceValues(forKeys: keys)
        if attributes.isSymbolicLink == true || attributes.isPackage == true {
          iterator.skipDescendants()
          continue
        }
        if attributes.isRegularFile == true { contents.append(url) }
      }
      if let failure { throw failure }
    } else {
      contents = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
    }
    var photos: [URL] = []
    for url in contents {
      try Task.checkCancellation()
      guard PhotoFormats.supports(url) else { continue }
      // A file can disappear during enumeration. Keep its place so its tile can
      // explain the read failure; never follow symbolic links out of the folder.
      if let attributes = try? url.resourceValues(forKeys: keys) {
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { continue }
      }
      photos.append(url)
    }
    photos.sort {
      let order = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
      return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
    }
    try Task.checkCancellation()
    return photos
  }
}
