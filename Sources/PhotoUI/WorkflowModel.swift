import AppKit
import Foundation
import Observation
import PhotoCore
import PhotoImaging

struct MetadataPreset: Codable, Identifiable {
  var id: String { name }
  var name: String
  var patch: MetadataPatch
}

@MainActor
@Observable
final class WorkflowModel {
  let workspace: WorkspaceState
  var requestedTab = 0
  var sourceReviewLaunch: UUID?
  var busy = false
  var backgroundable = false
  var status =
    "Choose a step. Copy photos, choose keepers, organize, then deliver or open in your editor."
  var renamePlan: RenamePlan?
  var metadataPlan: [MetadataFilePlan] = []
  var metadataResults: [String: String] = [:]
  var metadataUndoCount = 0
  var metadataRedoCount = 0
  var metadataUndoSummary: String?
  var metadataRedoSummary: String?
  var currentMetadata = DescriptiveMetadata()
  var presets: [MetadataPreset] = []
  var vocabulary: [String] = []
  var nextSequence = UserDefaults.standard.integer(forKey: "Photo.nextSequence")
  var lastRenameJournal: URL?
  var pendingRenames: [URL] = []
  var handoffFolder: URL?
  @ObservationIgnored var worker: Task<Void, Never>?

  init(workspace: WorkspaceState) {
    self.workspace = workspace
    presets =
      UserDefaults.standard.data(forKey: "Photo.metadataPresets").flatMap {
        try? JSONDecoder().decode([MetadataPreset].self, from: $0)
      } ?? []
    vocabulary = UserDefaults.standard.stringArray(forKey: "Photo.keywordVocabulary") ?? []
    if let path = UserDefaults.standard.string(forKey: "Photo.lastRenameJournal") {
      lastRenameJournal = URL(fileURLWithPath: path)
    }
  }
  func targets(_ scope: String) -> [URL] {
    switch scope {
    case "All files": workspace.filePhotos.compactMap(\.fileURL)
    case "Visible": workspace.filesRepresented(by: workspace.photos).compactMap(\.fileURL)
    default: workspace.operationPhotos.compactMap(\.fileURL)
    }
  }
  func run(background: Bool = false, _ action: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }
    busy = true
    backgroundable = background
    status = "Working…"
    let task = Task { @MainActor [self] in
      await DecisionSaveQueue.shared.flush()
      do {
        try Task.checkCancellation()
        try await action()
      } catch is CancellationError {
        status = "Cancelled. Verified copies remain; unfinished renames retain recovery journals."
      } catch { status = error.localizedDescription }
      busy = false
      backgroundable = false
      worker = nil
    }
    worker = task
    WorkflowOperationBarrier.shared.track(task)
  }
  func refresh() async {
    do {
      let history = try await workspace.persistence.metadataHistoryState()
      metadataUndoCount = history.undoCount
      metadataRedoCount = history.redoCount
      metadataUndoSummary = history.undoSummary
      metadataRedoSummary = history.redoSummary
    } catch { status = error.localizedDescription }
    do { pendingRenames = try await MediaOperations.shared.pendingRenames() } catch {
      status = "Rename recovery needs attention: " + error.localizedDescription
    }
    currentMetadata = DescriptiveMetadata()
    if let image = workspace.firstSelectedPhoto?.fileURL {
      do {
        let embedded = try await ImageMetadataReader().embeddedXMP(for: image)
        currentMetadata = try await workspace.persistence.loadMetadata(
          for: image, embedded: embedded
        ).value
      } catch { status = error.localizedDescription }
    }
  }
  func startSourceReview(source: String) {
    guard !busy else { return }
    guard !WorkflowOperationBarrier.shared.hasPending else {
      status = "Wait for the current file operation to finish before protecting a source."
      return
    }
    busy = true
    status = "Protecting source…"
    let task = Task { @MainActor [self] in
      do {
        let folder = try Self.path(source)
        _ = try await workspace.persistence.beginSourceReview(folder)
        // Protection is installed BEFORE draining queued normal saves.
        await DecisionSaveQueue.shared.flush()
        await openFolder(folder)
        guard workspace.loadState == .ready, workspace.isSourceReview else {
          throw SourceReviewError.sourceChanged
        }
        sourceReviewLaunch = UUID()
        status = "Review saved on this Mac. Source files and metadata stay unchanged."
        NotificationCenter.default.post(name: .photoSourceReviewChanged, object: nil)
      } catch { status = error.localizedDescription }
      busy = false
      worker = nil
    }
    worker = task
    WorkflowOperationBarrier.shared.track(task)
  }
  func ingest(source: String, primary: String, backup: String, job: String) {
    run(background: true) { [self] in
      guard !job.isEmpty, job != ".", job != "..", !job.contains(where: { "/\\:".contains($0) })
      else {
        throw MediaOperationError.invalid(
          "Use a shoot name without slashes, backslashes or colons.")
      }
      let sourceURL = try Self.path(source)
      let primaryURL = try Self.path(primary).appendingPathComponent(job).appendingPathComponent(
        "Originals")
      let backupURL = try Self.path(backup).appendingPathComponent(job).appendingPathComponent(
        "Originals")
      ingestBrowseFolder = nil
      verifiedArrivals = [:]
      activeIngestRoot = PhotoPath.canonical(primaryURL)
      defer { activeIngestRoot = nil }
      let report: IngestReport
      do {
        report = try await MediaOperations.shared.ingest(
          source: sourceURL, primary: primaryURL, backup: backupURL
        ) { [weak self] progress in
          await self?.ingestProgress(progress)
        }
      } catch {
        await flushArrivals()
        throw error
      }
      await flushArrivals()
      status =
        "Processed \(report.fileCount) files: \(report.copiedCount) copies written, \(report.alreadyVerifiedCount) existing copies verified, \(report.preservedMetadataCount) previously ingested metadata copies preserved."
      if report.sameVolumeBackup {
        status +=
          " Both destinations are on the same volume; choose another drive for an independent backup."
      }
      handoffFolder = report.destination
      status +=
        " Verified arrivals appear automatically; browse subfolders for other card directories."
    }
  }
  private var ingestBrowseFolder: URL?
  private var activeIngestRoot: URL?
  private var verifiedArrivals: [URL: Set<URL>] = [:]
  @ObservationIgnored private var arrivalTask: Task<Void, Never>?

  /// During ingest, opening/reloading a working subfolder excludes files whose
  /// family has not yet been verified at both destinations.
  func openFolder(_ folder: URL) async {
    let canonical = PhotoPath.canonical(folder)
    let limited =
      activeIngestRoot.map { canonical.pathComponents.starts(with: $0.pathComponents) } ?? false
    await workspace.openFolder(
      folder, verifiedImages: limited ? Array(verifiedArrivals[canonical] ?? []) : nil)
  }
  private func ingestProgress(_ progress: IngestProgress) async {
    status =
      "Verified \(progress.completed)/\(progress.total): \(progress.filename). Verified arrivals appear automatically."
    for image in progress.verifiedImages {
      verifiedArrivals[PhotoPath.canonical(image.deletingLastPathComponent()), default: []].insert(
        image)
    }
    if ingestBrowseFolder == nil, let directory = progress.directory {
      ingestBrowseFolder = directory
      await openFolder(directory)
    }
    guard arrivalTask == nil, !progress.verifiedImages.isEmpty else { return }
    arrivalTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(200))
        try Task.checkCancellation()
      } catch { return }
      self?.arrivalTask = nil
      await self?.flushArrivals()
    }
  }
  private func flushArrivals() async {
    arrivalTask?.cancel()
    arrivalTask = nil
    guard let folder = workspace.directory,
      let images = verifiedArrivals[PhotoPath.canonical(folder)]
    else { return }
    await workspace.publishVerified(Array(images), in: folder, using: ImageMetadataReader())?.value
  }
  func previewRename(scope: String, pattern: String, camera: String, sequence: String) {
    run { [self] in
      guard let start = Int(sequence) else {
        throw MediaOperationError.invalid("Enter a whole-number sequence.")
      }
      renamePlan = try await MediaOperations.shared.planRename(
        images: targets(scope), pattern: pattern, camera: camera, start: start,
        reader: ImageMetadataReader())
      status =
        "Review all \(renamePlan?.entries.count ?? 0) file changes, including companions. No files have been renamed."
    }
  }
  func applyRename() {
    guard let plan = renamePlan else { return }
    run { [self] in
      let journal = try await MediaOperations.shared.rename(plan)
      lastRenameJournal = journal
      nextSequence = plan.nextSequence
      UserDefaults.standard.set(nextSequence, forKey: "Photo.nextSequence")
      UserDefaults.standard.set(journal.path, forKey: "Photo.lastRenameJournal")
      renamePlan = nil
      if let directory = workspace.directory { await workspace.openFolder(directory) }
      status =
        "Renamed \(plan.entries.count) files. Original names are retained in the recovery journal."
    }
  }
  func undoRename() {
    guard let journal = lastRenameJournal else { return }
    run { [self] in
      try await MediaOperations.shared.undoRename(journal: journal)
      if let directory = workspace.directory { await workspace.openFolder(directory) }
      status = "Restored the previous filenames."
    }
  }
  func recover() {
    run { [self] in
      for journal in try await MediaOperations.shared.pendingRenames() {
        try await MediaOperations.shared.undoRename(journal: journal)
      }
      pendingRenames = try await MediaOperations.shared.pendingRenames()
      if let directory = workspace.directory { await workspace.openFolder(directory) }
      status = "Incomplete renames recovered to their original names."
    }
  }
  func previewField(_ field: MetadataField, value: String, clear: Bool, scope: String) {
    guard clear || !value.isEmpty else {
      metadataPlan = []
      status = "Enter a value or choose Clear for this field."
      return
    }
    var patch = MetadataPatch()
    patch.fields[field] = clear ? "" : value
    previewMetadata(patch, scope: scope)
  }
  func previewMetadata(_ patch: MetadataPatch, scope: String) {
    run { [self] in
      guard !patch.fields.isEmpty || patch.keywordAction != .leave else {
        throw MediaOperationError.invalid("Choose metadata fields or a keyword action first.")
      }
      let images = targets(scope)
      guard !images.isEmpty else {
        throw MediaOperationError.invalid("Select photos from a real folder first.")
      }
      let reader = ImageMetadataReader()
      var embedded: [String: Data] = [:]
      for image in images { embedded[image.path] = try await reader.embeddedXMP(for: image) }
      metadataPlan = try await workspace.persistence.prepareMetadata(
        patch, images: images, embedded: embedded)
      status =
        "Review \(metadataPlan.count) metadata updates. Nothing has been written to sidecars."
    }
  }
  func applyMetadata() {
    let plans = metadataPlan
    run { [self] in
      let entries = try await workspace.persistence.saveMetadataBatch(plans)
      metadataResults = entries.mapValues(\.status)
      metadataPlan = []
      status =
        "Metadata processed: \(metadataResults.values.filter { $0 == "Saved" }.count)/\(plans.count) synchronized. Review local-only or conflict rows below."
      await refresh()
    }
  }
  func replayMetadata(undo: Bool) {
    run { [self] in
      let entries =
        try await
        (undo
        ? workspace.persistence.undoMetadataBatch() : workspace.persistence.redoMetadataBatch())
      metadataResults = entries.mapValues(\.status)
      metadataPlan = []
      status =
        "\(undo ? "Undid" : "Redid") metadata for \(entries.count) files. Review any pending/conflict rows."
      await refresh()
    }
  }
  func resolveMetadata(path: String, choice: String) {
    run { [self] in
      let image = URL(fileURLWithPath: path)
      let entry: MetadataEntry
      if choice == "External" {
        entry = try await workspace.persistence.useExternalMetadata(for: image)
      } else {
        entry = try await workspace.persistence.retryMetadata(
          for: image, useLocal: choice == "Local")
      }
      metadataResults[path] = entry.status
      status = entry.status
    }
  }
  func savePreset(name: String, patch: MetadataPatch) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      status = "Enter a preset name."
      return
    }
    presets.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    presets.append(MetadataPreset(name: name, patch: patch))
    if let data = try? JSONEncoder().encode(presets) {
      UserDefaults.standard.set(data, forKey: "Photo.metadataPresets")
    }
    let words = patch.keywordText.components(separatedBy: CharacterSet(charactersIn: ",\n")).map {
      $0.trimmingCharacters(in: .whitespaces)
    }.filter { !$0.isEmpty }
    vocabulary = Array(Set(vocabulary + words)).sorted()
    UserDefaults.standard.set(vocabulary, forKey: "Photo.keywordVocabulary")
    status = "Preset saved locally."
  }
  func prepareLightroom(destination: String, embedMetadata: Bool) {
    run { [self] in
      guard !workspace.decisionsLoading,
        workspace.filePhotos.allSatisfy({ workspace.decisionsReady.contains($0.id) })
      else { throw MediaOperationError.invalid("Wait for culling decisions to finish loading.") }
      let files = workspace.filePhotos.filter { workspace.decisions[$0.id]?.flag != .reject }
        .compactMap(\.fileURL)
      for file in files {
        let entry = try await workspace.persistence.load(for: file)
        let metadata = try await workspace.persistence.loadMetadata(for: file)
        guard entry.status == "Saved", metadata.status == "Saved" else {
          throw MediaOperationError.invalid(
            "Resolve pending metadata/XMP for \(file.lastPathComponent) before handoff.")
        }
      }
      let destination = try Self.path(destination)
      let count = try await MediaOperations.shared.prepareHandoff(
        images: files, destination: destination
      ) { [weak self] progress in
        await MainActor.run {
          self?.status = "Handoff verified \(progress.completed)/\(progress.total) files"
        }
      }
      if embedMetadata {
        let writer = HandoffMetadataWriter()
        var derived: [String: String] = [:]
        for source in files where !PhotoFormats.isRaw(source) {
          let copy = destination.appendingPathComponent(source.lastPathComponent)
          let sidecar = XMPSidecar.url(for: copy)
          if FileManager.default.fileExists(atPath: sidecar.path) {
            derived[copy.lastPathComponent] = try await writer.embed(in: copy, sidecar: sidecar)
          }
        }
        if !derived.isEmpty {
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
          try encoder.encode(derived).write(
            to: destination.appendingPathComponent(".photo-derived-checksums.json"),
            options: .atomic)
        }
      }
      handoffFolder = destination
      status =
        "Prepared \(count) non-rejected photos plus their XMP/ACR companions. Ready for delivery or an editor. The source folder is unchanged."
    }
  }
  private static func path(_ text: String) throws -> URL {
    guard text.hasPrefix("/"), !text.isEmpty else {
      throw MediaOperationError.invalid("Use Choose to select a folder.")
    }
    return URL(fileURLWithPath: text).standardizedFileURL.resolvingSymlinksInPath()
  }
}
