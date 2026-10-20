import Foundation
import PhotoCore
import Testing

@MainActor
struct FolderLibraryTests {
  @Test func persistentTreeRemovesShortcutsWithoutDeletingFiles() async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    let child = root.appendingPathComponent("shoot/keepers")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let suite = "PhotoTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let library = FolderLibrary(defaults: defaults)
    library.add(root)
    library.add(root)
    library.rememberIfUncovered(child)
    #expect(library.roots.count == 1)
    await library.toggle(root)
    await library.toggle(root.appendingPathComponent("shoot"))
    #expect(library.rows.map(\.depth) == [0, 1, 2])
    let restored = FolderLibrary(defaults: defaults)
    #expect(restored.selected?.path == child.path)
    await restored.restoreExpanded()
    #expect(restored.rows.map(\.directory.path) == library.rows.map(\.directory.path))
    restored.add(child)
    restored.remove(root)
    #expect(restored.selected?.path == child.path)
    restored.remove(child)
    #expect(restored.roots.isEmpty)
    #expect(restored.selected == nil)
    #expect(FileManager.default.fileExists(atPath: child.path))
    #expect(FolderLibrary(defaults: defaults).roots.isEmpty)
  }
  @Test func directoryReaderIsShallowNaturalAndSkipsHiddenAndLinks() async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["Shoot10", "Shoot2", ".hidden", "Shoot2/deeper"] {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    try Data().write(to: root.appendingPathComponent("photo.jpg"))
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("link"), withDestinationURL: root)
    #expect(
      try await LocalFolderDirectoryReader().subfolders(in: root).map(\.lastPathComponent) == [
        "Shoot2", "Shoot10",
      ])
  }
  @Test func missingRootStaysListedUntilExplicitRemoval() async throws {
    let suite = "PhotoTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    let library = FolderLibrary(defaults: defaults)
    library.add(root)
    await library.toggle(root)
    #expect(library.errors[root.path] != nil)
    #expect(library.roots == [root])
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    await library.refresh(root)
    #expect(library.errors[root.path] == nil)
    #expect(library.roots == [root])
  }
}
