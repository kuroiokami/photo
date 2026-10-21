import AppKit
import PhotoCore
import SwiftUI

private typealias IngestStorage<Value> = SwiftUI.State<Value>

/// A bounded setup flow. Long inventories and recovery details use separate sheets.
struct IngestWorkflowView: View {
  enum Step: Int, CaseIterable {
    case source, destinations, confirm, copying
    var title: String {
      switch self {
      case .source: "Choose photos"
      case .destinations: "Set up copies"
      case .confirm: "Review & copy"
      case .copying: "Copying"
      }
    }
  }

  let model: WorkflowModel
  let showWalkthrough: () -> Void
  @Environment(\.dismiss) private var dismiss
  @AppStorage(WorkflowGuidance.dismissalKey) private var hideIntroduction = false
  @IngestStorage private var introductionDismissed = false
  @IngestStorage private var step: Step
  @IngestStorage private var cullFirst = true
  @IngestStorage private var source: String
  @IngestStorage private var primary =
    UserDefaults.standard.string(forKey: "Photo.ingestWorkingRoot")
    ?? UserDefaults.standard.string(forKey: "Photo.folders.home") ?? ""
  @IngestStorage private var backup =
    UserDefaults.standard.string(forKey: "Photo.ingestBackupRoot") ?? ""
  @IngestStorage private var job = ""
  @IngestStorage private var scope = ReviewedCopyScope.picks
  @IngestStorage private var keepPairs = true
  @IngestStorage private var acceptMetadataChanges = false
  @IngestStorage private var includeOpposingPairs = false
  @IngestStorage private var showingFiles = false
  @IngestStorage private var showingAdvanced = false
  @IngestStorage private var showingSaved = false
  @IngestStorage private var showingPending = false
  @IngestStorage private var resumePlan: ReviewedCopyPlan?

  init(model: WorkflowModel, showWalkthrough: @escaping () -> Void) {
    self.model = model
    self.showWalkthrough = showWalkthrough
    _source = State(initialValue: model.workspace.sourceReview?.root.path ?? "")
    _step = State(
      initialValue: model.busy && model.backgroundable
        ? .copying : (model.opensReviewedCopySetup ? .destinations : .source))
  }

