import PhotoCore
import PhotoImaging
import SwiftUI

/// Stable input equality isolates parent toolbar/status publications. Actions use
/// the owning workspace's stable State storage; all captured display inputs and
/// clipboard availability participate in equality. Photo state is observed here.
struct WorkspaceThumbnail: View, Equatable {
  let photo: PhotoItem
  let state: PhotoThumbnailState
  let selection: WorkspaceSelectionState
  let thumbnails: ImagePipeline
  let sessionID: UUID
  let cacheGeneration: Int
  let thumbnailEdge: Double
  let thumbnailLabels: [ThumbnailInfoField]
  let groupPairs: Bool
  let folderLabel: String?
  let hasCopiedCrop: Bool
  var fixedContentHeight: Double? = nil
  let select: () -> Void
  let action: (ThumbnailAction) -> Void
  let openPreview: () -> Void
  let metadata: () -> Void
  let apply: (Int?, PhotoFlag?) -> Void
  let edit: (PhotoEditAction) -> Void
  let copyCrop: () -> Void
  let pasteCrop: () -> Void

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.photo == rhs.photo && lhs.state === rhs.state && lhs.selection === rhs.selection
      && lhs.thumbnails === rhs.thumbnails && lhs.sessionID == rhs.sessionID
      && lhs.cacheGeneration == rhs.cacheGeneration && lhs.thumbnailEdge == rhs.thumbnailEdge
      && lhs.thumbnailLabels == rhs.thumbnailLabels && lhs.groupPairs == rhs.groupPairs
      && lhs.hasCopiedCrop == rhs.hasCopiedCrop && lhs.folderLabel == rhs.folderLabel
      && lhs.fixedContentHeight == rhs.fixedContentHeight
  }
  private var canEdit: Bool { state.ready && (!state.selected || selection.ready) }
  var body: some View {
    let selected = state.selected
    let decision = state.decision
    let information = thumbnailLabels.map {
      (field: $0, value: $0.label(state.metadata))
    }
    let spokenValue =
      (["\(decision.flag.title), \(decision.rating) stars"] + [folderLabel].compactMap { $0 }
      + information.map(\.value)).joined(
        separator: ", ")
    return VStack(alignment: .leading, spacing: 6) {
      ThumbnailQuickActions(
        filename: photo.filename, selected: selected, canEdit: canEdit,
        action: { action($0) }
      ) {
        Button {
          select()
        } label: {
          PhotoImageView(
            photo: photo, pipeline: thumbnails, maximumPixelSize: 480,
            edit: state.edit, prioritize: selected, sessionID: sessionID,
            cacheGeneration: cacheGeneration
          )
          .frame(height: thumbnailEdge * 0.7).clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(photo.filename)").accessibilityValue(spokenValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .simultaneousGesture(TapGesture(count: 2).onEnded { openPreview() })
      }
      thumbnailDecisions
      Button {
        select()
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          if groupPairs, state.pairedCount > 1 {
            Text("RAW + JPEG").font(.caption2)
          }
          Text(photo.filename).font(.caption).lineLimit(1).truncationMode(.middle)
          if let folderLabel {
            Text(folderLabel).font(.caption2).lineLimit(1).truncationMode(.middle).help(folderLabel)
          }
          thumbnailInformation(information)
        }.foregroundStyle(selected ? Color.white : Color.secondary).frame(
          maxWidth: .infinity, alignment: .leading
        ).contentShape(Rectangle())
      }.buttonStyle(.plain)
      if state.edit.isEdited {
        Text(state.edit.crop != nil ? "Cropped · Photo edit" : "Photo edit")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
    .frame(height: fixedContentHeight.map { CGFloat($0) }, alignment: .top)
    .padding(8)
    .background(
      selected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.025),
      in: RoundedRectangle(cornerRadius: 7)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 7).strokeBorder(
        selected ? Color.accentColor : .clear, lineWidth: 2)
    )
    .contextMenu {
      ForEach([PhotoFlag.pick, .reject, .unflagged], id: \.self) { flag in
        Button(flag.title + " Selection") {
          apply(nil, flag)
        }.disabled(!canEdit)
      }
      Menu("Stars") {
        ForEach(0...5, id: \.self) { rating in
          Button(rating == 0 ? "Clear Stars" : "\(rating) Stars") {
            apply(rating, nil)
          }
        }
      }.disabled(!canEdit)
      Divider()
      ForEach([PhotoEditAction.counterclockwise, .clockwise, .horizontal, .vertical], id: \.self) {
        action in
        Button(action.rawValue + " Selection") {
          edit(action)
        }.disabled(!canEdit)
      }
      Button("Crop…") {
        action(.crop)
      }.disabled(!canEdit)
      Button("Copy Crop") { copyCrop() }.disabled(
        state.edit.crop == nil)
      Button("Paste Crop to Selection") {
        pasteCrop()
      }.disabled(!hasCopiedCrop || !canEdit)
      Button("Clear Crop from Selection") {
        edit(.clearCrop)
      }.disabled(!canEdit)
      Button("Reset Image Edits for Selection") {
        edit(.reset)
      }.disabled(!canEdit)
      Divider()
      Button("Edit IPTC & Keywords…") { metadata() }
    }
  }
  private var thumbnailDecisions: some View {
    let decision = state.decision
    return HStack(spacing: 0) {
      Menu {
        ForEach([PhotoFlag.pick, .reject, .unflagged], id: \.self) { flag in
          Button(flag.title) {
            apply(nil, flag)
          }
        }
      } label: {
        Image(systemName: decision.flag.symbol).frame(width: 18, height: 24)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .accessibilityLabel("Flag \(photo.filename)").accessibilityValue(decision.flag.title).help(
        "Flag this photo, or the selected group when this photo is selected. Reject never deletes files."
      )
      ForEach(1...5, id: \.self) { rating in
        Button {
          let current = state.selected ? selection.summary.rating : decision.rating
          apply(current == rating ? 0 : rating, nil)
        } label: {
          Image(systemName: rating <= decision.rating ? "star.fill" : "star").font(
            .system(size: 11)
          ).frame(maxWidth: .infinity).frame(height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(rating) stars for \(photo.filename)")
          .help(
            "Set \(rating) stars for this photo or selected group. Click the current rating again to clear; flags stay independent."
          )
      }
    }.foregroundStyle(.secondary).disabled(!canEdit)
  }
  private func thumbnailInformation(_ information: [(field: ThumbnailInfoField, value: String)])
    -> some View
  {
    ForEach(information, id: \.field) { item in
      Text(item.value).font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        .help(item.field.title + ": " + item.value)
    }
  }

}
