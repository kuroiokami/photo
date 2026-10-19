import Foundation

// Read-only boundaries for the folder workflow in Phase 2. No live adapters yet.
public protocol PhotoFileAccess: Sendable {
  func photos(in directory: URL) async throws -> [URL]
}

public protocol PhotoPreviewLoading: Sendable {
  func previewData(for file: URL, maximumPixelSize: Int) async throws -> Data
}

public struct PhotoMetadata: Equatable, Sendable {
  public let pixelWidth: Int
  public let pixelHeight: Int

  public init(pixelWidth: Int, pixelHeight: Int) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }
}

public protocol PhotoMetadataReading: Sendable {
  func metadata(for file: URL) async throws -> PhotoMetadata
}
