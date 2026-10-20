import CoreGraphics
import Foundation

/// Photo-local, non-destructive composition relative to the EXIF-oriented original.
public struct PhotoCrop: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double
  public init(x: Double, y: Double, width: Double, height: Double) {
    let x = (x * 1e12).rounded() / 1e12
    let y = (y * 1e12).rounded() / 1e12
    let width = (width * 1e12).rounded() / 1e12
    let height = (height * 1e12).rounded() / 1e12
    self.x = x.isFinite ? min(0.99, max(0, x)) : 0
    self.y = y.isFinite ? min(0.99, max(0, y)) : 0
    self.width = width.isFinite ? min(1 - self.x, max(0.01, width)) : 1 - self.x
    self.height = height.isFinite ? min(1 - self.y, max(0.01, height)) : 1 - self.y
  }
  public var rect: CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }
  public init(_ rect: CGRect) {
    self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
  }
}

public enum PhotoEditAction: String, CaseIterable, Sendable {
  case clockwise = "Rotate Right"
  case counterclockwise = "Rotate Left"
  case horizontal = "Mirror Horizontally"
  case vertical = "Mirror Vertically"
  case clearCrop = "Clear Crop"
  case reset = "Reset Image Edits"
}

public struct PhotoEdit: Codable, Equatable, Sendable {
  public var quarterTurns: Int
  public var mirrored: Bool
  public var crop: PhotoCrop?
  public init(quarterTurns: Int = 0, mirrored: Bool = false, crop: PhotoCrop? = nil) {
    self.quarterTurns = ((quarterTurns % 4) + 4) % 4
    self.mirrored = mirrored
    self.crop = crop.map { PhotoCrop($0.rect) }
  }
  public var turns: Int { ((quarterTurns % 4) + 4) % 4 }
  public var isEdited: Bool { turns != 0 || mirrored || crop != nil }
  public var withoutCrop: Self { Self(quarterTurns: turns, mirrored: mirrored) }
  public func applying(_ action: PhotoEditAction) -> Self {
    var value = self
    switch action {
    case .clockwise, .counterclockwise:
      let steps = action == .clockwise ? 1 : 3
      value.quarterTurns = (turns + (mirrored ? 4 - steps : steps)) % 4
      for _ in 0..<steps {
        if let c = value.crop {
          value.crop = PhotoCrop(x: 1 - c.y - c.height, y: c.x, width: c.height, height: c.width)
        }
      }
    case .horizontal:
      value.mirrored.toggle()
      if let c = crop {
        value.crop = PhotoCrop(x: 1 - c.x - c.width, y: c.y, width: c.width, height: c.height)
      }
    case .vertical:
      value.quarterTurns = (turns + 2) % 4
      value.mirrored.toggle()
      if let c = crop {
        value.crop = PhotoCrop(x: c.x, y: 1 - c.y - c.height, width: c.width, height: c.height)
      }
    case .clearCrop: value.crop = nil
    case .reset: value = Self()
    }
    return value
  }
  public func orientedSize(_ original: CGSize) -> CGSize {
    turns % 2 == 0 ? original : CGSize(width: original.height, height: original.width)
  }
  public func cropBounds(_ original: CGSize) -> CGRect {
    let size = orientedSize(original)
    let bounds = CGRect(origin: .zero, size: size)
    guard let c = crop else { return bounds }
    let normalized = PhotoCrop(c.rect)
    func snap(_ value: Double) -> Double {
      abs(value - value.rounded()) < 0.000001 ? value.rounded() : value
    }
    let left = snap(normalized.x * size.width)
    let top = snap(normalized.y * size.height)
    let right = snap((normalized.x + normalized.width) * size.width)
    let bottom = snap((normalized.y + normalized.height) * size.height)
    return CGRect(x: left, y: top, width: right - left, height: bottom - top).integral.intersection(
      bounds)
  }
  /// Top-left coordinates. Rotations/mirrors preserve one source pixel per output pixel.
  public func transform(_ original: CGSize) -> CGAffineTransform {
    let rotation: CGAffineTransform
    switch turns {
    case 1: rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: original.height, ty: 0)
    case 2:
      rotation = CGAffineTransform(
        a: -1, b: 0, c: 0, d: -1, tx: original.width, ty: original.height)
    case 3: rotation = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: original.width)
    default: rotation = .identity
    }
    let size = orientedSize(original)
    let mirror =
      mirrored ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0) : .identity
    let crop = cropBounds(original)
    return rotation.concatenating(mirror).concatenating(
      CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
  }
  public func originalPoint(_ output: CGPoint, original: CGSize) -> CGPoint {
    let size = cropBounds(original).size
    let point = CGPoint(x: output.x * size.width, y: output.y * size.height).applying(
      transform(original).inverted())
    return CGPoint(x: point.x / max(1, original.width), y: point.y / max(1, original.height))
  }
}
