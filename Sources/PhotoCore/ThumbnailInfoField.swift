import Foundation

public enum ThumbnailInfoField: String, CaseIterable, Identifiable, Sendable {
  case exposure, shutter, aperture, iso, focalLength, camera, lens, captureTime, dimensions
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .exposure: "Exposure summary"
    case .shutter: "Shutter speed"
    case .aperture: "Aperture"
    case .iso: "ISO"
    case .focalLength: "Focal length"
    case .camera: "Camera"
    case .lens: "Lens"
    case .captureTime: "Capture time"
    case .dimensions: "Dimensions"
    }
  }
  public func label(_ metadata: PhotoMetadata?) -> String {
    guard let metadata else { return title + " —" }
    switch self {
    case .exposure:
      return metadata.shootingSummary.isEmpty ? "Exposure —" : metadata.shootingSummary
    case .shutter:
      guard let value = metadata.exposureTime, value.isFinite, value > 0 else { return "Shutter —" }
      return value < 1
        ? "1/\((1/value).formatted(.number.precision(.fractionLength(0)))) s"
        : "\(value.formatted()) s"
    case .aperture: return metadata.aperture.map { "f/\($0.formatted())" } ?? "Aperture —"
    case .iso:
      return metadata.iso.map { "ISO \($0.formatted(.number.precision(.fractionLength(0))))" }
        ?? "ISO —"
    case .focalLength:
      return metadata.focalLength.map { "\($0.formatted()) mm" } ?? "Focal length —"
    case .camera: return metadata.camera ?? "Camera —"
    case .lens: return metadata.lens ?? "Lens —"
    case .captureTime: return metadata.captureTimeText ?? "Capture time —"
    case .dimensions: return "\(metadata.pixelWidth) × \(metadata.pixelHeight)"
    }
  }
  public static func restored(_ values: [String]) -> [Self] {
    var seen: Set<Self> = []
    return Array(
      values.compactMap(Self.init(rawValue:)).filter { seen.insert($0).inserted }.prefix(2))
  }
}
