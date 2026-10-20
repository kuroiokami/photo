import AppKit
import PhotoCore
import SwiftUI
import UniformTypeIdentifiers

private typealias WorkflowStorage<Value> = SwiftUI.State<Value>

struct WorkflowView: View {
  @Environment(\.dismiss) private var dismiss
  @WorkflowStorage private var model: WorkflowModel
  @WorkflowStorage private var tab = 0
  @WorkflowStorage private var scope = "Selection"
  @WorkflowStorage private var source = ""
  @WorkflowStorage private var primary =
    UserDefaults.standard.string(forKey: "Photo.ingestWorkingRoot") ?? ""
  @WorkflowStorage private var backup =
    UserDefaults.standard.string(forKey: "Photo.ingestBackupRoot") ?? ""
  @WorkflowStorage private var job = ""
  @WorkflowStorage private var pattern =
    UserDefaults.standard.string(forKey: "Photo.renamePattern")
    ?? "{date}_{time}_{camera}_{original}"
  @WorkflowStorage private var camera = "C1"
  @WorkflowStorage private var sequence = String(
    max(1, UserDefaults.standard.integer(forKey: "Photo.nextSequence")))
  @WorkflowStorage private var fieldValues: [MetadataField: String] = [:]
  @WorkflowStorage private var enabled: Set<MetadataField> = []
  @WorkflowStorage private var cleared: Set<MetadataField> = []
  @WorkflowStorage private var keywordAction: KeywordAction = .leave
  @WorkflowStorage private var keywordText = ""
  @WorkflowStorage private var presetName = ""
  @WorkflowStorage private var destination = ""
  @WorkflowStorage private var embedMetadata = true

