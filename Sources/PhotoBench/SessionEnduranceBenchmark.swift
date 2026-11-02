import CoreGraphics
import Darwin
import Foundation
import ImageIO
import PhotoCore
import PhotoImaging
import UniformTypeIdentifiers

/// Owns every image, sidecar, journal and database it touches. No shared app storage.
@MainActor
enum SessionEnduranceBenchmark {
  struct Checkpoint: Encodable {
    let round: Int
    let elapsedSeconds: Double
    let residentBytes: UInt64
    let openDescriptors: Int?
    let thumbnailBytes: Int
    let fitBytes: Int
  }
  struct Report: Encodable {
    let schemaVersion = 1
    let rounds: Int
    let idleSecondsPerRound: Int
    let elapsedSeconds: Double
    let imageCount: Int
    let decisionsVerifiedInFreshProcess: Int
    let cullingActionsWhileIngestPending: Int
    let verifiedArrivals: Int
    let sourceAndBackupImagesUnchanged: Bool
    let workingImagesUnchanged: Bool
    let queuesDrained: Bool
    let releasedCameraPreviewBytes: Int
    let checkpoints: [Checkpoint]
    let operatingSystem: String
    let notes = [
      "Generated 1600x1000 JPEGs only, 64 separate identities in two subfolders. All writes use a fresh private temporary tree and explicit store/journal injection, never Photo's shared database.",
      "One initial 32-image verified ingest, followed by 32 live arrivals while making decisions; arrival callbacks include a deliberate 20ms dwell to exercise overlap, not measure copy throughput. Both destinations share a local volume.",
      "Each round alternates combined parent/subfolder browsing, indexes EXIF/decisions, loads 24 thumbnails, navigates 16 Fit previews, draws two full-detail JPEGs, rates/flags a group, then idles with services alive.",
      "A separate child process opens the same disposable database and compares all expected decisions. This verifies completed-save restart persistence, not power-loss recovery or app termination barriers.",
      "Checkpoint RSS includes allocator/framework/model memory and is not a whole-session peak. Descriptor counts include process baseline. No automatic RSS threshold proves absence of leaks; compare late checkpoints and repeated runs.",
      "No native window, App Nap, physical scroll/frame, RAW detail/camera-worker, real sleep/wake, memory-pressure or overnight acceptance is implied. Camera-preview accounting is recorded, but this JPEG workload does not exercise that worker.",
      "Output omits paths, filenames, hashes, photo metadata and pixels. Image hashes are compared outside active work. Source hashing warms filesystem caches.",
    ]
  }
  private struct Expected: Codable {
    let relativePath: String
    let decision: CullingDecision
  }
  private enum Failure: Error { case invariant, restart }
  @MainActor private final class Arrivals {
    var count = 0
    var pending = true
  }

