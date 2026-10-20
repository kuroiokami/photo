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
  var busy = false
  var backgroundable = false
  var status = "Choose an operation. File changes are intended for photos before Lightroom import."
  var renamePlan: RenamePlan?
  var metadataPlan: [MetadataFilePlan] = []
  var metadataResults: [String: String] = [:]
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
  func ingest(source: String, primary: String, backup: String, job: String) {
    run(background: true) { [self] in
      guard !job.isEmpty, job != ".", job != "..", !job.contains(where: { "/\\:".contains($0) })
      else {
        throw MediaOperationError.invalid("Enter a single job folder name without path separators.")
      }
      let sourceURL = try Self.path(source)
      let primaryURL = try Self.path(primary).appendingPathComponent(job).appendingPathComponent(
        "Originals")
      let backupURL = try Self.path(backup).appendingPathComponent(job).appendingPathComponent(
        "Originals")
      ingestBrowseFolder = nil
      let report = try await MediaOperations.shared.ingest(
        source: sourceURL, primary: primaryURL, backup: backupURL
      ) { [weak self] progress in
        await self?.ingestProgress(progress)
      }
      status =
        "Processed \(report.fileCount) files: \(report.copiedCount) copies written, \(report.alreadyVerifiedCount) existing copies verified, \(report.preservedMetadataCount) previously ingested metadata copies preserved."
      if report.sameVolumeBackup {
        status +=
          " Both destinations are on the same volume; choose another drive for an independent backup."
      }
      handoffFolder = report.destination
      if let folder = ingestBrowseFolder, workspace.directory == folder {
        await workspace.openFolder(folder)
      }
      status +=
        " Reload the current folder to see arrivals; browse subfolders for other card directories."
    }
  }
  private var ingestBrowseFolder: URL?
  private func ingestProgress(_ progress: IngestProgress) async {
    status =
      "Verified \(progress.completed)/\(progress.total): \(progress.filename). Continue Browsing to cull; Reload shows new arrivals."
    if ingestBrowseFolder == nil, let directory = progress.directory {
      ingestBrowseFolder = directory
      await workspace.openFolder(directory)
    }
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
      metadataResults = [:]
      for plan in plans {
        try Task.checkCancellation()
        do {
          metadataResults[plan.image.path] = try await workspace.persistence.saveMetadata(plan)
            .status
        } catch { metadataResults[plan.image.path] = error.localizedDescription }
      }
      metadataPlan = []
      status =
        "Metadata processed: \(metadataResults.values.filter { $0 == "Saved" }.count)/\(plans.count) synchronized. Review local-only or conflict rows below."
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
        "Prepared \(count) non-rejected photos plus their XMP/ACR companions. In Lightroom Classic, Import this folder with Add. The source folder is unchanged."
    }
  }
  private static func path(_ text: String) throws -> URL {
    guard text.hasPrefix("/"), !text.isEmpty else {
      throw MediaOperationError.invalid("Choose or enter an absolute folder path.")
    }
    return URL(fileURLWithPath: text).standardizedFileURL.resolvingSymlinksInPath()
  }
}
