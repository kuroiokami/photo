import Foundation
import PhotoCore
import Testing

private actor ControlledFiles: PhotoFileAccess {
  private var pending: [URL: CheckedContinuation<[URL], Error>] = [:]
  private var waiting: [URL: CheckedContinuation<Void, Never>] = [:]

  func photos(in directory: URL) async throws -> [URL] {
    try await withCheckedThrowingContinuation { continuation in
      pending[directory] = continuation
      waiting.removeValue(forKey: directory)?.resume()
    }
  }

  func waitForRequest(_ directory: URL) async {
    if pending[directory] != nil { return }
    await withCheckedContinuation { waiting[directory] = $0 }
  }

  func finish(_ directory: URL, files: [URL]) {
    pending.removeValue(forKey: directory)?.resume(returning: files)
  }
}

@MainActor
struct FolderBrowsingTests {
  @Test func shallowEnumerationFiltersAndNaturallySorts() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for name in ["Photo10.JPG", "Photo2.png", "Photo1.jpeg", ".hidden.jpg", "notes.txt", "raw.nef"]
    {
      try Data("fixture".utf8).write(to: directory.appendingPathComponent(name))
    }
    let nested = directory.appendingPathComponent("nested.png")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data().write(to: nested.appendingPathComponent("nested.jpg"))
    try FileManager.default.createSymbolicLink(
      at: directory.appendingPathComponent("linked.jpg"),
      withDestinationURL: directory.appendingPathComponent("Photo1.jpeg"))
    let photos = try await LocalPhotoFileAccess().photos(in: directory)
    #expect(photos.map(\.lastPathComponent) == ["Photo1.jpeg", "Photo2.png", "Photo10.JPG"])
  }

  @Test(arguments: ["jpg", "JPG", "jpeg", "JPEG", "JpEg", "jPeG", "PNG", "pNg"])
  func extensionVariantsAndUnicodeNamesAreIncluded(_ ext: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let filename = "café-旅行.\(ext)"
    try Data().write(to: directory.appendingPathComponent(filename))
    let files = try await LocalPhotoFileAccess().photos(in: directory)
    #expect(files.map(\.lastPathComponent) == [filename])
  }

  @Test func latestFolderWinsEvenWhenOldProviderIgnoresCancellation() async {
    let provider = ControlledFiles()
    let state = WorkspaceState(fileAccess: provider)
    let first = URL(fileURLWithPath: "/first")
    let second = URL(fileURLWithPath: "/second")
    let firstTask = Task { await state.openFolder(first) }
    await provider.waitForRequest(first)
    #expect(state.loadState == .loading)
    #expect(state.photos.isEmpty)
    let secondTask = Task { await state.openFolder(second) }
    await provider.waitForRequest(second)
    await provider.finish(second, files: [second.appendingPathComponent("new.png")])
    await secondTask.value
    await provider.finish(first, files: [first.appendingPathComponent("old.jpg")])
    await firstTask.value
    #expect(state.directory == second)
    #expect(state.photos.map(\.filename) == ["new.png"])
    #expect(state.selectedPhoto?.filename == "new.png")
    #expect(state.loadState == .ready)
  }

  @Test func samplesInvalidatePendingFolderLoad() async {
    let provider = ControlledFiles()
    let state = WorkspaceState(fileAccess: provider)
    let directory = URL(fileURLWithPath: "/pending")
    let task = Task { await state.openFolder(directory) }
    await provider.waitForRequest(directory)
    state.showSamples()
    await provider.finish(directory, files: [])
    await task.value
    #expect(state.directory == nil)
    #expect(state.photos == SampleLibrary.photos)
    #expect(state.loadState == .ready)
  }

  @Test func emptyMissingAndReloadedFolders() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let state = WorkspaceState()
    await state.openFolder(directory)
    #expect(state.loadState == .ready)
    #expect(state.selectedPhoto == nil)
    let first = directory.appendingPathComponent("1.jpg")
    let second = directory.appendingPathComponent("2.jpg")
    try Data().write(to: first)
    try Data().write(to: second)
    await state.openFolder(directory)
    state.select(state.photos[1].id)
    let oldSession = state.sessionID
    await state.openFolder(directory)
    #expect(state.sessionID != oldSession)
    #expect(
      state.selectedPhoto?.fileURL?.resolvingSymlinksInPath() == second.resolvingSymlinksInPath())
    try FileManager.default.removeItem(at: second)
    await state.openFolder(directory)
    #expect(
      state.selectedPhoto?.fileURL?.resolvingSymlinksInPath() == first.resolvingSymlinksInPath())
    await state.openFolder(directory.appendingPathComponent("missing"))
    #expect(state.photos.isEmpty)
    if case .failed = state.loadState {
    } else {
      Issue.record("Missing folder should report a failure")
    }
  }
}
