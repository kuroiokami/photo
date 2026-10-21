import CryptoKit
import Darwin
import Foundation

public enum MediaOperationError: LocalizedError {
  case invalid(String)
  public var errorDescription: String? {
    if case .invalid(let message) = self { message } else { nil }
  }
}

public struct FileFingerprint: Codable, Equatable, Sendable {
  let device: UInt64
  let inode: UInt64
  let size: UInt64
  let modified: Date
  static func read(_ url: URL) throws -> Self {
    let a = try FileManager.default.attributesOfItem(atPath: url.path)
    guard a[.type] as? FileAttributeType == .typeRegular else {
      throw MediaOperationError.invalid(
        "Only regular files are supported; symbolic links are excluded.")
    }
    return Self(
      device: (a[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
      inode: (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
      size: (a[.size] as? NSNumber)?.uint64Value ?? 0,
      modified: a[.modificationDate] as? Date ?? .distantPast)
  }
}

public struct IngestProgress: Sendable {
  public let completed: Int
  public let total: Int
  public let filename: String
  public var directory: URL? = nil
  /// Published only after both destinations and every family companion are verified.
  public var verifiedImages: [URL] = []
}
public struct IngestReport: Sendable {
  public let fileCount: Int
  public let copiedCount: Int
  public let alreadyVerifiedCount: Int
  public let destination: URL
  public let sameVolumeBackup: Bool
  public let preservedMetadataCount: Int
}
struct IngestRecord: Codable {
  let relativePath: String
  let originalFilename: String
  let source: URL
  let sha256: String
  let verifiedDestinations: [URL]
}
struct IngestManifest: Codable {
  var records: [String: IngestRecord] = [:]
}

public struct RenameEntry: Codable, Sendable, Identifiable {
  public var id: String { original.path }
  public let original: URL
  public let destination: URL
  let staging: URL
  let recovery: URL
  let fingerprint: FileFingerprint
  let sha256: String
}
public struct RenamePlan: Codable, Sendable {
  public let id: UUID
  public let created: Date
  public let entries: [RenameEntry]
  public let nextSequence: Int
  var phase = "planned"
}

/// A single actor serializes ingest, naming and recovery. Original image bytes
/// are read, never rewritten; rename changes directory entries only.
public actor MediaOperations {
  public static let shared = MediaOperations()
  let journalDirectory: URL
  let sourceProtection: SourceProtection
  var operationInProgress = false
  func beginOperation() throws {
    guard !operationInProgress else {
      throw MediaOperationError.invalid(
        "Another file operation is running. Wait for it to finish before starting this operation.")
    }
    operationInProgress = true
  }
  public init(journalDirectory: URL? = nil, sourceProtection: SourceProtection = .shared) {
    self.sourceProtection = sourceProtection
    self.journalDirectory =
      journalDirectory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Photo/Operations")
  }

  public static func checksum(_ url: URL) throws -> String {
    _ = try FileFingerprint.read(url)
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var digest = SHA256()
    while true {
      try Task.checkCancellation()
      guard let data = try file.read(upToCount: 1_048_576), !data.isEmpty else { break }
      digest.update(data: data)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// Recurses for card ingest only; ordinary browsing stays shallow.
  public func ingest(
    source: URL, primary: URL, backup: URL,
    progress: @Sendable (IngestProgress) async -> Void = { _ in }
  ) async throws -> IngestReport {
    try beginOperation()
    defer { operationInProgress = false }
    let source = try directory(source)
    do { try sourceProtection.withWritable([source]) {} } catch SourceReviewError.protectedSource {
      throw SourceReviewError.copyNotReady
    }
    try sourceProtection.withWritable([primary, backup]) {}
    var primary = primary.standardizedFileURL
    var backup = backup.standardizedFileURL
    for pair in [(source, primary), (source, backup), (primary, backup)] {
      guard !Self.contains(pair.0, pair.1), !Self.contains(pair.1, pair.0) else {
        throw MediaOperationError.invalid(
          "Source and destinations must be separate, non-overlapping folders.")
      }
    }
    try safeDirectory(primary)
    try safeDirectory(backup)
    primary = Self.canonical(primary)
    backup = Self.canonical(backup)
    let manifestURL = primary.appendingPathComponent(".photo-ingest.json")
    var manifest = try readManifest(manifestURL)
    var backupManifest = try readManifest(backup.appendingPathComponent(".photo-ingest.json"))
    let files = try ingestFiles(in: source)
    let families = Dictionary(grouping: files, by: { $0.deletingLastPathComponent() }).values
      .flatMap { contents in
        let images = contents.filter(PhotoFormats.supports)
        return (try? PhotoFamily.groups(images, contents: contents))
          ?? images.map { PhotoFamily(primary: $0, images: [$0], sidecars: []) }
      }
    var remaining = families.map { $0.files.count }
    var dependencies: [URL: [Int]] = [:]
    for (index, family) in families.enumerated() {
      for file in family.files { dependencies[file, default: []].append(index) }
    }
    var publishedTargets: [URL: URL] = [:]
    var copied = 0
    var skipped = 0
    var preservedMetadata = 0
    for (index, file) in files.enumerated() {
      try Task.checkCancellation()
      let fingerprint = try FileFingerprint.read(file)
      let relative = file.pathComponents.dropFirst(source.pathComponents.count).joined(
        separator: "/")
      let hash = try Self.checksum(file)
      let known = manifest.records[relative]
      let targets = [primary, backup].map { root in
        known?.sha256 == hash
          ? known?.verifiedDestinations.first(where: { Self.contains(root, $0) })
            ?? root.appendingPathComponent(relative) : root.appendingPathComponent(relative)
      }
      for target in targets {
        if FileManager.default.fileExists(atPath: target.path) {
          _ = try FileFingerprint.read(target)
        }
        if ["xmp", "acr"].contains(file.pathExtension.lowercased()), known?.sha256 == hash,
          FileManager.default.fileExists(atPath: target.path), try Self.checksum(target) != hash
        {
          preservedMetadata += 1
        } else if try copyVerified(file, to: target, expected: hash) {
          copied += 1
        } else {
          skipped += 1
        }
      }
      guard try FileFingerprint.read(file) == fingerprint else {
        throw MediaOperationError.invalid(
          "A source file changed during ingest. Retry after capture has finished.")
      }
      manifest.records[relative] = IngestRecord(
        relativePath: relative, originalFilename: file.lastPathComponent,
        source: file, sha256: hash, verifiedDestinations: targets)
      try durableJSON(manifest, at: manifestURL)
      backupManifest.records[relative] = manifest.records[relative]
      try durableJSON(backupManifest, at: backup.appendingPathComponent(".photo-ingest.json"))
      publishedTargets[file] = targets[0]
      var arrivals: [URL] = []
      for family in dependencies[file] ?? [] {
        remaining[family] -= 1
        if remaining[family] == 0 {
          arrivals += families[family].images.compactMap { publishedTargets[$0] }
        }
      }
      await progress(
        IngestProgress(
          completed: index + 1, total: files.count, filename: file.lastPathComponent,
          directory: arrivals.first?.deletingLastPathComponent(), verifiedImages: arrivals))
    }
    let a =
      try FileManager.default.attributesOfItem(atPath: primary.path)[.systemNumber] as? NSNumber
    let b =
      try FileManager.default.attributesOfItem(atPath: backup.path)[.systemNumber] as? NSNumber
    return IngestReport(
      fileCount: files.count, copiedCount: copied, alreadyVerifiedCount: skipped,
      destination: primary, sameVolumeBackup: a != nil && a == b,
      preservedMetadataCount: preservedMetadata)
  }

  public func prepareHandoff(
    images: [URL], destination: URL,
    progress: @Sendable (IngestProgress) async -> Void = { _ in }
  ) async throws -> Int {
    try beginOperation()
    defer { operationInProgress = false }
    guard !images.isEmpty else {
      throw MediaOperationError.invalid("There are no eligible photos to copy.")
    }
    for image in images {
      do { try sourceProtection.withWritable([image]) {} } catch SourceReviewError.protectedSource {
        throw SourceReviewError.copyNotReady
      }
      guard !Self.contains(image.deletingLastPathComponent(), destination),
        !Self.contains(destination, image.deletingLastPathComponent())
      else {
        throw MediaOperationError.invalid(
          "Choose a handoff folder outside the source photo folder.")
      }
    }
    var files = Set(images)
    var companions: [URL: [String: [URL]]] = [:]
    for folder in Set(images.map { $0.deletingLastPathComponent() }) {
      let peers = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
      companions[folder] = Dictionary(
        grouping: peers.filter { ["xmp", "acr"].contains($0.pathExtension.lowercased()) }
      ) { $0.lastPathComponent.lowercased().precomposedStringWithCanonicalMapping }
    }
    for image in images {
      let base = PhotoFormats.isRaw(image) ? image.deletingPathExtension() : image
      let expected = [
        base.appendingPathExtension("xmp").lastPathComponent,
        base.appendingPathExtension("acr").lastPathComponent,
      ]
      for name in expected {
        for peer in companions[image.deletingLastPathComponent()]?[
          name.lowercased().precomposedStringWithCanonicalMapping] ?? []
        {
          _ = try FileFingerprint.read(peer)
          files.insert(peer)
        }
      }
    }
    let ordered = files.sorted { $0.path < $1.path }
    guard Set(ordered.map { $0.lastPathComponent.lowercased() }).count == ordered.count else {
      throw MediaOperationError.invalid(
        "The handoff has duplicate filenames. Rename them before copying.")
    }
    if FileManager.default.fileExists(atPath: destination.path) {
      let expected = Set(ordered.map { $0.lastPathComponent.lowercased() })
      let existing = try FileManager.default.contentsOfDirectory(
        at: destination, includingPropertiesForKeys: nil)
      guard
        !existing.contains(where: {
          (PhotoFormats.supports($0) || ["xmp", "acr"].contains($0.pathExtension.lowercased()))
            && !expected.contains($0.lastPathComponent.lowercased())
        })
      else {
        throw MediaOperationError.invalid(
          "This handoff folder contains other photos or sidecars. Choose a new dedicated folder.")
      }
    }
    try safeDirectory(destination)
    var manifest = IngestManifest()
    for (index, file) in ordered.enumerated() {
      try Task.checkCancellation()
      let fingerprint = try FileFingerprint.read(file)
      let hash = try Self.checksum(file)
      let target = destination.appendingPathComponent(file.lastPathComponent)
      _ = try copyVerified(file, to: target, expected: hash)
      guard try FileFingerprint.read(file) == fingerprint else {
        throw DecisionStoreError.fileChanged
      }
      manifest.records[file.lastPathComponent] = IngestRecord(
        relativePath: file.lastPathComponent, originalFilename: file.lastPathComponent,
        source: file, sha256: hash, verifiedDestinations: [target])
      try durableJSON(manifest, at: destination.appendingPathComponent(".photo-handoff.json"))
      await progress(
        IngestProgress(completed: index + 1, total: ordered.count, filename: file.lastPathComponent)
      )
    }
    return images.count
  }

  /// Plan only: no filesystem mutation. The complete image/companion mapping is
  /// reviewable before execution. A unique RAW+JPEG pair consumes one sequence.
  public func planRename(
    images: [URL], pattern: String, camera: String, start: Int,
    reader: any PhotoMetadataReading
  ) async throws -> RenamePlan {
    let images = images.map(Self.canonical)
    guard start >= 0, start <= 999_999_999, !images.isEmpty else {
      throw MediaOperationError.invalid("Choose photos and a sequence between 0 and 999999999.")
    }
    guard Set(images.map { $0.deletingLastPathComponent() }).count == 1 else {
      throw MediaOperationError.invalid("Rename one folder at a time.")
    }
    let folder = try directory(images[0].deletingLastPathComponent())
    let contents = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil)
    // Include paired images even when only their representative was selected.
    let supported = contents.filter(PhotoFormats.supports)
    let families = try PhotoFamily.groups(supported, contents: contents)
    let selected = Set(images.map { Self.canonical($0).path.precomposedStringWithCanonicalMapping })
    var chosen = families.filter { family in
      family.images.contains {
        selected.contains(Self.canonical($0).path.precomposedStringWithCanonicalMapping)
      }
    }
    guard !chosen.isEmpty else {
      throw MediaOperationError.invalid("The selected files are no longer present in this folder.")
    }
    var dates: [URL: Date] = [:]
    for family in chosen {
      if let date = try? await reader.metadata(for: family.primary).captureTime {
        dates[family.primary] = date
      }
    }
    chosen.sort {
      let a = dates[$0.primary] ?? .distantFuture
      let b = dates[$1.primary] ?? .distantFuture
      return a == b ? $0.primary.path < $1.primary.path : a < b
    }
    let id = UUID()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    var entries: [RenameEntry] = []
    var sequence = start
    for family in chosen {
      try Task.checkCancellation()
      var stem = pattern
      if pattern.contains("{date}") || pattern.contains("{time}") {
        guard let date = dates[family.primary] else {
          throw MediaOperationError.invalid(
            "Capture time is missing for \(family.primary.lastPathComponent). Use {original}/{sequence} or correct the metadata first."
          )
        }
        formatter.dateFormat = "yyyyMMdd"
        stem = stem.replacingOccurrences(of: "{date}", with: formatter.string(from: date))
        formatter.dateFormat = "HHmmss"
        stem = stem.replacingOccurrences(of: "{time}", with: formatter.string(from: date))
      }
      stem = stem.replacingOccurrences(of: "{camera}", with: camera)
        .replacingOccurrences(
          of: "{original}", with: family.primary.deletingPathExtension().lastPathComponent
        )
        .replacingOccurrences(of: "{sequence}", with: String(format: "%06d", sequence))
      guard Self.validStem(stem) else {
        throw MediaOperationError.invalid(
          "Use a nonempty filename without path separators, colons, braces or control characters (maximum 180 UTF-8 bytes)."
        )
      }
      for file in family.files {
        _ = try FileFingerprint.read(file)
        let member = family.images.first { image in
          !PhotoFormats.isRaw(image)
            && file.lastPathComponent.lowercased().hasPrefix(
              image.lastPathComponent.lowercased() + ".")
        }
        let suffix: String
        if let member {
          suffix = "." + member.pathExtension + "." + file.pathExtension
        } else {
          suffix = "." + file.pathExtension
        }
        let target = folder.appendingPathComponent(stem + suffix)
        if target == file { continue }
        let slot = entries.count
        entries.append(
          RenameEntry(
            original: file, destination: target,
            staging: folder.appendingPathComponent(".photo-rename-\(id)-\(slot)"),
            recovery: folder.appendingPathComponent(".photo-recover-\(id)-\(slot)"),
            fingerprint: try FileFingerprint.read(file), sha256: try Self.checksum(file)))
      }
      sequence += 1
    }
    try validate(entries)
    return RenamePlan(id: id, created: Date(), entries: entries, nextSequence: sequence)
  }

  public func rename(_ proposed: RenamePlan) throws -> URL {
    return try sourceProtection.withWritable(
      proposed.entries.flatMap { [$0.original, $0.destination, $0.staging, $0.recovery] } + [
        journalDirectory
      ]
    ) {
      try beginOperation()
      defer { operationInProgress = false }
      var plan = proposed
      try validate(plan.entries)
      for entry in plan.entries { try verify(entry.original, entry) }
      plan.phase = "executing"
      let journal = journalDirectory.appendingPathComponent("\(plan.id).json")
      try safeDirectory(journalDirectory)
      try durableJSON(plan, at: journal)
      do {
        for entry in plan.entries {
          try Task.checkCancellation()
          try verify(entry.original, entry)
          try FileManager.default.moveItem(at: entry.original, to: entry.staging)
        }
        for entry in plan.entries {
          try Task.checkCancellation()
          try FileManager.default.moveItem(at: entry.staging, to: entry.destination)
        }
        try updateIngestMappings(plan.entries, undo: false)
        plan.phase = "completed"
        try durableJSON(plan, at: journal)
        return journal
      } catch {
        // Rollback ignores cancellation so that a cancelled operation can recover.
        try? rollback(plan, journal: journal)
        throw error
      }

    }
  }

  public func undoRename(journal: URL) throws {
    try beginOperation()
    defer { operationInProgress = false }
    let plan = try JSONDecoder().decode(RenamePlan.self, from: Data(contentsOf: journal))
    try rollback(plan, journal: journal)
  }

  public func pendingRenames() throws -> [URL] {
    guard FileManager.default.fileExists(atPath: journalDirectory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: journalDirectory, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix("review-copy-") }.filter
    {
      let plan = try JSONDecoder().decode(RenamePlan.self, from: Data(contentsOf: $0))
      return ["executing", "rollingBack"].contains(plan.phase)
    }
  }

  private func rollback(_ original: RenamePlan, journal: URL) throws {
    return try sourceProtection.withWritable(
      original.entries.flatMap { [$0.original, $0.destination, $0.staging, $0.recovery] } + [
        journal
      ]
    ) {
      var plan = original
      if plan.phase == "rolledBack" { return }
      // Preflight every member before moving any: never overwrite an unrelated
      // file or silently undo a later metadata edit.
      var locations: [(RenameEntry, URL)] = []
      for entry in plan.entries {
        let matches = [entry.original, entry.staging, entry.destination, entry.recovery].filter {
          (try? FileFingerprint.read($0)) == entry.fingerprint
            && (try? $0.resourceValues(forKeys: [.nameKey]).name) == $0.lastPathComponent
        }
        guard let location = matches.first, Set(matches).count == 1 else {
          throw MediaOperationError.invalid(
            "Rename recovery is blocked by a missing or changed file. The journal was retained.")
        }
        try verify(location, entry, cancellation: false)
        locations.append((entry, location))
      }
      let owned = Set(locations.map { $0.1.standardizedFileURL.path })
      for entry in plan.entries where FileManager.default.fileExists(atPath: entry.original.path) {
        guard
          owned.contains(entry.original.path)
            || locations.contains(where: {
              (try? FileFingerprint.read(entry.original)) == $0.0.fingerprint
            })
        else {
          throw MediaOperationError.invalid(
            "An original filename is occupied; recovery will not overwrite it.")
        }
      }
      plan.phase = "rollingBack"
      try durableJSON(plan, at: journal)
      for (entry, location) in locations where location != entry.recovery {
        try FileManager.default.moveItem(at: location, to: entry.recovery)
      }
      for entry in plan.entries {
        try FileManager.default.moveItem(at: entry.recovery, to: entry.original)
      }
      try updateIngestMappings(plan.entries, undo: true)
      plan.phase = "rolledBack"
      try durableJSON(plan, at: journal)

    }
  }

  private func updateIngestMappings(_ entries: [RenameEntry], undo: Bool) throws {
    var manifests: Set<URL> = []
    for folder in Set(entries.map { $0.original.deletingLastPathComponent() }) {
      for ancestor in sequence(
        first: folder, next: { $0.path == "/" ? nil : $0.deletingLastPathComponent() })
      {
        let manifest = ancestor.appendingPathComponent(".photo-ingest.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
          manifests.insert(manifest)
          break
        }
      }
    }
    let mapping = Dictionary(
      entries.map {
        (
          (undo ? $0.destination : $0.original).path.precomposedStringWithCanonicalMapping,
          undo ? $0.original : $0.destination
        )
      }, uniquingKeysWith: { first, _ in first })
    for url in manifests {
      var manifest = try readManifest(url)
      var changed = false
      for (key, record) in manifest.records {
        let destinations = record.verifiedDestinations.map { old -> URL in
          if let replacement = mapping[old.path.precomposedStringWithCanonicalMapping] {
            changed = true
            return replacement
          }
          return old
        }
        manifest.records[key] = IngestRecord(
          relativePath: record.relativePath, originalFilename: record.originalFilename,
          source: record.source, sha256: record.sha256, verifiedDestinations: destinations)
      }
      if changed { try durableJSON(manifest, at: url) }
    }
  }

  private func validate(_ entries: [RenameEntry]) throws {
    let sources = Set(entries.map { $0.original.path.lowercased() })
    guard
      Set(entries.map { "\($0.fingerprint.device):\($0.fingerprint.inode)" }).count == entries.count
    else {
      throw MediaOperationError.invalid(
        "Multiple selected paths refer to the same file. Rename one hard-link alias at a time.")
    }
    guard sources.count == entries.count,
      Set(entries.map { $0.destination.path.lowercased() }).count == entries.count
    else {
      throw MediaOperationError.invalid(
        "The rename has duplicate destinations or ambiguous case-only source names.")
    }
    for entry in entries {
      if FileManager.default.fileExists(atPath: entry.destination.path),
        !sources.contains(entry.destination.path.lowercased())
      {
        throw MediaOperationError.invalid(
          "A destination already exists: \(entry.destination.lastPathComponent)")
      }
      for path in [entry.staging, entry.recovery]
      where FileManager.default.fileExists(atPath: path.path) {
        throw MediaOperationError.invalid(
          "A staging path already exists. Recover the prior operation first.")
      }
    }
  }

  private func verify(_ url: URL, _ entry: RenameEntry, cancellation: Bool = true) throws {
    guard try FileFingerprint.read(url) == entry.fingerprint else {
      throw DecisionStoreError.fileChanged
    }
    // Recovery must run even if the caller cancelled the original operation.
    let hash = try Self.hashIgnoringCancellation(url, checkCancellation: cancellation)
    guard hash == entry.sha256 else { throw DecisionStoreError.fileChanged }
  }
  private static func hashIgnoringCancellation(_ url: URL, checkCancellation: Bool) throws -> String
  {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var digest = SHA256()
    while true {
      if checkCancellation { try Task.checkCancellation() }
      guard let data = try file.read(upToCount: 1_048_576), !data.isEmpty else { break }
      digest.update(data: data)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
  func ingestFiles(in source: URL) throws -> [URL] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
    var enumerationFailure: (any Error)?
    guard
      let enumerator = FileManager.default.enumerator(
        at: source, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, error in
          enumerationFailure = error
          return false
        })
    else {
      throw MediaOperationError.invalid("The source folder could not be enumerated.")
    }
    var images: [URL] = []
    var companions: [URL] = []
    for case let url as URL in enumerator {
      try Task.checkCancellation()
      let values = try url.resourceValues(forKeys: Set(keys))
      guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
      if PhotoFormats.supports(url) {
        images.append(url)
      } else if ["xmp", "acr"].contains(url.pathExtension.lowercased()) {
        companions.append(url)
      }
    }
    if let enumerationFailure { throw enumerationFailure }
    let expected = Set(
      images.flatMap { image -> [String] in
        let base = PhotoFormats.isRaw(image) ? image.deletingPathExtension() : image
        return [
          base.appendingPathExtension("xmp").path.lowercased(),
          base.appendingPathExtension("acr").path.lowercased(),
        ]
      })
    // Publish companions before images so culling a completed image cannot
    // race the initial copy of that image's existing sidecar.
    let files = (images + companions.filter { expected.contains($0.path.lowercased()) }).sorted {
      if PhotoFormats.supports($0) != PhotoFormats.supports($1) {
        return !PhotoFormats.supports($0)
      }
      return $0.path < $1.path
    }
    guard !files.isEmpty else {
      throw MediaOperationError.invalid("No supported photos were found in the source.")
    }
    var folded: Set<String> = []
    for file in files {
      let relative = file.pathComponents.dropFirst(source.pathComponents.count).joined(
        separator: "/")
      guard folded.insert(relative.lowercased()).inserted else {
        throw MediaOperationError.invalid(
          "Case-only filename collisions must be resolved before ingest.")
      }
    }
    return files
  }

  func copyVerified(_ source: URL, to target: URL, expected: String) throws -> Bool {
    try sourceProtection.withWritable([target]) {}
    try safeDirectory(target.deletingLastPathComponent())
    if FileManager.default.fileExists(atPath: target.path) {
      let before = try FileFingerprint.read(target)
      guard try Self.checksum(target) == expected, try FileFingerprint.read(target) == before else {
        throw MediaOperationError.invalid(
          "Destination collision: \(target.lastPathComponent). Existing data was left untouched.")
      }
      return false
    }
    let temporary = target.deletingLastPathComponent().appendingPathComponent(
      ".photo-partial-\(UUID())")
    try sourceProtection.withWritable([temporary]) {
      try Data().write(to: temporary, options: .withoutOverwriting)
    }
    defer {
      try? sourceProtection.withWritable([temporary]) {
        try FileManager.default.removeItem(at: temporary)
      }
    }
    let input = try FileHandle(forReadingFrom: source)
    let output = try FileHandle(forWritingTo: temporary)
    defer {
      try? input.close()
      try? output.close()
    }
    // Bound the protection lock to a write chunk, never a whole RAW copy/hash.
    // Preview/decision checks in another actor can proceed between chunks.
    while true {
      try Task.checkCancellation()
      guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { break }
      try sourceProtection.withWritable([temporary]) { try output.write(contentsOf: data) }
    }
    try sourceProtection.withWritable([temporary]) { try output.synchronize() }
    try output.close()
    guard try Self.checksum(temporary) == expected else {
      throw MediaOperationError.invalid(
        "Copy verification failed; the incomplete copy was not published.")
    }
    try sourceProtection.withWritable([temporary, target]) {
      try FileManager.default.moveItem(at: temporary, to: target)
      try syncDirectory(target.deletingLastPathComponent())
    }
    return true
  }
  func directory(_ url: URL) throws -> URL {
    let url = url.standardizedFileURL
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw MediaOperationError.invalid("Choose a regular folder, not a symbolic link.")
    }
    return Self.canonical(url)
  }
  private static func canonical(_ url: URL) -> URL {
    if let pointer = realpath(url.path, nil) {
      defer { free(pointer) }
      return URL(fileURLWithPath: String(cString: pointer))
    }
    return url.standardizedFileURL
  }
  func safeDirectory(_ url: URL) throws {
    return try sourceProtection.withWritable([url]) {
      for component in sequence(
        first: url.standardizedFileURL,
        next: { $0.path == "/" ? nil : $0.deletingLastPathComponent() })
      {
        if let destination = try? FileManager.default.destinationOfSymbolicLink(
          atPath: component.path)
        {
          // macOS exposes these immutable system aliases in temporary URLs.
          if ["/var": "private/var", "/tmp": "private/tmp", "/etc": "private/etc"][component.path]
            == destination
          {
            continue
          }
          throw MediaOperationError.invalid(
            "A destination contains a symbolic link. Choose its actual folder instead.")
        }
      }
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

    }
  }
  static func contains(_ parent: URL, _ child: URL) -> Bool {
    let a = parent.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
    let b = child.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
    return a == b || b.hasPrefix(a + "/")
  }
  private static func validStem(_ value: String) -> Bool {
    !value.isEmpty && value != "." && value != ".." && !value.hasPrefix(".")
      && value.utf8.count <= 180
      && !value.contains(where: {
        "/:\\{}".contains($0) || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true
      })
  }
  func readManifest(_ url: URL) throws -> IngestManifest {
    guard FileManager.default.fileExists(atPath: url.path) else { return IngestManifest() }
    _ = try FileFingerprint.read(url)
    return try JSONDecoder().decode(IngestManifest.self, from: Data(contentsOf: url))
  }
  func durableJSON<T: Encodable>(_ value: T, at url: URL) throws {
    return try sourceProtection.withWritable([url]) {
      if FileManager.default.fileExists(atPath: url.path) { _ = try FileFingerprint.read(url) }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(value).write(to: url, options: .atomic)
      let file = try FileHandle(forWritingTo: url)
      try file.synchronize()
      try file.close()
      try syncDirectory(url.deletingLastPathComponent())
    }
  }
  private func syncDirectory(_ folder: URL) throws {
    let handle = Darwin.open(folder.path, O_RDONLY)
    guard handle >= 0 else {
      throw MediaOperationError.invalid(
        "A copy record could not be saved safely. Retry the operation.")
    }
    defer { Darwin.close(handle) }
    guard fsync(handle) == 0 else {
      throw MediaOperationError.invalid(
        "A copy record could not be synchronized. Retry the operation.")
    }
  }
}
