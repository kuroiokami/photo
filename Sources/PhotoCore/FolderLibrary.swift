import Foundation
import Observation

public protocol FolderDirectoryReading: Sendable {
  func subfolders(in directory: URL) async throws -> [URL]
}

public actor LocalFolderDirectoryReader: FolderDirectoryReading {
  public init() {}
  public func subfolders(in directory: URL) throws -> [URL] {
    try Task.checkCancellation()
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
    return try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
    ).filter { url in
      try Task.checkCancellation()
      let value = try url.resourceValues(forKeys: keys)
      return value.isDirectory == true && value.isSymbolicLink != true && value.isPackage != true
    }.sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
  }
}

public struct FolderSidebarRow: Identifiable, Sendable {
  public let id: String
  public let directory: URL
  public let depth: Int
  public let root: URL
  public var isRoot: Bool { depth == 0 }
}

/// Persistent shortcuts, not a catalog. Expanding a row reads only its immediate
/// directories; WorkspaceState owns the optional combined photo inventory.
@MainActor
@Observable
public final class FolderLibrary {
  public private(set) var home: URL?
  public private(set) var roots: [URL]
  public private(set) var expanded: Set<String>
  public private(set) var children: [String: [URL]] = [:]
  public private(set) var errors: [String: String] = [:]
  public private(set) var loading: Set<String> = []
  public private(set) var selected: URL?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let reader: any FolderDirectoryReading
  @ObservationIgnored private var requests: [String: UUID] = [:]

  public init(
    defaults: UserDefaults = .standard,
    reader: any FolderDirectoryReading = LocalFolderDirectoryReader()
  ) {
    self.defaults = defaults
    self.reader = reader
    let savedRoots = (defaults.stringArray(forKey: "Photo.folders.roots") ?? []).map {
      URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
    }
    roots = savedRoots
    if let savedHome = defaults.string(forKey: "Photo.folders.home") {
      home = savedHome.isEmpty ? nil : savedRoots.first { $0.path == savedHome }
    } else {
      // Existing installations keep their first saved folder as their starting place.
      home = savedRoots.first
    }
    expanded = Set(defaults.stringArray(forKey: "Photo.folders.expanded") ?? [])
    if let path = defaults.string(forKey: "Photo.folders.selected") {
      let candidate = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
      selected = roots.contains(where: { Self.contains($0, candidate) }) ? candidate : nil
    }
    if defaults.string(forKey: "Photo.folders.home") == nil {
      defaults.set(home?.path ?? "", forKey: "Photo.folders.home")
    }
  }
  public var rows: [FolderSidebarRow] {
    var result: [FolderSidebarRow] = []
    func append(_ folder: URL, root: URL, depth: Int) {
      result.append(
        FolderSidebarRow(
          id: root.path + "|" + folder.path, directory: folder, depth: depth, root: root))
      if expanded.contains(folder.path) {
        for child in children[folder.path] ?? [] { append(child, root: root, depth: depth + 1) }
      }
    }
    for root in roots { append(root, root: root, depth: 0) }
    return result
  }
  /// A navigation starting point, never a filesystem move or a recursive photo index.
  public func setHome(_ directory: URL) {
    let folder = directory.standardizedFileURL
    home = folder
    roots.removeAll { $0.path == folder.path }
    roots.insert(folder, at: 0)
    persist()
  }
  public func add(_ directory: URL) {
    let folder = directory.standardizedFileURL
    if !roots.contains(where: { $0.path == folder.path }) { roots.append(folder) }
    persist()
  }
  public func rememberIfUncovered(_ directory: URL) {
    if !roots.contains(where: { Self.contains($0, directory) }) { add(directory) }
    select(directory)
  }
  public func select(_ directory: URL) {
    selected = directory.standardizedFileURL
    persist()
  }
  public func remove(_ directory: URL) {
    let directory = directory.standardizedFileURL
    roots.removeAll { $0.path == directory.path }
    if home?.path == directory.path { home = nil }
    if let selected, !roots.contains(where: { Self.contains($0, selected) }) { self.selected = nil }
    // Forget only unloaded/unused cache state; never touch filesystem contents.
    let retained = { (path: String) in
      self.roots.contains { Self.contains($0, URL(fileURLWithPath: path)) }
    }
    expanded = Set(expanded.filter(retained))
    children = children.filter { retained($0.key) }
    errors = errors.filter { retained($0.key) }
    persist()
  }
  public func toggle(_ directory: URL) async {
    let directory = directory.standardizedFileURL
    if expanded.remove(directory.path) != nil {
      persist()
      return
    }
    expanded.insert(directory.path)
    persist()
    await refresh(directory)
  }
  public func refresh(_ directory: URL) async {
    let directory = directory.standardizedFileURL
    let token = UUID()
    requests[directory.path] = token
    loading.insert(directory.path)
    errors[directory.path] = nil
    do {
      let result = try await reader.subfolders(in: directory)
      guard requests[directory.path] == token else { return }
      children[directory.path] = result.map(\.standardizedFileURL)
    } catch {
      guard requests[directory.path] == token else { return }
      errors[directory.path] = "Unavailable — click to retry. " + error.localizedDescription
    }
    loading.remove(directory.path)
    requests[directory.path] = nil
  }
  public func restoreExpanded() async {
    for row in rows where expanded.contains(row.directory.path) { await refresh(row.directory) }
    // Descendant rows become visible only after their parents load.
    var visited: Set<String> = []
    while let row = rows.first(where: {
      expanded.contains($0.directory.path) && !visited.contains($0.directory.path)
    }) {
      visited.insert(row.directory.path)
      if children[row.directory.path] == nil && errors[row.directory.path] == nil {
        await refresh(row.directory)
      }
    }
  }
  private func persist() {
    defaults.set(home?.path ?? "", forKey: "Photo.folders.home")
    defaults.set(roots.map(\.path), forKey: "Photo.folders.roots")
    defaults.set(Array(expanded), forKey: "Photo.folders.expanded")
    if let selected {
      defaults.set(selected.path, forKey: "Photo.folders.selected")
    } else {
      defaults.removeObject(forKey: "Photo.folders.selected")
    }
  }
  private static func contains(_ root: URL, _ child: URL) -> Bool {
    let prefix = root.standardizedFileURL.pathComponents
    return child.standardizedFileURL.pathComponents.starts(with: prefix)
  }
}
