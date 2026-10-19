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

  public init(pixelWidth: Int, pixelHeight: Int) {
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }
}

public protocol PhotoMetadataReading: Sendable {
  func metadata(for file: URL) async throws -> PhotoMetadata
}
