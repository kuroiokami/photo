import Foundation

public enum ReviewedCopyScope: String, Codable, CaseIterable, Sendable {
  case all = "All Photos"
  case picks = "Picks Only"
  case nonRejected = "Everything Except Rejects"
  case selection = "Current Selection"
}

public struct ReviewCopyImage: Codable, Sendable {
  public let source: URL
  public let identity: String
  public let decision: CullingDecision
  public let fields: SourceDecisionFields
  public let edit: PhotoEdit
  public let reviewed: Bool
  public let revision: Int
  public let sidecarDigest: String
}
public struct ReviewCopyFile: Codable, Sendable {
  public let source: URL
  public let relative: String
  let fingerprint: FileFingerprint
}
public struct ReviewCopyFamily: Codable, Sendable {
  public let images: [ReviewCopyImage]
  public let files: [ReviewCopyFile]
}
/// Immutable snapshot, not the current filtered screen or mutable review state.
public struct ReviewedCopyPlan: Codable, Sendable, Identifiable {
  public let id: UUID
  public let created: Date
  public let session: SourceReviewSession
  public let scope: ReviewedCopyScope
  public let primary: URL
  public let backup: URL
  public let families: [ReviewCopyFamily]
  public let sourcePhotoCount: Int?
  public let sourceUnreviewedCount: Int?
  public let omittedUnreviewedCount: Int?
  public let otherFileCount: Int?
  public let addedPairImages: [URL]
  public let opposingPairImages: [URL]
  public var images: [ReviewCopyImage] { families.flatMap(\.images) }
  public var files: [ReviewCopyFile] { families.flatMap(\.files) }
  public var bytes: UInt64 { files.reduce(0) { $0 + $1.fingerprint.size } }
}

extension DecisionStore {
  /// One actor turn freezes decisions and ownership without interleaving saves.
  public func freezeSourceReview(
    _ session: SourceReviewSession, images: [URL], acceptMetadataChanges: Bool = false
  ) throws -> [ReviewCopyImage] {
    try images.map { image in
      try Task.checkCancellation()
      let (entry, edit) = try loadSourceReview(session, image: image)
      let identity = try validateReview(session, image: image, identity: entry.identity)
      guard let item = try reviewItem(session.id, identity: identity),
        item.warning == nil || acceptMetadataChanges
      else {
        throw MediaOperationError.invalid(
          "Existing source metadata could not be read safely for \(image.lastPathComponent). Fix it outside Photo before copying this review."
        )
      }
      let data = try sidecarData(image)
      let digest = XMPSidecar.digest(data)
      guard digest == item.baseline || acceptMetadataChanges else {
        throw MediaOperationError.invalid(
          "Source metadata changed for \(image.lastPathComponent). Review the change, then enable Use Updated Source Metadata to keep your review decisions and copy its latest other fields."
        )
      }
      let fields = entry.reviewFields
      let current = try data.map(XMPSidecar.read) ?? CullingDecision()
      let decision = CullingDecision(
        rating: fields.contains(.rating) ? entry.decision.rating : current.rating,
        flag: fields.contains(.flag) ? entry.decision.flag : current.flag)
      return ReviewCopyImage(
        source: image, identity: identity, decision: decision, fields: fields, edit: edit,
        reviewed: entry.reviewed, revision: item.revision ?? 0, sidecarDigest: digest)
    }
  }
  public func changedReviewCount(_ plan: ReviewedCopyPlan) throws -> Int {
    try plan.images.filter {
      try reviewItem(plan.session.id, identity: $0.identity)?.revision ?? 0 != $0.revision
    }.count
  }
}

