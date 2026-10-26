import AppKit
import SwiftUI
import Testing

@testable import PhotoCore
@testable import PhotoUI

@MainActor
struct NativeContactSheetTests {
  private func sheet(_ workspace: WorkspaceState, labels: [ThumbnailInfoField] = [])
    -> NativeContactSheet
  {
    NativeContactSheet(
      workspace: workspace, columns: 5, thumbnailEdge: 160,
      availableWidth: 1000, labels: labels, folderLabels: false,
      cacheGeneration: 0, hasCopiedCrop: false,
      content: { photo, _ in AnyView(Text(photo.filename)) },
      navigate: { workspace.moveSelection(by: $0, extending: $1) },
      preview: { _ in }, magnify: { _ in })
  }

  @Test func selectionAndReadinessDoNotReloadInventoryAndOffscreenFocusIsRevealed() throws {
    let photos = (0..<1000).map {
      PhotoItem(id: "photo-\($0)", filename: "Photo \($0)", resourceName: "")
    }
    let workspace = WorkspaceState(photos: photos)
    let value = sheet(workspace)
    let coordinator = value.makeCoordinator()
    let scroll = value.makeView(coordinator: coordinator)
    let collection = try #require(coordinator.collection)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = scroll
    scroll.layoutSubtreeIfNeeded()
    defer { window.close() }
    #expect(coordinator.reloadCount == 1)
    workspace.moveSelection(by: Int.max)
    coordinator.update(value)
    #expect(coordinator.reloadCount == 1)
    #expect(collection.selectionIndexPaths == [IndexPath(item: 999, section: 0)])
    let record = try #require(workspace.thumbnailState(for: photos[999].id))
    record.ready = true
    coordinator.update(value)
    #expect(coordinator.reloadCount == 1)
    #expect(scroll.contentView.bounds.minY > 0)
    scroll.scrollerStyle = .legacy
    scroll.setFrameSize(NSSize(width: 820, height: 500))
    scroll.layoutSubtreeIfNeeded()
    let layout = try #require(collection.collectionViewLayout as? NSCollectionViewFlowLayout)
    #expect(layout.itemSize.width * 5 + 48 + 32 <= scroll.contentSize.width)
    #expect(coordinator.reloadCount == 1)
    #expect(coordinator.bindCount < 100)
    // A drag after scrolling uses native item frames and cannot hit old rows.
    let visible = collection.visibleRect
    collection.selectMarquee(in: visible, base: [])
    let selected = collection.selectionIndexPaths
    #expect(!selected.isEmpty)
    #expect(selected.allSatisfy { $0.item > 900 })
    #expect(workspace.selectedIDs == Set(selected.map { photos[$0.item].id }))
    collection.selectMarquee(in: CGRect(x: 0, y: -500, width: 100, height: 100), base: [])
    #expect(workspace.selectedIDs.isEmpty)
  }

  @Test func equalCountLabelReplacementRebindsWithoutReloadingAndFilterReloadsOnce() throws {
    let workspace = WorkspaceState()
    let value = sheet(workspace, labels: [.iso])
    let coordinator = value.makeCoordinator()
    let scroll = value.makeView(coordinator: coordinator)
    let collection = try #require(coordinator.collection)
    collection.layoutSubtreeIfNeeded()
    let bound = coordinator.bindCount
    coordinator.update(sheet(workspace, labels: [.aperture]))
    #expect(coordinator.reloadCount == 1)
    #expect(coordinator.bindCount > bound)
    workspace.setFilter(.all, minimumRating: 5)
    coordinator.update(sheet(workspace, labels: [.aperture]))
    #expect(coordinator.photos.isEmpty)
    #expect(coordinator.reloadCount == 2)
    #expect(collection.selectionIndexPaths.isEmpty)
    workspace.setFilter(.all, minimumRating: 0)
    coordinator.update(value)
    #expect(coordinator.reloadCount == 3)
    let session = workspace.sessionID
    workspace.showSamples()
    #expect(workspace.sessionID != session)
    coordinator.update(value)
    #expect(coordinator.reloadCount == 4)
    _ = scroll
  }

  @Test func nativeGroupSelectionAndShiftNavigationUseModelDecisions() throws {
    let workspace = WorkspaceState()
    let value = sheet(workspace)
    let coordinator = value.makeCoordinator()
    let scroll = value.makeView(coordinator: coordinator)
    let collection = try #require(coordinator.collection)
    collection.selectionIndexPaths = [
      IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0),
    ]
    coordinator.collectionView(collection, didSelectItemsAt: [IndexPath(item: 1, section: 0)])
    #expect(workspace.selectedIDs == Set(workspace.photos.prefix(2).map(\.id)))
    let end = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: [.shift], timestamp: 0, windowNumber: 0, context: nil,
        characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 119))
    #expect(coordinator.key(end))
    #expect(workspace.selectedIDs == Set(workspace.photos.suffix(2).map(\.id)))
    #expect(coordinator.reloadCount == 1)
    _ = scroll
  }
}