  private var reviewedSource: Bool {
    guard let root = model.workspace.sourceReview?.root, !source.isEmpty else { return false }
    return PhotoPath.canonical(URL(fileURLWithPath: source)) == root
  }
  private var ready: Bool {
    [source, primary, backup, job].allSatisfy {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 14) {
        ForEach(Step.allCases, id: \.self) { item in
          Label(
            item.title, systemImage: "\(item.rawValue + 1).circle\(step == item ? ".fill" : "")"
          )
          .font(.callout.weight(step == item ? .semibold : .regular))
          .foregroundStyle(step == item ? Color.accentColor : Color.secondary)
        }
        Spacer(minLength: 0)
      }
      Divider()
      Group {
        switch step {
        case .source: sourcePage
        case .destinations: destinationsPage
        case .confirm: confirmationPage
        case .copying: copyingPage
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      if !hideIntroduction && !introductionDismissed {
        HStack {
          Label("Need a hand?", systemImage: "lightbulb")
          Button("Show Walkthrough", action: showWalkthrough)
          Spacer()
          Button("Not Now") { introductionDismissed = true }
          Button("Don’t Show Again") { hideIntroduction = true }
        }.font(.caption)
      }
      if !model.savedReviewCopies.isEmpty && step != .copying {
        Button("Resume a Saved Copy…") { showingSaved = true }
          .font(.caption)
      }
    }
    .padding(14)
    .sheet(isPresented: $showingFiles) { copyDetails }
    .sheet(isPresented: $showingSaved) { savedCopies }
    .sheet(isPresented: $showingPending) { pendingMetadata }
    .onChange(of: source) { invalidate() }
    .onChange(of: primary) { invalidate() }
    .onChange(of: backup) { invalidate() }
    .onChange(of: job) { invalidate() }
    .onChange(of: scope) { invalidate() }
    .onChange(of: keepPairs) { invalidate() }
    .onChange(of: acceptMetadataChanges) { invalidate() }
    .onChange(of: showingSaved) { if showingSaved { includeOpposingPairs = false } }
    .onChange(of: model.reviewedCopyPlan?.id) {
      if model.reviewedCopyPlan != nil { step = .confirm }
    }
    .onChange(of: model.busy) {
      if model.busy && model.backgroundable { step = .copying }
    }
  }

  private var sourcePage: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Where are the photos?").font(.title3.bold())
      folderRow("Card or folder", path: $source, accessibility: "Source folder")
      Text(
        "Choose your card or photo folder. Start Culling opens it in the main window; expand the sidebar folders to reach DCIM or other subfolders."
      )
      .font(.callout).foregroundStyle(.secondary)
      Picker("How would you like to start?", selection: $cullFirst) {
        Text("Choose keepers before copying").tag(true)
        Text("Copy the entire shoot first").tag(false)
      }.pickerStyle(.segmented)
      if cullFirst {
        Text("1. Start culling → 2. Press P on keepers → 3. Copy Reviewed Photos")
          .font(.headline)
        Text(
          "Browse thumbnails and use P / X / U or stars. Nothing is copied yet, and Photo keeps the source unchanged. When ready, the banner above your photos takes you to copy setup."
        )
        .font(.callout).foregroundStyle(.secondary)
      } else {
        Text("Copy everything, then choose keepers as verified photos arrive.")
          .font(.headline)
        Text(
          "Next, choose a Photo folder, a Backup folder and a name for this shoot. Both copies are checked before photos become available for culling."
        )
        .font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      HStack {
        if reviewedSource {
          Button("Copy Existing Picks…") { step = .destinations }
        }
        Spacer()
        Button(cullFirst ? "Start Culling" : "Set Up Copies →") {
          if cullFirst {
            model.startSourceReview(source: source)
          } else {
            scope = .all
            step = .destinations
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }

  private var destinationsPage: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(reviewedSource ? "Copy your keepers" : "Set up this shoot").font(.title3.bold())
      location("From", path: source)
      folderRow("Photo folder", path: $primary)
      folderRow("Backup folder", path: $backup)
      HStack {
        Text("Shoot name").frame(width: 105, alignment: .leading)
        TextField("e.g. 2026-10-20_Match", text: $job).textFieldStyle(.roundedBorder)
          .accessibilityLabel("Shoot name")
      }
      if reviewedSource {
        Picker("Photos to copy", selection: $scope) {
          ForEach(ReviewedCopyScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Text(
          scope == .selection
            ? "Copies the thumbnails you selected in the main window, plus required companions."
            : "Picks Only copies photos marked P across this source and its subfolders. Other choices can include unreviewed photos."
        )
        .font(.caption).foregroundStyle(.secondary)
        HStack {
          Toggle("Keep RAW+JPEG pairs together", isOn: $keepPairs)
          Spacer()
          Button("More Options…") { showingAdvanced = true }
            .popover(isPresented: $showingAdvanced) {
              VStack(alignment: .leading, spacing: 10) {
                Toggle("Use Updated Source Metadata", isOn: $acceptMetadataChanges)
                Text(
                  "Use only after inspecting an external sidecar change. Your local stars/flags stay; other fields use the current source metadata. Photo never writes to the source."
                )
                .font(.caption)
              }.padding().frame(width: 380)
            }
        }
      } else {
        Text(
          "All supported photos and metadata files in this folder and its subfolders will be copied."
        )
        .font(.callout).foregroundStyle(.secondary)
      }
      HStack {
        Button("Remember These Folders") {
          UserDefaults.standard.set(primary, forKey: "Photo.ingestWorkingRoot")
          UserDefaults.standard.set(backup, forKey: "Photo.ingestBackupRoot")
          model.status = "Photo and backup folders remembered."
        }.disabled(primary.isEmpty || backup.isEmpty)
        Text(
          "Each location gets Shoot name / Originals. Use separate drives for an independent backup."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      HStack {
        Button("Back") { step = .source }
        if reviewedSource {
          Button("Return to Culling") { dismiss() }
        }
        Spacer()
        Button("Review Copy Setup →") {
          if reviewedSource {
            model.prepareReviewedCopy(
              source: source, scope: scope, primary: primary,
              backup: backup, job: job, keepPairs: keepPairs,
              acceptMetadataChanges: acceptMetadataChanges)
          } else {
            step = .confirm
          }
        }.buttonStyle(.borderedProminent).disabled(!ready)
      }
    }
  }

  private var confirmationPage: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Ready to copy?").font(.title3.bold())
      if let plan = model.reviewedCopyPlan {
        Text(
          "\(plan.scope.rawValue) · Photos: \(plan.images.count) · Files: \(plan.files.count) · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: plan.bytes), countStyle: .file)) per copy"
        )
        .font(.headline)
        Text(
          "\(plan.images.filter { $0.reviewed }.count) reviewed · \(plan.images.filter { !$0.reviewed }.count) unreviewed included"
        )
        if let total = plan.sourcePhotoCount, let omitted = plan.omittedUnreviewedCount {
          Text(
            "Source: \(total) photos · \(omitted) unreviewed left behind · \(plan.otherFileCount ?? 0) other files excluded"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        location("Photo copy", path: plan.primary.path)
        location("Backup copy", path: plan.backup.path)
        HStack {
          Text("\(plan.addedPairImages.count) RAW/JPEG companions added")
          Button("View Files & Details…") { showingFiles = true }
        }.font(.caption)
        if !plan.opposingPairImages.isEmpty {
          Toggle(
            "Include \(plan.opposingPairImages.count) companions with opposing flags",
            isOn: $includeOpposingPairs)
        }
        Text(
          "This list is fixed. Stars, flags and Photo-local edits go to both copies. Later source decisions need a new list; crops are not rendered into delivery images."
        )
        .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Copy the entire shoot and verify both destinations.").font(.headline)
        location("From", path: source)
        location("Photo copy", path: primary + "/" + job + "/Originals")
        location("Backup copy", path: backup + "/" + job + "/Originals")
        Text(
          "Keep your card until both copies are verified. You can continue browsing while Photo copies."
        )
        .font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      HStack {
        Button("Back") { step = .destinations }
        Spacer()
        Button("Copy & Verify Both Copies") {
          if let plan = model.reviewedCopyPlan {
            model.copyReviewed(plan, includeOpposingPairs: includeOpposingPairs)
          } else if !reviewedSource {
            model.ingest(source: source, primary: primary, backup: backup, job: job)
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          !ready || (reviewedSource && model.reviewedCopyPlan == nil)
            || (model.reviewedCopyPlan?.opposingPairImages.isEmpty == false
              && !includeOpposingPairs)
        )
      }
    }
  }

  private var copyingPage: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(
        model.busy ? "Copying and verifying" : "Copy status",
        systemImage: model.busy ? "externaldrive.badge.timemachine" : "doc.text.magnifyingglass"
      )
      .font(.title3.bold())
      Text(model.status).font(.callout).lineLimit(7)
      if model.reviewMetadataPending > 0 {
        Button("Metadata Needs Attention…") { showingPending = true }
      }
      if model.copiedReviewFolder != nil {
        Button("Review Copied Photos") { model.reviewCopiedPhotos() }
          .buttonStyle(.borderedProminent)
      }
      if let folder = model.handoffFolder {
        Button("Reveal Latest Destination") {
          NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
      }
      Spacer(minLength: 0)
      HStack {
        if !model.busy {
          Button("Back to Setup") { step = .destinations }
          if !model.savedReviewCopies.isEmpty {
            Button("Resume a Saved Copy…") { showingSaved = true }
          }
        }
        Spacer()
        if !model.busy { Button("Return to Photos") { dismiss() } }
      }
    }
  }

  private var copyDetails: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Copy list details").font(.title2.bold())
      if let plan = model.reviewedCopyPlan {
        Text(
          "Groups: \(plan.families.count) · \(plan.sourceUnreviewedCount.map(String.init) ?? "Not counted") unreviewed on source"
        )
        Text("Photo folder: \(plan.primary.path)\nBackup folder: \(plan.backup.path)")
          .font(.caption).textSelection(.enabled)
        List(plan.files, id: \.relative) { file in
          VStack(alignment: .leading) {
            Text(file.relative)
            if plan.addedPairImages.contains(file.source) {
              Text("Added RAW/JPEG companion").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      HStack {
        Spacer()
        Button("Done") { showingFiles = false }.keyboardShortcut(.cancelAction)
      }
    }.padding(20).frame(width: 680, height: 440)
  }

  private var savedCopies: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Resume a Saved Copy").font(.title2.bold())
      Text(
        "Continue the original list and destinations. New decisions need a fresh list and shoot folder; newer destination work is preserved."
      ).font(.callout)
      Picker(
        "Saved copy",
        selection: Binding(
          get: { resumePlan?.id ?? model.savedReviewCopies.first?.id },
          set: { id in resumePlan = model.savedReviewCopies.first { $0.id == id } }
        )
      ) {
        ForEach(model.savedReviewCopies) { plan in
          Text(
            "\(plan.primary.deletingLastPathComponent().lastPathComponent) · \(plan.scope.rawValue)"
          )
          .tag(Optional(plan.id))
        }
      }
      if let plan = resumePlan ?? model.savedReviewCopies.first {
        Text(
          "Photos: \(plan.images.count)\nFrom: \(plan.session.root.path)\nPhoto copy: \(plan.primary.path)\nBackup: \(plan.backup.path)"
        ).font(.caption).textSelection(.enabled)
        if !plan.opposingPairImages.isEmpty {
          Toggle("Include companions with opposing flags", isOn: $includeOpposingPairs)
        }
        Spacer(minLength: 0)
        HStack {
          Button("Close") { showingSaved = false }.keyboardShortcut(.cancelAction)
          Spacer()
          Button("Resume Saved Copy") {
            showingSaved = false
            model.copyReviewed(plan, includeOpposingPairs: includeOpposingPairs)
          }.buttonStyle(.borderedProminent)
            .disabled(!plan.opposingPairImages.isEmpty && !includeOpposingPairs)
        }
      }
    }.padding(20).frame(width: 680, height: 330)
      .onChange(of: resumePlan?.id) { includeOpposingPairs = false }
  }

  private var pendingMetadata: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Destination metadata needs attention").font(.title2.bold())
      List(model.reviewMetadataPendingImages, id: \.self) { Text($0.path).textSelection(.enabled) }
      Button("Done") { showingPending = false }.keyboardShortcut(.cancelAction)
    }.padding(20).frame(width: 680, height: 400)
  }

  private func invalidate() {
    model.reviewedCopyPlan = nil
    includeOpposingPairs = false
  }
  private func location(_ label: String, path: String) -> some View {
    HStack {
      Text(label).frame(width: 105, alignment: .leading)
      Text(path).lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(path)
    }.font(.callout)
  }
  private func folderRow(_ label: String, path: Binding<String>, accessibility: String? = nil)
    -> some View
  {
    HStack {
      Text(label).frame(width: 105, alignment: .leading)
      TextField("Choose a folder…", text: path).textFieldStyle(.roundedBorder)
        .accessibilityLabel(accessibility ?? label)
      Button("Choose…") {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Choose " + label
        panel.prompt = "Use This Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = label != "Card or folder"
        panel.allowsMultipleSelection = false
        if !path.wrappedValue.isEmpty {
          panel.directoryURL = URL(fileURLWithPath: path.wrappedValue)
        }
        if panel.runModal() == .OK, let url = panel.url { path.wrappedValue = url.path }
      }.accessibilityLabel("Choose " + (accessibility ?? label))
    }
  }
}