extension MediaOperations {
  public func planReviewedCopy(
    session: SourceReviewSession, scope: ReviewedCopyScope, selection: [URL] = [],
    selectionIdentities: [URL: String] = [:],
    primary: URL, backup: URL, keepPairs: Bool = true, acceptMetadataChanges: Bool = false,
    store: DecisionStore
  ) async throws -> ReviewedCopyPlan {
    try beginOperation()
    defer { operationInProgress = false }
    let source = try directory(session.root)
    let selection = selection.map(PhotoPath.canonical)
    let selectionIdentities = Dictionary(
      uniqueKeysWithValues: selectionIdentities.map { (PhotoPath.canonical($0.key), $0.value) })
    guard try sourceProtection.session(for: source)?.id == session.id else {
      throw SourceReviewError.sourceChanged
    }
    try validateReviewDestinations(source: source, primary: primary, backup: backup)
    var contents: [URL]
    var otherCount: Int?
    if scope == .selection {
      guard !selection.isEmpty else {
        throw MediaOperationError.invalid(
          "Select at least one source photo before planning a copy.")
      }
      for image in selection { try validateReviewPath(image, root: source) }
      contents = try Set(selection.map { $0.deletingLastPathComponent() }).flatMap { folder in
        try FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
          options: .skipsHiddenFiles
        ).filter {
          let value = try $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
          return value.isRegularFile == true && value.isSymbolicLink != true
        }
      }
      func stem(_ image: URL) -> String {
        image.deletingPathExtension().path.lowercased().precomposedStringWithCanonicalMapping
      }
      let selectedStems = Set(selection.map(stem))
      let peers = contents.filter { PhotoFormats.supports($0) && selectedStems.contains(stem($0)) }
      var required = Set(selection)
      for bucket in Dictionary(grouping: peers, by: stem).values {
        let raws = bucket.filter(PhotoFormats.isRaw)
        let jpegs = bucket.filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
        if keepPairs && raws.count == 1 && jpegs.count == 1 { required.formUnion(raws + jpegs) }
        if raws.count > 1 && !Set(raws).isDisjoint(with: required) {
          let base = raws[0].deletingPathExtension().path.lowercased()
          if contents.contains(where: {
            [base + ".xmp", base + ".acr"].contains($0.path.lowercased())
          }) {
            throw SidecarError.ambiguous
          }
        }
      }
      let companions = Set(
        required.flatMap { image in
          let base = PhotoFormats.isRaw(image) ? image.deletingPathExtension() : image
          return [
            base.appendingPathExtension("xmp").path.lowercased(),
            base.appendingPathExtension("acr").path.lowercased(),
          ]
        })
      contents = contents.filter {
        required.contains($0) || companions.contains($0.path.lowercased())
      }
    } else {
      contents = try ingestFiles(in: source)
      // Counting excluded files is metadata-only; no pixel or RAW decoding.
      let enumerator = FileManager.default.enumerator(
        at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants])
      var count = 0
      while let file = enumerator?.nextObject() as? URL {
        try Task.checkCancellation()
        let value = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if value.isRegularFile == true && value.isSymbolicLink != true { count += 1 }
      }
      otherCount = max(0, count - contents.count)
    }
    contents.sort { $0.path < $1.path }
    let images = contents.filter(PhotoFormats.supports)
    let snapshots = try await store.freezeSourceReview(
      session, images: images, acceptMetadataChanges: acceptMetadataChanges)
    for image in snapshots {
      if let expected = selectionIdentities[image.source], expected != image.identity {
        throw DecisionStoreError.fileChanged
      }
    }
    let byPath = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.source, $0) })
    let selected = Set(selection)
    let included = Set(
      snapshots.filter { image in
        switch scope {
        case .all: true
        case .picks: image.decision.flag == .pick
        case .nonRejected: image.decision.flag != .reject
        case .selection: selected.contains(image.source)
        }
      }.map(\.source))
    if scope == .selection, !selected.isSubset(of: Set(images)) {
      throw DecisionStoreError.fileChanged
    }
    var families: [ReviewCopyFamily] = []
    var added: [URL] = []
    var opposing: [URL] = []
    for folderFiles in Dictionary(grouping: contents, by: { $0.deletingLastPathComponent() }).values
    {
      for family in try PhotoFamily.groups(
        folderFiles.filter(PhotoFormats.supports), contents: folderFiles)
      {
        var members = family.images.filter { included.contains($0) }
        guard !members.isEmpty else { continue }
        if keepPairs, family.images.count > members.count {
          let extra = family.images.filter { !included.contains($0) }
          added += extra
          let flags = Set(members.compactMap { byPath[$0]?.decision.flag })
          opposing += extra.filter { image in
            guard let flag = byPath[image]?.decision.flag else { return false }
            return flag == .reject || (flag == .pick && flags.contains(.reject))
          }
          members = family.images
        }
        let subset = try PhotoFamily.groups(members, contents: folderFiles)
        let files = Array(Set(subset.flatMap(\.files))).sorted { $0.path < $1.path }
        let frozen = try files.map { file -> ReviewCopyFile in
          try validateReviewPath(file, root: source)
          let relative = file.pathComponents.dropFirst(source.pathComponents.count).joined(
            separator: "/")
          return ReviewCopyFile(
            source: file, relative: relative, fingerprint: try FileFingerprint.read(file))
        }
        families.append(ReviewCopyFamily(images: members.compactMap { byPath[$0] }, files: frozen))
      }
    }
    families.sort { ($0.images.first?.source.path ?? "") < ($1.images.first?.source.path ?? "") }
    guard !families.isEmpty else {
      throw MediaOperationError.invalid(
        "No photos match this copy choice. Change the choice or mark some picks.")
    }
    let includedImages = Set(families.flatMap(\.images).map(\.source))
    let allFiles = families.flatMap(\.files)
    guard
      Set(allFiles.map { $0.relative.lowercased().precomposedStringWithCanonicalMapping }).count
        == allFiles.count
    else {
      throw MediaOperationError.invalid(
        "Ambiguous or case-only filenames must be resolved before copying.")
    }
    for file in allFiles {
      for root in [primary, backup] {
        let target = root.appendingPathComponent(file.relative)
        try validateReviewTarget(target)
        if FileManager.default.fileExists(atPath: target.path) {
          _ = try FileFingerprint.read(target)
          // Existing originals may be rechecked during copy; differing bytes are never replaced.
        }
      }
    }
    return ReviewedCopyPlan(
      id: UUID(), created: Date(), session: session, scope: scope,
      primary: primary.standardizedFileURL, backup: backup.standardizedFileURL, families: families,
      sourcePhotoCount: scope == .selection ? nil : snapshots.count,
      sourceUnreviewedCount: scope == .selection ? nil : snapshots.filter { !$0.reviewed }.count,
      omittedUnreviewedCount: scope == .selection
        ? nil : snapshots.filter { !$0.reviewed && !includedImages.contains($0.source) }.count,
      otherFileCount: otherCount, addedPairImages: added.sorted { $0.path < $1.path },
      opposingPairImages: opposing.sorted { $0.path < $1.path })
  }

  func validateReviewPath(_ url: URL, root: URL) throws {
    guard url.isFileURL, Self.contains(root, url), PhotoPath.canonical(url).path != root.path
    else {
      throw SourceReviewError.sourceChanged
    }
    var ancestor = url
    while PhotoPath.canonical(ancestor).path != root.path {
      guard !ancestor.lastPathComponent.hasPrefix("."),
        (try? FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path)) == nil
      else {
        throw SourceReviewError.sourceChanged
      }
      ancestor.deleteLastPathComponent()
    }
    _ = try FileFingerprint.read(url)
  }
  func validateReviewTarget(_ target: URL) throws {
    try sourceProtection.withWritable([target]) {}
    for component in sequence(
      first: target.standardizedFileURL,
      next: { $0.path == "/" ? nil : $0.deletingLastPathComponent() })
    {
      if let destination = try? FileManager.default.destinationOfSymbolicLink(
        atPath: component.path)
      {
        if ["/var": "private/var", "/tmp": "private/tmp", "/etc": "private/etc"][component.path]
          == destination
        {
          continue
        }
        throw MediaOperationError.invalid(
          "A copy destination contains a symbolic link. Choose its actual folder instead.")
      }
    }
  }
  func validateReviewDestinations(source: URL, primary: URL, backup: URL) throws {
    for pair in [(source, primary), (source, backup), (primary, backup)] {
      guard !Self.contains(pair.0, pair.1), !Self.contains(pair.1, pair.0) else {
        throw MediaOperationError.invalid(
          "Source, photo and backup folders must be separate, non-overlapping folders.")
      }
    }
    try validateReviewTarget(primary)
    try validateReviewTarget(backup)
  }
}
