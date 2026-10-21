import Foundation
import PhotoCore

extension WorkflowModel {
  func prepareReviewedCopy(
    source: String, scope: ReviewedCopyScope, primary: String, backup: String, job: String,
    keepPairs: Bool, acceptMetadataChanges: Bool
  ) {
    let selected = workspace.operationPhotos.compactMap(\.fileURL)
    let identities = workspace.selectedFileIdentities
    reviewedCopyPlan = nil
    run { [self] in
      let root = try Self.path(source)
      guard let session = try await workspace.persistence.sourceReview(for: root),
        PhotoPath.canonical(root).path == session.root.path
      else {
        throw MediaOperationError.invalid(
          "Choose the reviewed source folder shown in the source banner. Start Review Before Copying first if this source has not been reviewed."
        )
      }
      if workspace.isSourceReview
        && workspace.saveStatus.values.contains(where: { !$0.hasPrefix("Review saved on this Mac") }
        )
      {
        throw MediaOperationError.invalid(
          "Some review changes have not saved. Close this panel, retry the review save, then prepare the copy list again."
        )
      }
      let destinations = try Self.reviewDestinations(primary: primary, backup: backup, job: job)
      reviewedCopyPlan = try await mediaOperations.planReviewedCopy(
        session: session, scope: scope, selection: selected, selectionIdentities: identities,
        primary: destinations.0, backup: destinations.1, keepPairs: keepPairs,
        acceptMetadataChanges: acceptMetadataChanges, store: workspace.persistence)
      status =
        "Copy list prepared. Review its counts and companions, then choose Copy & Verify Both Copies. Later review changes will not change this saved list."
    }
  }

  static func reviewDestinations(primary: String, backup: String, job: String) throws -> (URL, URL)
  {
    guard !job.isEmpty, !job.hasPrefix("."), job.utf8.count <= 180,
      !job.contains(where: {
        "/\\:".contains($0) || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true
      })
    else {
      throw MediaOperationError.invalid(
        "Give the shoot a short name without slashes, colons, hidden-folder prefixes or line breaks."
      )
    }
    return (
      try Self.path(primary).appendingPathComponent(job).appendingPathComponent("Originals"),
      try Self.path(backup).appendingPathComponent(job).appendingPathComponent("Originals")
    )
  }

  func copyReviewed(_ plan: ReviewedCopyPlan, includeOpposingPairs: Bool) {
    run(background: true) { [self] in
      keepSourceVisible = true
      copiedReviewFolder = nil
      reviewMetadataPendingImages = []
      reviewMetadataPending = 0
      handoffFolder = nil
      ingestBrowseFolder = nil
      verifiedArrivals = [:]
      activeIngestRoot = PhotoPath.canonical(plan.primary)
      defer {
        activeIngestRoot = nil
        keepSourceVisible = false
      }
      let report: ReviewedCopyReport
      do {
        report = try await mediaOperations.copyReviewed(
          plan, store: workspace.persistence, includeOpposingPairs: includeOpposingPairs
        ) { [weak self] progress in
          await self?.ingestProgress(progress)
        }
      } catch {
        await flushArrivals()
        savedReviewCopies =
          (try? await mediaOperations.savedReviewedCopies()) ?? savedReviewCopies
        status =
          "Copy paused. Keep both destinations and choose Resume Saved Copy to continue the same list. "
          + error.localizedDescription
        return
      }
      await flushArrivals()
      copiedReviewFolder = report.firstFolder
      handoffFolder = plan.primary
      reviewMetadataPending = report.pendingMetadata
      reviewMetadataPendingImages = report.pendingMetadataImages
      savedReviewCopies = try await mediaOperations.savedReviewedCopies()
      status =
        "Verified \(report.photoCount) photos and \(report.fileCount) total files at both destinations. Review decisions and Photo-local image edits are saved for both copies."
      if report.pendingMetadata > 0 {
        status +=
          " \(report.pendingMetadata) destination metadata saves are pending or conflicted across photo/backup copies. Resume the saved copy to retry; inspect saving status in each destination before delivery."
      } else {
        status += " Review metadata is ready on both copies."
      }
      if report.preservedDecisions > 0 {
        status += " Preserved \(report.preservedDecisions) newer destination decisions."
      }
      if report.changedSourceReviews > 0 {
        status +=
          " \(report.changedSourceReviews) included source reviews changed since this list was prepared; those later decisions are not part of this copy."
      }
      if report.sameVolumeBackup {
        status +=
          " Both destinations are on the same volume; use another drive for an independent backup."
      }
      status += " Choose Review Copied Photos when ready. The source stays protected."
    }
  }
  func reviewCopiedPhotos() {
    guard let folder = copiedReviewFolder else { return }
    let task = Task { @MainActor [self] in
      await DecisionSaveQueue.shared.flush()
      await openFolder(folder)
      sourceReviewLaunch = UUID()  // close the workflow sheet after explicit navigation
    }
    WorkflowOperationBarrier.shared.track(task)
  }
}
