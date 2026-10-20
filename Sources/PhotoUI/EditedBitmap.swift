import AppKit
import PhotoCore
import SwiftUI

/// Draws edits without allocating another full-resolution bitmap or changing cached pixels.
enum ImageEditDrawing {
  static func draw(
    _ image: CGImage, region: CGRect, original: CGSize, edit: PhotoEdit, in target: CGRect,
    interpolation: NSImageInterpolation = .high
  ) {
    let cropped = edit.cropBounds(original).size
    guard cropped.width > 0, cropped.height > 0, target.width > 0, target.height > 0,
      let context = NSGraphicsContext.current?.cgContext
    else { return }
    let scale = min(target.width / cropped.width, target.height / cropped.height)
    context.saveGState()
    defer { context.restoreGState() }
    context.interpolationQuality = interpolation == .none ? .none : .high
    let fitted = CGRect(
      x: target.midX - cropped.width * scale / 2, y: target.midY - cropped.height * scale / 2,
      width: cropped.width * scale, height: cropped.height * scale)
    context.clip(to: fitted)
    context.translateBy(
      x: target.midX - cropped.width * scale / 2, y: target.midY - cropped.height * scale / 2)
    context.scaleBy(x: scale, y: scale)
    context.concatenate(edit.transform(original))
    // CGImage has a bottom-left drawing convention; all Photo geometry is top-left.
    context.translateBy(x: region.minX, y: region.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: region.size))
  }

}

struct EditedBitmap: NSViewRepresentable {
  let image: CGImage
  var edit = PhotoEdit()
  func makeNSView(context: Context) -> EditedBitmapView { EditedBitmapView() }
  func updateNSView(_ view: EditedBitmapView, context: Context) {
    view.set(image, edit: edit)
  }
}
final class EditedBitmapView: NSView {
  private var source: CGImage?
  private var edit = PhotoEdit()
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func setFrameSize(_ newSize: NSSize) {
    let changed = frame.size != newSize
    super.setFrameSize(newSize)
    if changed { needsDisplay = true }
  }
  func set(_ image: CGImage, edit: PhotoEdit) {
    guard source !== image || self.edit != edit else { return }
    if source !== image {
      source = image
    }
    self.edit = edit
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let source else { return }
    NSGraphicsContext.saveGraphicsState()
    bounds.clip()
    ImageEditDrawing.draw(
      source, region: CGRect(x: 0, y: 0, width: source.width, height: source.height),
      original: CGSize(width: source.width, height: source.height), edit: edit, in: bounds)
    NSGraphicsContext.restoreGraphicsState()
  }
}

enum InspectionZoom {
  static func bounded(_ factor: Double) -> Double {
    factor.isFinite ? min(8, max(0.05, factor)) : 1
  }
  static func changed(_ factor: Double, delta: Double) -> Double {
    guard delta.isFinite else { return bounded(factor) }
    return bounded(factor * max(0.05, 1 + delta))
  }
}