  static func run(rounds: Int, idleSeconds: Int) async throws -> Report {
    let fm = FileManager.default
    let scratch = fm.temporaryDirectory.appendingPathComponent(
      "photo-endurance-" + UUID().uuidString)
    try fm.createDirectory(
      at: scratch, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: scratch) }
    do {
      return try await exercise(rounds: rounds, idleSeconds: idleSeconds, scratch: scratch)
    } catch {
      await DecisionSaveQueue.shared.flush()
      throw error
    }
  }
  private static func exercise(rounds: Int, idleSeconds: Int, scratch: URL) async throws -> Report {
    let firstCard = scratch.appendingPathComponent("Card1")
    let secondCard = scratch.appendingPathComponent("Card2")
    try generate(firstCard, startingAt: 0)
    try generate(secondCard, startingAt: 32)
    let primary = scratch.appendingPathComponent("Working")
    let backup = scratch.appendingPathComponent("Backup")
    let access = LocalPhotoFileAccess()
    let cards =
      try await access.photos(in: firstCard, includingSubfolders: true)
      + access.photos(in: secondCard, includingSubfolders: true)
    let sourceHashes = try await hash(cards)
    let protection = SourceProtection(
      registryURL: scratch.appendingPathComponent("protection.json"))
    let media = MediaOperations(
      journalDirectory: scratch.appendingPathComponent("Operations"), sourceProtection: protection)
    _ = try await media.ingest(source: firstCard, primary: primary, backup: backup)
    let database = scratch.appendingPathComponent("decisions.sqlite")
    let store = DecisionStore(databaseURL: database, sourceProtection: protection)
    let state = WorkspaceState(photos: [], decisionStore: store)
    let reader = ImageMetadataReader()
    let thumbnails = ImagePipeline(byteLimit: 16 * 1024 * 1024, maximumConcurrentLoads: 2)
    let fit = ImagePipeline(byteLimit: 48 * 1024 * 1024)
    let detail = DetailPipeline()
    await state.openFolder(primary, includingSubfolders: true)
    await state.loadDecisions()
    let arrivals = Arrivals()
    let began = ContinuousClock.now
    let copying = Task {
      defer { arrivals.pending = false }
      return try await media.ingest(source: secondCard, primary: primary, backup: backup) {
        progress in
        if !progress.verifiedImages.isEmpty {
          let indexing = await state.publishVerified(
            progress.verifiedImages, in: primary, using: reader)
          await indexing?.value
          await MainActor.run { arrivals.count += progress.verifiedImages.count }
          try? await Task.sleep(for: .milliseconds(20))
        }
      }
    }
    // Always join a file task before removing its private tree, including failures.
    var expectedDecisions: [URL: CullingDecision] = [:]
    var actionsDuringIngest = 0
    do {
      for index in 0..<32 {
        try Task.checkCancellation()
        guard let photo = state.photos.first else { throw Failure.invariant }
        state.select(photo.id)
        state.applyDecision(rating: index % 6, flag: index % 2 == 0 ? .pick : .reject)
        expectedDecisions[photo.fileURL!] = CullingDecision(
          rating: index % 6, flag: index % 2 == 0 ? .pick : .reject)
        if arrivals.pending { actionsDuringIngest += 1 }
        _ = try await fit.preview(
          for: photo.fileURL!, maximumPixelSize: 2560, sessionID: state.sessionID)
        try await Task.sleep(for: .milliseconds(25))
      }
      _ = try await copying.value
    } catch {
      copying.cancel()
      _ = await copying.result
      await DecisionSaveQueue.shared.flush()
      throw error
    }
    guard arrivals.count == 32, actionsDuringIngest > 0 else { throw Failure.invariant }
    let working = try await access.photos(in: primary, includingSubfolders: true)
    let backupFiles = try await access.photos(in: backup, includingSubfolders: true)
    guard working.count == 64, backupFiles.count == 64 else { throw Failure.invariant }
    let workingHashes = try await hash(working)
    let backupHashes = try await hash(backupFiles)
    guard sourceHashes.sorted() == workingHashes.sorted(), workingHashes == backupHashes else {
      throw Failure.invariant
    }
    var checkpoints: [Checkpoint] = []
    for round in 0..<rounds {
      try Task.checkCancellation()
      let folder = round % 2 == 0 ? primary : primary.appendingPathComponent("Day1")
      await state.openFolder(folder, includingSubfolders: true)
      await thumbnails.startSession(state.sessionID)
      await fit.startSession(state.sessionID)
      await state.loadDecisions()
      await state.indexMetadata(using: reader)
      let photos = state.photos
      guard !photos.isEmpty, state.decisionsReady.count == photos.count else {
        throw Failure.invariant
      }
      try await withThrowingTaskGroup(of: Void.self) { group in
        for photo in photos.prefix(24) {
          group.addTask {
            _ = try await thumbnails.preview(
              for: photo.fileURL!, maximumPixelSize: 240, sessionID: await state.sessionID)
          }
        }
        try await group.waitForAll()
      }
      for index in 0..<16 {
        let photo = photos[(index * 7 + round) % photos.count]
        state.select(photo.id)
        _ = try await fit.preview(
          for: photo.fileURL!, maximumPixelSize: 2560, sessionID: state.sessionID)
        if index < 2 { try await drawDetail(detail, photo.fileURL!) }
      }
      let targets = Array(photos.prefix(8))
      state.selectGroup(Set(targets.map(\.id)), focus: targets[0].id)
      state.applyDecision(rating: round % 6, flag: round % 2 == 0 ? .pick : .reject)
      state.undoDecision()
      state.redoDecision()
      for photo in targets {
        expectedDecisions[photo.fileURL!] = CullingDecision(
          rating: round % 6, flag: round % 2 == 0 ? .pick : .reject)
      }
      await DecisionSaveQueue.shared.flush()
      guard targets.allSatisfy({ state.saveStatus[$0.id] == "Saved" }) else {
        throw Failure.invariant
      }
      if idleSeconds > 0 { try await Task.sleep(for: .seconds(idleSeconds)) }
      let thumbnailBytes = await thumbnails.cachedByteCount
      let fitBytes = await fit.cachedByteCount
      let a = await thumbnails.schedulingStatistics()
      let b = await fit.schedulingStatistics()
      guard thumbnailBytes <= 16 * 1024 * 1024, fitBytes <= 48 * 1024 * 1024,
        a.activeLoads == 0, a.queuedLoads == 0, b.activeLoads == 0, b.queuedLoads == 0,
        !DecisionSaveQueue.shared.hasPending
      else { throw Failure.invariant }
      checkpoints.append(
        Checkpoint(
          round: round + 1, elapsedSeconds: seconds(began),
          residentBytes: residentBytes(), openDescriptors: descriptorCount(),
          thumbnailBytes: thumbnailBytes, fitBytes: fitBytes))
    }
    await DecisionSaveQueue.shared.flush()
    // Build expected values through a fresh store; compare against the live model below.
    let reopened = DecisionStore(databaseURL: database, sourceProtection: protection)
    var expected: [Expected] = []
    for file in working {
      let entry = try await reopened.load(for: file)
      guard entry.status == "Saved" else { throw Failure.invariant }
      guard entry.decision == (expectedDecisions[file] ?? CullingDecision()) else {
        throw Failure.invariant
      }
      expected.append(
        Expected(
          relativePath: file.deletingLastPathComponent().lastPathComponent + "/"
            + file.lastPathComponent,
          decision: entry.decision))
    }
    try JSONEncoder().encode(expected).write(
      to: scratch.appendingPathComponent("expected.json"), options: .atomic)
    try await restartVerifier(scratch)
    let sourceAfter = try await hash(cards)
    let backupAfter = try await hash(backupFiles)
    let unchanged = sourceAfter == sourceHashes && backupAfter == backupHashes
    let workingUnchanged = try await hash(working) == workingHashes
    guard unchanged, workingUnchanged else { throw Failure.invariant }
    return Report(
      rounds: rounds, idleSecondsPerRound: idleSeconds, elapsedSeconds: seconds(began),
      imageCount: working.count, decisionsVerifiedInFreshProcess: expected.count,
      cullingActionsWhileIngestPending: actionsDuringIngest, verifiedArrivals: arrivals.count,
      sourceAndBackupImagesUnchanged: unchanged, workingImagesUnchanged: workingUnchanged,
      queuesDrained: true, releasedCameraPreviewBytes: DetailPipeline.retainedCameraPreviewBytes,
      checkpoints: checkpoints,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString)
  }
  // Keep decoded images out of the caller's lifetime. Drawing touches every output row.
  private static func drawDetail(_ pipeline: DetailPipeline, _ file: URL) async throws {
    let preview = try await pipeline.detail(for: file)
    try autoreleasepool {
      guard
        let context = CGContext(
          data: nil, width: preview.decodedWidth, height: preview.decodedHeight,
          bitsPerComponent: 8, bytesPerRow: preview.decodedWidth * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { throw Failure.invariant }
      context.draw(
        preview.image,
        in: CGRect(x: 0, y: 0, width: preview.decodedWidth, height: preview.decodedHeight))
    }
  }
  static func verify(_ scratch: URL) async throws {
    let records = try JSONDecoder().decode(
      [Expected].self, from: Data(contentsOf: scratch.appendingPathComponent("expected.json")))
    let store = DecisionStore(
      databaseURL: scratch.appendingPathComponent("decisions.sqlite"),
      sourceProtection: SourceProtection(
        registryURL: scratch.appendingPathComponent("protection.json")))
    for record in records {
      let value = try await store.load(
        for: scratch.appendingPathComponent("Working").appendingPathComponent(record.relativePath))
      guard value.decision == record.decision, value.status == "Saved" else {
        throw Failure.restart
      }
    }
  }
  private static func restartVerifier(_ scratch: URL) async throws {
    guard let executable = Bundle.main.executableURL else { throw Failure.restart }
    try await Task.detached {
      let child = Process()
      child.executableURL = executable
      child.arguments = ["--endurance-verify", scratch.path]
      child.standardOutput = FileHandle.nullDevice
      child.standardError = FileHandle.nullDevice
      try child.run()
      child.waitUntilExit()
      guard child.terminationReason == .exit, child.terminationStatus == 0 else {
        throw Failure.restart
      }
    }.value
  }
  private static func generate(_ card: URL, startingAt start: Int) throws {
    guard
      let context = CGContext(
        data: nil, width: 1600, height: 1000, bitsPerComponent: 8,
        bytesPerRow: 6400, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw Failure.invariant }
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1000))
    guard let image = context.makeImage() else { throw Failure.invariant }
    for index in start..<(start + 32) {
      let folder = card.appendingPathComponent(index % 2 == 0 ? "Day1" : "Day2")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let file = folder.appendingPathComponent(String(format: "Photo%04d.jpeg", index))
      guard
        let output = CGImageDestinationCreateWithURL(
          file as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
      else { throw Failure.invariant }
      CGImageDestinationAddImage(
        output, image,
        [kCGImagePropertyExifDictionary: [kCGImagePropertyExifISOSpeedRatings: [100 + index]]]
          as CFDictionary)
      guard CGImageDestinationFinalize(output) else { throw Failure.invariant }
    }
  }
  private static func hash(_ files: [URL]) async throws -> [String] {
    try await Task.detached { try files.map { try MediaOperations.checksum($0) } }.value
  }
  private static func seconds(_ start: ContinuousClock.Instant) -> Double {
    let value = start.duration(to: .now)
    return Double(value.components.seconds) + Double(value.components.attoseconds) / 1e18
  }
  private static func descriptorCount() -> Int? {
    let size = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
    guard size > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: Int(size) + 1024)
    let length = bytes.withUnsafeMutableBytes {
      proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
    }
    return length > 0 ? Int(length) / MemoryLayout<proc_fdinfo>.stride : nil
  }
}
