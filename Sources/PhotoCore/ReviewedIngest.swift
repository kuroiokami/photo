import Darwin
import Foundation

struct ReviewCopyEvent: Codable {
  let relative: String
  let sha256: String
  let verified: Bool
  var derivedMetadata: Bool? = nil
}
public struct ReviewedCopyReport: Sendable {
  public let photoCount: Int
  public let fileCount: Int
  public let pendingMetadata: Int
  public let pendingMetadataImages: [URL]
  public let preservedDecisions: Int
  public let changedSourceReviews: Int
  public let sameVolumeBackup: Bool
  public let firstFolder: URL
}

extension MediaOperations {
  func reviewJournalURL(_ id: UUID) -> URL {
    journalDirectory.appendingPathComponent("review-copy-\(id.uuidString).json")
  }
  private func reviewEventsURL(_ id: UUID) -> URL {
    journalDirectory.appendingPathComponent("review-copy-\(id.uuidString).events")
  }
  public func savedReviewedCopies() throws -> [ReviewedCopyPlan] {
    guard FileManager.default.fileExists(atPath: journalDirectory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: journalDirectory, includingPropertiesForKeys: nil
    )
    .filter { $0.lastPathComponent.hasPrefix("review-copy-") && $0.pathExtension == "json" }
    .map { url in
      _ = try FileFingerprint.read(url)
      return try JSONDecoder().decode(ReviewedCopyPlan.self, from: Data(contentsOf: url))
    }.sorted { $0.created > $1.created }
  }
  private func appendReviewEvent(_ event: ReviewCopyEvent, to url: URL) throws {
    try validateReviewTarget(url)
    try sourceProtection.withWritable([url]) {
      if FileManager.default.fileExists(atPath: url.path) {
        _ = try FileFingerprint.read(url)
      } else {
        try Data().write(to: url, options: .withoutOverwriting)
      }
      var data = try JSONEncoder().encode(event)
      data.append(0x0A)
      let handle = try FileHandle(forUpdating: url)
      defer { try? handle.close() }
      let end = try handle.seekToEnd()
      if end > 0 {
        try handle.seek(toOffset: end - 1)
        if try handle.read(upToCount: 1)?.last != 0x0A {
          // Remove only an unacknowledged torn final event before appending.
          var cursor = end
          var boundary: UInt64 = 0
          while cursor > 0 {
            let start = cursor > 65_536 ? cursor - 65_536 : 0
            try handle.seek(toOffset: start)
            let tail = try handle.read(upToCount: Int(cursor - start)) ?? Data()
            if let newline = tail.lastIndex(of: 0x0A) {
              boundary = start + UInt64(tail.distance(from: tail.startIndex, to: newline)) + 1
              break
            }
            cursor = start
          }
          try handle.truncate(atOffset: boundary)
        }
      }
      _ = try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.synchronize()
      try syncReviewDirectory(url.deletingLastPathComponent())
    }
  }
  private func syncReviewDirectory(_ folder: URL) throws {
    let descriptor = Darwin.open(folder.path, O_RDONLY)
    guard descriptor >= 0 else {
      throw MediaOperationError.invalid(
        "The copy record could not be saved safely. Resume the saved copy to retry.")
    }
    defer { Darwin.close(descriptor) }
    guard fsync(descriptor) == 0 else {
      throw MediaOperationError.invalid(
        "The copy record could not be synchronized. Resume the saved copy to retry.")
    }
  }
  private func readReviewEvents(_ url: URL) throws -> [String: ReviewCopyEvent] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    _ = try FileFingerprint.read(url)
    let data = try Data(contentsOf: url)
    var result: [String: ReviewCopyEvent] = [:]
    // An interrupted final append is unacknowledged, so reverify that file.
    let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
    for (index, line) in lines.enumerated() {
      do {
        let event = try JSONDecoder().decode(ReviewCopyEvent.self, from: Data(line))
        if let previous = result[event.relative], previous.sha256 != event.sha256 {
          throw DecisionStoreError.fileChanged
        }
        result[event.relative] = event
      } catch {
        if index == lines.count - 1 && data.last != 0x0A { break }
        throw error
      }
    }
    return result
  }

  /// Every retry uses the exact saved plan. Later source decisions are reported,
  /// never silently substituted; later destination work is protected by receipts.
  public func copyReviewed(
    _ plan: ReviewedCopyPlan, store: DecisionStore, includeOpposingPairs: Bool = false,
    progress: @Sendable (IngestProgress) async -> Void = { _ in }
  ) async throws -> ReviewedCopyReport {
    try beginOperation()
    defer { operationInProgress = false }
    guard plan.opposingPairImages.isEmpty || includeOpposingPairs else {
      throw MediaOperationError.invalid(
        "A RAW+JPEG companion has an opposing flag. Confirm including those companions, or prepare a new list with Keep RAW+JPEG Pairs Together off."
      )
    }
    guard try sourceProtection.session(for: plan.session.root)?.id == plan.session.id else {
      throw SourceReviewError.sourceChanged
    }
    try validateReviewDestinations(
      source: plan.session.root, primary: plan.primary, backup: plan.backup)
    let allFiles = plan.files
    let allImages = plan.images
    guard !allImages.isEmpty, !allFiles.isEmpty,
      Set(allFiles.map(\.relative)).count == allFiles.count
    else {
      throw MediaOperationError.invalid("The saved copy list is invalid. Prepare a new list.")
    }
    for file in allFiles {
      try validateReviewPath(file.source, root: plan.session.root)
      let relative = file.source.pathComponents.dropFirst(plan.session.root.pathComponents.count)
        .joined(separator: "/")
      guard file.relative == relative, try FileFingerprint.read(file.source) == file.fingerprint
      else {
        throw DecisionStoreError.fileChanged
      }
    }
    try await store.validateReviewCopySources(plan, images: allImages)
    try safeDirectory(journalDirectory)
    let journal = reviewJournalURL(plan.id)
    if FileManager.default.fileExists(atPath: journal.path) {
      _ = try FileFingerprint.read(journal)
      let saved = try Data(contentsOf: journal)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let prior = try JSONDecoder().decode(ReviewedCopyPlan.self, from: saved)
      guard try encoder.encode(prior) == encoder.encode(plan) else {
        throw MediaOperationError.invalid(
          "The saved copy list differs. Resume the original list instead.")
      }
    } else {
      try durableJSON(plan, at: journal)
      try syncReviewDirectory(journalDirectory)
    }
    var events = try readReviewEvents(reviewEventsURL(plan.id))
    try safeDirectory(plan.primary)
    try safeDirectory(plan.backup)
    for root in [plan.primary, plan.backup] {
      let destinationPlan = root.appendingPathComponent(".photo-review-\(plan.id.uuidString).json")
      try validateReviewTarget(destinationPlan)
      if FileManager.default.fileExists(atPath: destinationPlan.path) {
        _ = try FileFingerprint.read(destinationPlan)
        let saved = try JSONDecoder().decode(
          ReviewedCopyPlan.self, from: Data(contentsOf: destinationPlan))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(saved) == encoder.encode(plan) else {
          throw MediaOperationError.invalid(
            "A destination copy record changed. Its files were left untouched.")
        }
      } else {
        try durableJSON(plan, at: destinationPlan)
      }
    }
    var primaryManifest = try readManifest(
      plan.primary.appendingPathComponent(".photo-ingest.json"))
    var backupManifest = try readManifest(plan.backup.appendingPathComponent(".photo-ingest.json"))
    var complete = 0
    var pendingImages: [URL] = []
    var preserved = 0
    for family in plan.families {
      try Task.checkCancellation()
      try await store.validateReviewCopySources(plan, images: family.images)
      let received = try await store.hasReviewCopyReceipts(plan, family: family)
      var expectedImages: [URL: FileFingerprint] = [:]
      let files = family.files.sorted {
        if PhotoFormats.supports($0.source) != PhotoFormats.supports($1.source) {
          return !PhotoFormats.supports($0.source)
        }
        return $0.relative < $1.relative
      }
      for file in files {
        try Task.checkCancellation()
        try validateReviewPath(file.source, root: plan.session.root)
        guard try FileFingerprint.read(file.source) == file.fingerprint else {
          throw DecisionStoreError.fileChanged
        }
        let hash = try Self.checksum(file.source)
        if let prior = events[file.relative], prior.sha256 != hash {
          throw DecisionStoreError.fileChanged
        }
        if events[file.relative] == nil {
          let event = ReviewCopyEvent(relative: file.relative, sha256: hash, verified: false)
          try appendReviewEvent(event, to: reviewEventsURL(plan.id))
          events[file.relative] = event
        }
        let targets = [plan.primary, plan.backup].map { $0.appendingPathComponent(file.relative) }
        for target in targets {
          try validateReviewTarget(target)
          if !PhotoFormats.supports(file.source), events[file.relative]?.verified == true, received
          {
            // Receipts prove initial byte verification. Keep subsequent destination
            // metadata, including deliberate deletion, rather than recopying it.
            if FileManager.default.fileExists(atPath: target.path) {
              _ = try FileFingerprint.read(target)
            }
          } else {
            _ = try copyVerified(file.source, to: target, expected: hash)
          }
          if PhotoFormats.supports(file.source) {
            expectedImages[target] = try FileFingerprint.read(target)
          }
        }
        guard try FileFingerprint.read(file.source) == file.fingerprint else {
          throw DecisionStoreError.fileChanged
        }
        let event = ReviewCopyEvent(
          relative: file.relative, sha256: hash, verified: true,
          derivedMetadata: !PhotoFormats.supports(file.source) && received ? true : nil)
        for root in [plan.primary, plan.backup] {
          try appendReviewEvent(
            event, to: root.appendingPathComponent(".photo-review-\(plan.id.uuidString).jsonl"))
        }
        try appendReviewEvent(event, to: reviewEventsURL(plan.id))
        events[file.relative] = event
        let record = IngestRecord(
          relativePath: file.relative, originalFilename: file.source.lastPathComponent,
          source: file.source, sha256: hash, verifiedDestinations: targets)
        primaryManifest.records[file.relative] = record
        backupManifest.records[file.relative] = record
        complete += 1
      }
      try await store.validateReviewCopySources(plan, images: family.images)
      try await store.installReviewCopy(plan, family: family, expectedImages: expectedImages)
      let result = try await store.synchronizeReviewCopy(plan, family: family)
      pendingImages += result.pendingImages
      preserved += result.preserved
      let arrivals = family.images.map { image in
        plan.primary.appendingPathComponent(
          image.source.pathComponents.dropFirst(plan.session.root.pathComponents.count).joined(
            separator: "/"))
      }
      await progress(
        IngestProgress(
          completed: complete, total: allFiles.count,
          filename: family.images.first?.source.lastPathComponent ?? "",
          directory: arrivals.first?.deletingLastPathComponent(), verifiedImages: arrivals))
    }
    // Append-only provenance above is durable before publication. Materialize the
    // ordinary ingest manifests once, avoiding a growing JSON rewrite per photo.
    try durableJSON(primaryManifest, at: plan.primary.appendingPathComponent(".photo-ingest.json"))
    try durableJSON(backupManifest, at: plan.backup.appendingPathComponent(".photo-ingest.json"))
    let a =
      try FileManager.default.attributesOfItem(atPath: plan.primary.path)[.systemNumber]
      as? NSNumber
    let b =
      try FileManager.default.attributesOfItem(atPath: plan.backup.path)[.systemNumber] as? NSNumber
    let first = allImages[0].source.pathComponents.dropFirst(
      plan.session.root.pathComponents.count
    ).joined(separator: "/")
    return ReviewedCopyReport(
      photoCount: allImages.count, fileCount: allFiles.count, pendingMetadata: pendingImages.count,
      pendingMetadataImages: pendingImages,
      preservedDecisions: preserved, changedSourceReviews: try await store.changedReviewCount(plan),
      sameVolumeBackup: a != nil && a == b,
      firstFolder: plan.primary.appendingPathComponent(first).deletingLastPathComponent())
  }
}