  init(model: WorkflowModel) {
    _model = State(initialValue: model)
    _tab = State(initialValue: model.requestedTab)
  }
  private var patch: MetadataPatch {
    var value = MetadataPatch()
    for field in enabled {
      if cleared.contains(field) {
        value.fields[field] = ""
      } else if let text = fieldValues[field], !text.isEmpty {
        value.fields[field] = text
      }
    }
    value.keywordAction = keywordAction
    value.keywordText = keywordText
    return value
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Photo workflow").font(.title2.bold())
        Spacer()
        if model.busy {
          ProgressView().controlSize(.small)
          Button("Cancel Operation") { model.worker?.cancel() }
        }
        Button(model.busy && model.backgroundable ? "Continue Browsing" : "Done") { dismiss() }
          .keyboardShortcut(.cancelAction).disabled(model.busy && !model.backgroundable)
      }
      Text("Ingest → Cull → Rename → Metadata → Lightroom Classic").font(.callout).foregroundStyle(
        .secondary)
      TabView(selection: $tab) {
        ingest.tabItem { Text("Ingest") }.tag(0)
        rename.tabItem { Text("Bulk Rename") }.tag(1)
        metadata.tabItem { Text("IPTC & Keywords") }.tag(2)
        handoff.tabItem { Text("Lightroom") }.tag(3)
      }
      .disabled(model.busy)
      if !model.pendingRenames.isEmpty {
        HStack {
          Text("\(model.pendingRenames.count) incomplete rename operations need recovery.")
          Button("Recover Original Names") { model.recover() }.disabled(model.busy)
        }
      }
      Text(model.status).font(.callout).textSelection(.enabled).frame(
        maxWidth: .infinity, alignment: .leading)
    }
    .padding(20).frame(width: 880, height: panelHeight)
    .interactiveDismissDisabled(model.busy && !model.backgroundable)
    .task {
      model.renamePlan = nil
      model.metadataPlan = []
      await model.refresh()
      fieldValues = model.currentMetadata.fields
    }
    .onChange(of: tab) { model.requestedTab = tab }
    .onChange(of: pattern) { model.renamePlan = nil }
    .onChange(of: camera) { model.renamePlan = nil }
    .onChange(of: sequence) { model.renamePlan = nil }
    .onChange(of: scope) {
      model.renamePlan = nil
      model.metadataPlan = []
    }
    .onChange(of: fieldValues) { model.metadataPlan = [] }
    .onChange(of: enabled) { model.metadataPlan = [] }
    .onChange(of: cleared) {
      enabled.formUnion(cleared)
      model.metadataPlan = []
    }
    .onChange(of: keywordAction) { model.metadataPlan = [] }
    .onChange(of: keywordText) { model.metadataPlan = [] }
    .onChange(of: model.nextSequence) { sequence = String(model.nextSequence) }
  }
  private var panelHeight: CGFloat {
    let available = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.height ?? 840
    return max(500, min(720, available - 100))
  }
  private var scopePicker: some View {
    Picker("Apply to", selection: $scope) {
      Text("Selection").tag("Selection")
      Text("Visible photos").tag("Visible")
      Text("All files in folder").tag("All files")
    }.pickerStyle(.segmented)
  }
  private var ingest: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        "Copy supported photos and their XMP/ACR companions to two destinations. Card subfolders are preserved. Existing matching files are reverified; different files are never overwritten."
      ).fixedSize(horizontal: false, vertical: true)
      pathRow("Card / source", path: $source)
      pathRow("Working root", path: $primary)
      pathRow("Backup root", path: $backup)
      HStack {
        Text("Job folder").frame(width: 125, alignment: .leading)
        TextField("e.g. 2026-10-19_Birding", text: $job).textFieldStyle(.roundedBorder)
          .help(
            "A single shoot folder name. Both destinations receive this folder with an Originals subfolder."
          )
      }
      Button("Remember Destination Roots") {
        UserDefaults.standard.set(primary, forKey: "Photo.ingestWorkingRoot")
        UserDefaults.standard.set(backup, forKey: "Photo.ingestBackupRoot")
        model.status = "Destination roots saved; each shoot still needs its own job folder."
      }.disabled(primary.isEmpty || backup.isEmpty)
      Text(
        "Each destination receives Job/Originals. Keep the card until both copies are verified; a second folder on the same drive is not an independent backup."
      ).font(.caption).foregroundStyle(.secondary)
      Button("Ingest & Verify Both Copies") {
        model.ingest(source: source, primary: primary, backup: backup, job: job)
      }
      .disabled(source.isEmpty || primary.isEmpty || backup.isEmpty || job.isEmpty)
      if let folder = model.handoffFolder {
        Button("Reveal Latest Destination") {
          NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
      }
      Spacer()
    }.padding()
  }
  private var rename: some View {
    VStack(alignment: .leading, spacing: 12) {
      scopePicker
      Text(
        "Rename before Lightroom import. A unique RAW+JPEG pair consumes one sequence; matching XMP and ACR files follow it. Camera times without offsets are interpreted consistently as wall-clock time; offset-tagged times use UTC."
      ).font(.caption).foregroundStyle(.secondary)
      LabeledContent("Naming template") {
        TextField("Naming template", text: $pattern).textFieldStyle(.roundedBorder)
      }
      Text("Tokens: {date} {time} {camera} {original} {sequence}").font(.caption.monospaced())
      HStack {
        LabeledContent("Camera") { TextField("Camera label", text: $camera).frame(width: 100) }
        LabeledContent("Sequence") { TextField("Start sequence", text: $sequence).frame(width: 90) }
          .help("A whole number starting at 1; unique RAW+JPEG pairs share a number.")
        Button("Save Template") {
          UserDefaults.standard.set(pattern, forKey: "Photo.renamePattern")
          model.status = "Naming template saved."
        }
      }.textFieldStyle(.roundedBorder)
      HStack {
        Button("Preview Names") {
          model.previewRename(scope: scope, pattern: pattern, camera: camera, sequence: sequence)
        }.disabled(model.targets(scope).isEmpty || pattern.isEmpty || (Int(sequence) ?? 0) < 1)
          .help("Review every filename and companion before changing names.")
        Button("Apply Reviewed Rename") { model.applyRename() }.disabled(
          model.renamePlan?.entries.isEmpty != false)
        Button("Undo Last Rename") { model.undoRename() }.disabled(model.lastRenameJournal == nil)
      }
      if let plan = model.renamePlan {
        Text("\(plan.entries.count) file changes · next sequence \(plan.nextSequence)").font(
          .caption)
        List(plan.entries) { entry in
          HStack {
            Text(entry.original.lastPathComponent)
            Image(systemName: "arrow.right")
            Text(entry.destination.lastPathComponent).bold()
          }.font(.caption.monospaced()).textSelection(.enabled)
        }
      } else {
        ContentUnavailableView("Preview a rename first", systemImage: "character.cursor.ibeam")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
  private var metadata: some View {
    let targetCount = model.targets(scope).count
    let targetDescription = "\(targetCount) target " + (targetCount == 1 ? "file" : "files")
    let validKeywords =
      keywordAction == .leave || keywordAction == .clear
      || !keywordText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return VStack(alignment: .leading, spacing: 10) {
      scopePicker
      HStack {
        Menu("Load Preset") {
          ForEach(model.presets) { preset in Button(preset.name) { load(preset.patch) } }
        }.frame(width: 140).disabled(model.presets.isEmpty).help(
          "Load shared fields from a saved metadata preset.")
        TextField("Preset name", text: $presetName)
        Button("Save Preset") { model.savePreset(name: presetName, patch: patch) }
          .disabled(
            presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || (patch.fields.isEmpty && keywordAction == .leave) || !validKeywords
          )
          .help(
            "Save the checked fields and keyword action for reuse; unselected fields are excluded.")
      }
      Text(
        "Only checked, nonempty fields change. Choose Clear to remove a value. Other properties and develop settings are preserved; source image bytes are never edited. JPEG/PNG sidecar recognition varies by application."
      ).font(.caption).foregroundStyle(.secondary)
      Text(
        "Values from: \(model.workspace.firstSelectedPhoto?.filename ?? "No selected photo") · \(targetDescription). Other photos may have different values."
      )
      .font(.caption).foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(MetadataField.allCases) { field in
            HStack {
              Toggle(field.rawValue, isOn: membership(field, in: $enabled)).toggleStyle(.checkbox)
                .frame(width: 190, alignment: .leading)
                .help(
                  "Include only this field in the combined preview. Unchecked fields stay unchanged."
                )
              TextField(
                field.rawValue,
                text: Binding(
                  get: { fieldValues[field] ?? "" },
                  set: {
                    fieldValues[field] = $0
                    enabled.insert(field)
                  })
              ).disabled(cleared.contains(field))
              Toggle("Clear", isOn: membership(field, in: $cleared)).toggleStyle(.checkbox)
                .help("Explicitly remove this field from the target photos.")
              Button {
                model.previewField(
                  field, value: fieldValues[field] ?? "", clear: cleared.contains(field),
                  scope: scope)
              } label: {
                Label("Preview Field", systemImage: "eye")
              }
              .disabled(
                targetCount == 0 || (!cleared.contains(field) && (fieldValues[field] ?? "").isEmpty)
              )
              .accessibilityLabel("Preview only " + field.rawValue)
              .help(
                "Preview only \(field.rawValue) for \(targetDescription). Every other field stays unchanged, including other checked fields."
              )
            }
          }
          Divider()
          HStack {
            Picker("Keywords", selection: $keywordAction) {
              ForEach(KeywordAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Menu("Recent / saved vocabulary") {
              ForEach(model.vocabulary.prefix(50), id: \.self) { word in
                Button(word) {
                  keywordText += (keywordText.isEmpty ? "" : "\n") + word
                  if keywordAction == .leave { keywordAction = .append }
                }
              }
            }.disabled(model.vocabulary.isEmpty)
          }
          Text(
            "One keyword or hierarchy per line, e.g. Wildlife|Birds|Herons|Great Blue Heron. Append preserves existing tags; Replace/Clear are explicit."
          ).font(.caption)
          TextEditor(text: $keywordText).font(.body.monospaced()).frame(minHeight: 75)
            .disabled(keywordAction == .leave || keywordAction == .clear)
            .overlay(alignment: .topLeading) {
              if keywordAction == .leave || keywordAction == .clear {
                Text(
                  keywordAction == .leave
                    ? "Choose a keyword action to edit tags."
                    : "Existing keywords will be cleared after review."
                )
                .font(.caption).foregroundStyle(.secondary).padding(6).allowsHitTesting(false)
              }
            }
            .help(
              "Choose Append, Replace or Remove and enter keywords. Choose Clear explicitly to remove all keywords."
            )
          Text("Current keywords: \(model.currentMetadata.keywords.joined(separator: ", "))").font(
            .caption)
          ForEach(model.metadataPlan) { plan in
            DisclosureGroup(plan.image.lastPathComponent) {
              ForEach(plan.fields.sorted(by: { $0.rawValue < $1.rawValue })) { field in
                Text(
                  "\(field.rawValue): \(plan.before.fields[field] ?? "—") → \(plan.after.fields[field].flatMap { $0.isEmpty ? nil : $0 } ?? "[Clear]")"
                ).font(.caption).textSelection(.enabled)
              }
              if plan.changesKeywords {
                Text(
                  "Keywords: \(plan.before.keywords.joined(separator: ", ")) → \(plan.after.keywords.joined(separator: ", "))"
                ).font(.caption).textSelection(.enabled)
                Text("Hierarchy: \(plan.after.hierarchy.joined(separator: ", "))").font(.caption)
                  .textSelection(.enabled)
              }
            }
          }
          ForEach(model.metadataResults.keys.sorted(), id: \.self) { path in
            VStack(alignment: .leading) {
              Text(
                "\(URL(fileURLWithPath: path).lastPathComponent): \(model.metadataResults[path] ?? "")"
              ).font(.caption)
              if model.metadataResults[path] != "Saved" {
                HStack {
                  Button("Retry") { model.resolveMetadata(path: path, choice: "Retry") }
                  Button("Use Local Metadata") {
                    model.resolveMetadata(path: path, choice: "Local")
                  }
                  Button("Use External Metadata") {
                    model.resolveMetadata(path: path, choice: "External")
                  }
                }.font(.caption)
              }
            }
          }
        }.textFieldStyle(.roundedBorder)
      }
      HStack {
        Button("Preview Metadata Changes") { model.previewMetadata(patch, scope: scope) }
          .disabled(
            targetCount == 0 || (patch.fields.isEmpty && keywordAction == .leave) || !validKeywords
          )
          .help("Review exactly the checked fields and explicit keyword action before writing.")
        Button(
          model.metadataPlan.isEmpty
            ? "Apply Reviewed Fields" : "Apply to \(model.metadataPlan.count) Files"
        ) {
          model.applyMetadata()
        }.disabled(
          model.metadataPlan.isEmpty)
        Text(
          model.metadataPlan.first.map { plan in
            plan.fields.map(\.rawValue).sorted().joined(separator: ", ")
              + (plan.changesKeywords ? " · Keywords" : "")
          } ?? "Preview changes first"
        ).font(.caption).lineLimit(2)
      }
    }.padding()
  }
  private var handoff: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(
          "Prepare a verified copy of all non-rejected photos in the current folder, including their XMP/ACR companions. This optional handoff uses extra disk space and leaves the source library in place."
        )
        pathRow("New handoff folder", path: $destination)
        Toggle("Embed metadata in derived JPEG/PNG handoff copies", isOn: $embedMetadata)
          .toggleStyle(
            .checkbox)
        Text(
          "This changes metadata bytes in the handoff copies, preserving their image data. Source JPEG/PNG files stay untouched. RAW files continue to use XMP sidecars."
        ).font(.caption).foregroundStyle(.secondary)
        Button("Verify Metadata & Copy Non-Rejected Photos") {
          model.prepareLightroom(destination: destination, embedMetadata: embedMetadata)
        }.disabled(destination.isEmpty)
        if let folder = model.handoffFolder {
          Button("Reveal Prepared Folder") {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
          }
        }
        Divider()
        Text("In Lightroom Classic").font(.headline)
        Text(
          "1. Import the prepared folder with Add.\n2. Use Embedded & Sidecar previews for fast initial browsing.\n3. Avoid an import preset that overwrites prepared metadata.\n4. Verify stars, flags, captions and keyword hierarchy on a small set.\n5. After import, rename/move photos inside Lightroom. Save Lightroom metadata before any intentional external round trip."
        )
        Text(
          "Lightroom Classic 13.2+ can store flags in XMP; 15+ may also use ACR sidecars. Actual application-level interchange remains a verification task. This app does not modify a Lightroom catalog or automate its import."
        ).font(.caption).foregroundStyle(.secondary)
      }.padding().frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private func pathRow(_ label: String, path: Binding<String>) -> some View {
    HStack {
      Text(label).frame(width: 125, alignment: .leading)
      TextField("Absolute folder path", text: path).textFieldStyle(.roundedBorder)
        .accessibilityLabel(label + " folder path")
      Button("Choose…") {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { path.wrappedValue = url.path }
      }.accessibilityLabel("Choose " + label + " folder")
    }
  }
  private func membership(_ field: MetadataField, in set: Binding<Set<MetadataField>>) -> Binding<
    Bool
  > {
    Binding(
      get: { set.wrappedValue.contains(field) },
      set: { value in
        if value { set.wrappedValue.insert(field) } else { set.wrappedValue.remove(field) }
      })
  }
  private func load(_ patch: MetadataPatch) {
    fieldValues = patch.fields
    enabled = Set(patch.fields.keys)
    cleared = Set(patch.fields.filter { $0.value.isEmpty }.keys)
    keywordAction = patch.keywordAction
    keywordText = patch.keywordText
  }
}
