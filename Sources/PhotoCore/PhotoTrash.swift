import Foundation

public struct PhotoTrashPlan: Identifiable, Sendable {
  public let id = UUID()
  public let images: [URL]
  public let companions: [URL]
  public let retainedSharedCompanions: Int
  fileprivate let inventories: [URL: Set<URL>]
  fileprivate let names: [URL: String]
  public func displayName(for url: URL) -> String { names[url] ?? url.lastPathComponent }
  fileprivate let files: [(url: URL, fingerprint: FileFingerprint)]
}

public struct PhotoTrashResult: Sendable {
  public let moved: [URL]
  public let error: String?
}

/// Only an explicit confirmed plan can move files. Never fall back to permanent deletion.
public actor PhotoTrash {
  private let store: DecisionStore
  private let move: @Sendable (URL) throws -> Void
  public init(
    store: DecisionStore,
    move: @escaping @Sendable (URL) throws -> Void = { url in
      try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
  ) {
    self.store = store
    self.move = move
  }

  public func prepare(images: [URL: String], folder: URL, includingSubfolders: Bool = false)
    async throws -> PhotoTrashPlan
  {
    guard !images.isEmpty else {
      throw MediaOperationError.invalid("Select photos to move to Trash.")
    }
    let folder = PhotoPath.canonical(folder)
    if includingSubfolders {
      let groups = Dictionary(
        grouping: images, by: { PhotoPath.canonical($0.key.deletingLastPathComponent()) })
      var plans: [PhotoTrashPlan] = []
      for parent in groups.keys.sorted(by: { $0.path < $1.path }) {
        guard parent.pathComponents.starts(with: folder.pathComponents) else {
          throw DecisionStoreError.fileChanged
        }
        let entries = Dictionary(
          uniqueKeysWithValues: groups[parent, default: []].map { ($0.key, $0.value) })
        plans.append(try await prepare(images: entries, folder: parent))
      }
      // Validate every image before moving any; sidecars stay after all images.
      let files =
        plans.flatMap { Array($0.files.prefix($0.images.count)) }
        + plans.flatMap { Array($0.files.dropFirst($0.images.count)) }
      return PhotoTrashPlan(
        images: plans.flatMap(\.images), companions: plans.flatMap(\.companions),
        retainedSharedCompanions: plans.reduce(0) { $0 + $1.retainedSharedCompanions },
        inventories: Dictionary(
          uniqueKeysWithValues: plans.flatMap { $0.inventories.map { ($0.key, $0.value) } }),
        names: Dictionary(
          uniqueKeysWithValues: files.map {
            (
              $0.url,
              PhotoPath.canonical($0.url).pathComponents.dropFirst(folder.pathComponents.count)
                .joined(separator: "/")
            )
          }), files: files)
    }
    let selected = Set(images.keys.map(PhotoPath.canonical))
    let contents = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    let photos = contents.filter { PhotoFormats.supports($0) }
    // Conservative case-folded ownership retains ambiguous/shared sidecars on
    // both case-sensitive and case-insensitive volumes. Build once, not per photo.
    func name(_ url: URL) -> String { url.lastPathComponent.lowercased() }
    let xmpOwners = Dictionary(grouping: photos, by: { name(XMPSidecar.url(for: $0)) })
    let rawOwners = Dictionary(
      grouping: photos.filter(PhotoFormats.isRaw),
      by: {
        name($0.deletingPathExtension())
      })
    let sidecars = Dictionary(
      grouping: contents.filter {
        ["xmp", "acr"].contains($0.pathExtension.lowercased())
      }, by: { name($0) })
    var companions: Set<URL> = []
    var shared: Set<URL> = []
    var files: [(url: URL, fingerprint: FileFingerprint)] = []
    for (image, identity) in images.sorted(by: { $0.key.path < $1.key.path }) {
      try Task.checkCancellation()
      let fingerprint = try FileFingerprint.read(image)
      guard PhotoPath.canonical(image.deletingLastPathComponent()) == folder,
        PhotoFormats.supports(image), try await store.key(for: image) == identity,
        try FileFingerprint.read(image) == fingerprint
      else { throw DecisionStoreError.fileChanged }
      try store.sourceProtection.withWritable([image]) {}
      files.append((image, fingerprint))
      let xmp = XMPSidecar.url(for: image)
      let acr = image.deletingPathExtension().appendingPathExtension("acr")
      let candidates =
        (sidecars[name(xmp)] ?? [])
        + (PhotoFormats.isRaw(image) ? sidecars[name(acr)] ?? [] : [])
      for candidate in candidates {
        let owners =
          candidate.pathExtension.lowercased() == "xmp"
          ? xmpOwners[name(candidate)] ?? []
          : rawOwners[name(image.deletingPathExtension())] ?? []
        if owners.contains(where: { !selected.contains(PhotoPath.canonical($0)) }) {
          shared.insert(candidate)
        } else {
          companions.insert(candidate)
        }
      }
    }
    for url in companions.sorted(by: { $0.path < $1.path }) {
      try store.sourceProtection.withWritable([url]) {}
      files.append((url, try FileFingerprint.read(url)))
    }
    return PhotoTrashPlan(
      images: files.prefix(images.count).map(\.url),
      companions: companions.sorted { $0.path < $1.path }, retainedSharedCompanions: shared.count,
      inventories: [folder: Set(photos.map(PhotoPath.canonical))],
      names: Dictionary(uniqueKeysWithValues: files.map { ($0.url, $0.url.lastPathComponent) }),
      files: files)
  }

  private func inventory(in folder: URL) throws -> Set<URL> {
    Set(
      try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
      )
      .filter(PhotoFormats.supports).map(PhotoPath.canonical))
  }

  public func execute(_ plan: PhotoTrashPlan) -> PhotoTrashResult {
    var moved: [URL] = []
    do {
      for (folder, expected) in plan.inventories {
        guard try inventory(in: folder) == expected else {
          throw MediaOperationError.invalid(
            "Photos in these folders changed. Review the Trash list again.")
        }
      }
      // Validate the complete snapshot before the first move, then each file
      // again inside the source-protection boundary immediately before moving.
      for file in plan.files {
        try Task.checkCancellation()
        try store.sourceProtection.withWritable([file.url]) {
          guard try FileFingerprint.read(file.url) == file.fingerprint else {
            throw DecisionStoreError.fileChanged
          }
        }
      }
      for (index, file) in plan.files.enumerated() {
        try Task.checkCancellation()
        if index == plan.images.count {
          let removed = Set(plan.images.map(PhotoPath.canonical))
          for (folder, expected) in plan.inventories {
            guard try inventory(in: folder) == expected.subtracting(removed) else {
              throw MediaOperationError.invalid(
                "Photos arrived while moving files. Their sidecars were left untouched.")
            }
          }
        }
        try store.sourceProtection.withWritable([file.url]) {
          guard try FileFingerprint.read(file.url) == file.fingerprint else {
            throw DecisionStoreError.fileChanged
          }
          try move(file.url)
        }
        moved.append(file.url)
      }
      return PhotoTrashResult(moved: moved, error: nil)
    } catch {
      return PhotoTrashResult(moved: moved, error: error.localizedDescription)
    }
  }
}
