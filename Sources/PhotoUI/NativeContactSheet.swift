import AppKit
import PhotoCore
import QuartzCore
import SwiftUI

/// AppKit owns scrolling, item reuse and geometry. SwiftUI observes only each
/// bound tile's state; scrolling publishes no per-tile geometry preferences.
struct NativeContactSheet: NSViewRepresentable {
  let workspace: WorkspaceState
  let columns: Int
  let thumbnailEdge: Double
  let availableWidth: Double
  let labels: [ThumbnailInfoField]
  let folderLabels: Bool
  let cacheGeneration: Int
  let hasCopiedCrop: Bool
  let content: (PhotoItem, Double) -> AnyView
  let navigate: (Int, Bool) -> Void
  let preview: (Bool) -> Void
  let magnify: (Double) -> Void

  // Reserve one composition-status line so an edit doesn't move the rows.
  var itemHeight: Double {
    thumbnailEdge * 0.7 + 88 + Double(labels.count) * 16
      + (folderLabels ? 16 : 0) + (workspace.groupPairs ? 16 : 0)
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView { makeView(coordinator: context.coordinator) }
  func makeView(coordinator: Coordinator) -> NSScrollView {
    let scroll = ContactSheetScrollView(
      frame: NSRect(x: 0, y: 0, width: availableWidth, height: 600))
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    let collection = ContactCollectionView(
      frame: NSRect(x: 0, y: 0, width: availableWidth, height: 1))
    collection.autoresizingMask = [.width]
    let layout = NSCollectionViewFlowLayout()
    layout.minimumInteritemSpacing = 12
    layout.minimumLineSpacing = 16
    layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    collection.collectionViewLayout = layout
    collection.backgroundColors = [.clear]
    collection.isSelectable = true
    collection.allowsMultipleSelection = true
    collection.allowsEmptySelection = true
    collection.register(ContactSheetItem.self, forItemWithIdentifier: ContactSheetItem.reuseID)
    collection.dataSource = coordinator
    collection.delegate = coordinator
    collection.keyAction = { [weak coordinator] in
      coordinator?.key($0) ?? false
    }
    collection.selectionChanged = { [weak coordinator] paths in
      coordinator?.nativeSelection(paths, focus: nil)
    }
    collection.zoom = { [weak coordinator] in coordinator?.parent.magnify($0)
    }
    scroll.viewportChanged = { [weak coordinator] in
      guard let coordinator else { return }
      coordinator.update(coordinator.parent)
    }
    scroll.documentView = collection
    coordinator.collection = collection
    coordinator.scroll = scroll
    coordinator.update(self)
    return scroll
  }
  func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.update(self) }
  static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
    (nsView as? ContactSheetScrollView)?.viewportChanged = nil
    coordinator.collection?.dataSource = nil
    coordinator.collection?.delegate = nil
    coordinator.collection?.selectionChanged = nil
    coordinator.collection?.keyAction = nil
    coordinator.collection?.zoom = nil
    for item in coordinator.collection?.visibleItems() ?? [] {
      (item as? ContactSheetItem)?.unbind()
    }
  }

  @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate
  {
    var parent: NativeContactSheet
    weak var collection: ContactCollectionView?
    weak var scroll: NSScrollView?
    private(set) var photos: [PhotoItem] = []
    private var indices: [String: Int] = [:]
    private var session: UUID?
    private var configuration: Configuration?
    private var reveal: Int?
    private var selected: Set<String> = []
    private var updating = false
    private(set) var reloadCount = 0
    private(set) var bindCount = 0

    private struct Configuration: Equatable {
      let size: NSSize
      let generation: Int
      let copiedCrop: Bool
      let labels: [ThumbnailInfoField]
      let folders: Bool
      let pairs: Bool
    }
    init(_ parent: NativeContactSheet) { self.parent = parent }

    func update(_ value: NativeContactSheet) {
      guard !updating else { return }
      parent = value
      guard let collection, let scroll,
        let layout = collection.collectionViewLayout as? NSCollectionViewFlowLayout
      else { return }
      updating = true
      defer { updating = false }
      // Arrays share their immutable storage on focus/selection updates. Only
      // inventory/order/filter changes need a new index and collection reload.
      let replaced = session != value.workspace.sessionID || photos != value.workspace.photos
      if replaced {
        session = value.workspace.sessionID
        photos = value.workspace.photos
        indices = Dictionary(
          photos.enumerated().map { ($0.element.id, $0.offset) },
          uniquingKeysWith: { first, _ in first })
      }
      let width =
        scroll.contentSize.width > 1 ? scroll.contentSize.width : max(1, value.availableWidth)
      let count = max(1, value.columns)
      let itemWidth = max(1, floor((width - 32 - CGFloat(count - 1) * 12) / CGFloat(count)))
      let config = Configuration(
        size: NSSize(width: itemWidth, height: value.itemHeight),
        generation: value.cacheGeneration, copiedCrop: value.hasCopiedCrop,
        labels: value.labels, folders: value.folderLabels, pairs: value.workspace.groupPairs)
      let reflow = configuration?.size != config.size
      let rebind = configuration != config
      configuration = config
      if reflow {
        layout.itemSize = config.size
        layout.invalidateLayout()
      }
      if replaced {
        reloadCount += 1
        collection.reloadData()
      } else if rebind {
        for case let item as ContactSheetItem in collection.visibleItems() {
          if let path = collection.indexPath(for: item) { bind(item, at: path.item) }
        }
      }
      if replaced || selected != value.workspace.selectedIDs {
        selected = value.workspace.selectedIDs
        let paths = Set(selected.compactMap { indices[$0].map { IndexPath(item: $0, section: 0) } })
        if collection.selectionIndexPaths != paths { collection.selectionIndexPaths = paths }
      }
      let focus = value.workspace.selectedIndex
      if replaced || reflow || reveal != focus {
        reveal = focus
        collection.layoutSubtreeIfNeeded()
        if let focus, photos.indices.contains(focus) {
          collection.scrollToItems(
            at: [IndexPath(item: focus, section: 0)], scrollPosition: .centeredVertically)
        }
      }
    }
    private func bind(_ item: ContactSheetItem, at index: Int) {
      guard photos.indices.contains(index), let height = configuration?.size.height else { return }
      bindCount += 1
      let photo = photos[index]
      item.bind(
        parent.content(photo, height - 16).id(photo.id)
          .environment(\.colorScheme, .dark))
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int)
      -> Int
    {
      photos.count
    }
    func collectionView(
      _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
      let item = collectionView.makeItem(withIdentifier: ContactSheetItem.reuseID, for: indexPath)
      if let item = item as? ContactSheetItem { bind(item, at: indexPath.item) }
      return item
    }
    func collectionView(
      _ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
      forRepresentedObjectAt indexPath: IndexPath
    ) {
      (item as? ContactSheetItem)?.unbind()
    }
    func nativeSelection(_ paths: Set<IndexPath>, focus: Int?) {
      guard !updating else { return }
      let ids = Set(
        paths.compactMap { photos.indices.contains($0.item) ? photos[$0.item].id : nil })
      let id = focus.flatMap { photos.indices.contains($0) ? photos[$0].id : nil }
      parent.workspace.selectGroup(ids, focus: id)
      // Native marquee/click selection already targets this viewport; don't
      // recenter the sheet in response to our own selection publication.
      reveal = parent.workspace.selectedIndex
      selected = ids
    }
    func collectionView(
      _ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
      nativeSelection(collectionView.selectionIndexPaths, focus: indexPaths.map(\.item).min())
    }
    func collectionView(
      _ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>
    ) {
      nativeSelection(collectionView.selectionIndexPaths, focus: nil)
    }
    func key(_ event: NSEvent) -> Bool {
      // Text editors/menu commands retain the normal AppKit responder chain.
      guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
        return false
      }
      let offset: Int
      switch event.keyCode {
      case 123: offset = -1
      case 124: offset = 1
      case 125: offset = max(1, parent.columns)
      case 126: offset = -max(1, parent.columns)
      case 115: offset = Int.min
      case 119: offset = Int.max
      case 49:
        parent.preview(true)
        return true
      case 53:
        parent.preview(false)
        return true
      default: return false
      }
      parent.navigate(offset, event.modifierFlags.contains(.shift))
      update(parent)
      return true
    }
  }
}

