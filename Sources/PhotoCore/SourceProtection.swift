import Darwin
import Foundation

public enum SourceReviewError: LocalizedError {
  case protectedSource, sourceChanged, unavailable, copyNotReady, localData, identityUnavailable
  public var errorDescription: String? {
    switch self {
    case .protectedSource:
      "This source is protected. Review decisions stay on this Mac; organize photos after copying."
    case .sourceChanged:
      "This source changed or was replaced. Choose Review Before Copying to start a new review."
    case .unavailable:
      "Source protection could not be read. No files were changed. Restore Photo’s local protection data before trying again."
    case .copyNotReady:
      "Copying a protected review is not available yet. Your review is saved on this Mac."
    case .identityUnavailable:
      "This folder cannot be identified safely. Use a local photo folder or mounted card for source review."
    case .localData: "Choose a source outside Photo’s local application data."
    }
  }
}

public struct SourceReviewSession: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let root: URL
  let binding: String
}

/// Synchronous write boundary shared by all file/metadata actors. The lock spans
/// the actual mutation, so activating protection cannot race a checked write.
/// Only the small source registry lives here; per-photo review data lives in SQLite.
public final class SourceProtection: @unchecked Sendable {
  public static let shared = SourceProtection(
    registryURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Photo/source-protection.json"))
  private static let lock = NSRecursiveLock()
  private let registryURL: URL
  private var stamp: String?
  private var cached: [SourceReviewSession] = []
  private var wasPresent = false
  public init(registryURL: URL) { self.registryURL = registryURL }

  private func records() throws -> [SourceReviewSession] {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: registryURL.path)
      let current =
        "\(attributes[.systemFileNumber] ?? ""):\(attributes[.modificationDate] ?? ""):\(attributes[.size] ?? "")"
      if current == stamp { return cached }
      let value = try JSONDecoder().decode(
        [SourceReviewSession].self, from: Data(contentsOf: registryURL))
      cached = value
      stamp = current
      wasPresent = true
      return value
    } catch let error as CocoaError
      where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
    {
      guard !wasPresent else { throw SourceReviewError.unavailable }
      return []
    } catch { throw SourceReviewError.unavailable }
  }

  private static func contains(_ root: URL, _ child: URL) -> Bool {
    child.pathComponents.starts(with: root.pathComponents)
  }
  private static func binding(_ folder: URL) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
    guard attributes[.type] as? FileAttributeType == .typeDirectory else {
      throw SourceReviewError.sourceChanged
    }
    let volume = (try? folder.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    let device = (attributes[.systemNumber] as? NSNumber)?.stringValue
    guard let volumeID = volume ?? device,
      let inode = (attributes[.systemFileNumber] as? NSNumber)?.stringValue
    else {
      throw SourceReviewError.identityUnavailable
    }
    let created = (attributes[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return "\(volumeID):\(inode):\(created)"
  }
  private func matching(_ url: URL, records: [SourceReviewSession]) throws -> SourceReviewSession? {
    guard !records.isEmpty else { return nil }
    let target = PhotoPath.canonical(url)
    let candidates = records.filter { Self.contains($0.root, target) }
    if !candidates.isEmpty {
      if let session = candidates.first(where: { (try? Self.binding($0.root)) == $0.binding }) {
        return session
      }
      throw SourceReviewError.sourceChanged
    }
    // Also protect a source folder moved within its volume, including aliases.
    var ancestor = target
    while ancestor.path != "/" {
      if let binding = try? Self.binding(ancestor),
        let session = records.first(where: { $0.binding == binding })
      {
        return SourceReviewSession(id: session.id, root: ancestor, binding: binding)
      }
      ancestor.deleteLastPathComponent()
    }
    return nil
  }
  public func session(for url: URL) throws -> SourceReviewSession? {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    return try matching(url, records: records())
  }
  public func protect(_ folder: URL) throws -> SourceReviewSession {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let root = PhotoPath.canonical(folder)
    guard !Self.contains(root, PhotoPath.canonical(registryURL)) else {
      throw SourceReviewError.localData
    }
    let binding = try Self.binding(root)
    var sessions = try records()
    if let session = sessions.first(where: { $0.binding == binding }) { return session }
    if let parent = sessions.first(where: {
      Self.contains($0.root, root) && $0.root.path != root.path
    }) {
      guard (try? Self.binding(parent.root)) == parent.binding else {
        throw SourceReviewError.sourceChanged
      }
      return parent
    }
    guard
      !sessions.contains(where: {
        Self.contains(root, $0.root) && $0.root.path != root.path
      })
    else { throw SourceReviewError.protectedSource }
    // Reusing the same card location is an explicit new review, never old decisions.
    let session = SourceReviewSession(id: UUID(), root: root, binding: binding)
    sessions.append(session)
    try FileManager.default.createDirectory(
      at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(sessions).write(to: registryURL, options: .atomic)
    let file = try FileHandle(forWritingTo: registryURL)
    try file.synchronize()
    try file.close()
    let directory = Darwin.open(registryURL.deletingLastPathComponent().path, O_RDONLY)
    guard directory >= 0 else { throw SourceReviewError.unavailable }
    defer { Darwin.close(directory) }
    guard fsync(directory) == 0 else { throw SourceReviewError.unavailable }
    cached = sessions
    stamp = nil
    wasPresent = true
    return session
  }
  public func withWritable<T>(_ urls: [URL], _ operation: () throws -> T) throws -> T {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let sessions = try records()
    for url in urls {
      let path = PhotoPath.canonical(url)
      if try sessions.contains(where: {
        Self.contains($0.root, path) || Self.contains(path, $0.root)
      }) || matching(path, records: sessions) != nil {
        throw SourceReviewError.protectedSource
      }
      // Conservatively reject multiply-linked files while sources are protected;
      // a second name must not bypass the source boundary through a hard link.
      if !sessions.isEmpty,
        let count = (try? FileManager.default.attributesOfItem(atPath: path.path)[.referenceCount])
          as? NSNumber,
        count.intValue > 1,
        (try? FileManager.default.attributesOfItem(atPath: path.path)[.type]) as? FileAttributeType
          == .typeRegular
      {
        throw SourceReviewError.protectedSource
      }
    }
    return try operation()
  }
}

extension Notification.Name {
  public static let photoSourceReviewChanged = Notification.Name("Photo.sourceReviewChanged")
}
