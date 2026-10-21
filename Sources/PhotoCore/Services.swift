import Foundation

public protocol PhotoFileAccess: Sendable {
  func photos(in directory: URL) async throws -> [URL]
}

public protocol PhotoPreviewLoading: Sendable {
  associatedtype Preview: Sendable
  func preview(for file: URL, maximumPixelSize: Int, sessionID: UUID?) async throws -> Preview
}

public struct PhotoMetadata: Equatable, Sendable {
  public let pixelWidth: Int
  public let pixelHeight: Int
  public var captureTime: Date?
  public var captureTimeText: String?
  public var camera: String?
  public var lens: String?
  public var exposureTime: Double?
  public var aperture: Double?
  public var iso: Double?
  public var focalLength: Double?

  public init(pixelWidth: Int, pixelHeight: Int) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }

  public var shootingSummary: String {
    [
      exposureTime.map {
        $0 < 1
          ? "1/\((1 / $0).formatted(.number.precision(.fractionLength(0)))) s"
          : "\($0.formatted()) s"
      },
      aperture.map { "f/\($0.formatted())" },
      iso.map { "ISO \($0.formatted(.number.precision(.fractionLength(0))))" },
    ]
    .compactMap { $0 }.joined(separator: "  ·  ")
  }
}

public enum PhotoSort: String, CaseIterable, Sendable {
  case filename = "Filename"
  case captureTime = "Capture time"
  case iso = "ISO"
  case exposureTime = "Shutter speed"
  case aperture = "Aperture"
  case focalLength = "Focal length"
  case rating = "Rating"

  public func ordered(
    _ photos: [PhotoItem], metadata: [String: PhotoMetadata],
    ratings: [String: Int] = [:], filenameRanks: [String: Int] = [:]
  ) -> [PhotoItem] {
    photos.sorted { a, b in
      let av = value(metadata[a.id])
      let bv = value(metadata[b.id])
      if self == .rating, ratings[a.id, default: 0] != ratings[b.id, default: 0] {
        return ratings[a.id, default: 0] > ratings[b.id, default: 0]
      }
      if av != bv {
        guard let av else { return false }
        guard let bv else { return true }
        return av < bv
      }
      if let ar = filenameRanks[a.id], let br = filenameRanks[b.id] { return ar < br }
      let order = a.filename.localizedStandardCompare(b.filename)
      return order == .orderedSame ? a.id < b.id : order == .orderedAscending
    }
  }

  /// Preserve Foundation's locale/Unicode/digit ordering once per inventory, then compare integers.
  public static func filenameRanks(for photos: [PhotoItem]) -> [String: Int] {
    func before(_ a: PhotoItem, _ b: PhotoItem) -> Bool {
      let order = a.filename.localizedStandardCompare(b.filename)
      return order == .orderedSame ? a.id < b.id : order == .orderedAscending
    }
    let alreadyOrdered = zip(photos, photos.dropFirst()).allSatisfy { !before($0.1, $0.0) }
    let ordered = alreadyOrdered ? photos : photos.sorted(by: before)
    return Dictionary(
      ordered.enumerated().map { ($0.element.id, $0.offset) },
      uniquingKeysWith: { first, _ in first })
  }

  private func value(_ metadata: PhotoMetadata?) -> Double? {
    switch self {
    case .filename, .rating: nil
    case .captureTime: metadata?.captureTime?.timeIntervalSince1970
    case .iso: metadata?.iso
    case .exposureTime: metadata?.exposureTime
    case .aperture: metadata?.aperture
    case .focalLength: metadata?.focalLength
    }
  }
}

public protocol PhotoMetadataReading: Sendable {
  func metadata(for file: URL) async throws -> PhotoMetadata
}