@MainActor final class ContactCollectionView: NSCollectionView {
  var keyAction: ((NSEvent) -> Bool)?
  var zoom: ((Double) -> Void)?
  var selectionChanged: ((Set<IndexPath>) -> Void)?

  override func mouseDown(with event: NSEvent) {
    let start = convert(event.locationInWindow, from: nil)
    guard indexPathForItem(at: start) == nil, let window else {
      super.mouseDown(with: event)
      return
    }
    window.makeFirstResponder(self)
    let base =
      event.modifierFlags.intersection([.command, .shift]).isEmpty
      ? Set<IndexPath>() : selectionIndexPaths
    let outline = CAShapeLayer()
    outline.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
    outline.strokeColor = NSColor.controlAccentColor.cgColor
    outline.lineWidth = 1
    outline.zPosition = 10000
    wantsLayer = true
    layer?.addSublayer(outline)
    defer { outline.removeFromSuperlayer() }
    // Track background drags here: a hosted SwiftUI button must not turn the
    // final mouse-up into a single-photo click after a group drag.
    while true {
      guard
        let next = window.nextEvent(
          matching: [.leftMouseDragged, .leftMouseUp],
          until: Date(timeIntervalSinceNow: 0.1), inMode: .eventTracking, dequeue: true)
      else {
        if !window.isKeyWindow || NSEvent.pressedMouseButtons & 1 == 0 { break }
        continue
      }
      let end = convert(next.locationInWindow, from: nil)
      let rect = CGRect(
        x: min(start.x, end.x), y: min(start.y, end.y),
        width: abs(start.x - end.x), height: abs(start.y - end.y))
      outline.path = CGPath(rect: rect, transform: nil)
      selectMarquee(in: rect, base: base)
      if next.type == .leftMouseUp { break }
    }
  }
  func selectMarquee(in rect: CGRect, base: Set<IndexPath>) {
    let area = rect.intersection(visibleRect)
    let attributes =
      area.isNull || area.width <= 0 || area.height <= 0
      ? [] : collectionViewLayout?.layoutAttributesForElements(in: area) ?? []
    let hits = Set(
      attributes.filter { $0.representedElementCategory == .item && $0.frame.intersects(area) }
        .compactMap(\.indexPath))
    selectionIndexPaths = base.union(hits)
    selectionChanged?(selectionIndexPaths)
  }
  override func keyDown(with event: NSEvent) {
    if keyAction?(event) != true { super.keyDown(with: event) }
  }
  override func magnify(with event: NSEvent) { zoom?(Double(event.magnification)) }
}

@MainActor final class ContactSheetItem: NSCollectionViewItem {
  static let reuseID = NSUserInterfaceItemIdentifier("Photo.ContactSheetItem")
  private var host: NSHostingView<AnyView>?
  override func loadView() {
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    // Frame dimensions are owned by the collection layout, not inferred by
    // repeatedly probing SwiftUI's min/ideal/max content dimensions.
    host.sizingOptions = []
    host.autoresizingMask = [.width, .height]
    self.host = host
    view = host
  }
  func bind<Content: View>(_ content: Content) {
    _ = view
    host?.rootView = AnyView(
      content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
  }
  func unbind() { host?.rootView = AnyView(EmptyView()) }
  override func prepareForReuse() {
    super.prepareForReuse()
    unbind()
  }
}

@MainActor final class ContactSheetScrollView: NSScrollView {
  var viewportChanged: (() -> Void)?
  private var previousWidth: CGFloat = -1
  override func layout() {
    super.layout()
    let width = contentSize.width
    if width != previousWidth {
      previousWidth = width
      viewportChanged?()
    }
  }
}
