import CoreGraphics
import Foundation
import PhotoCore
import PhotoImaging

enum CameraPreviewReference {
  struct Report: Encodable {
    let source: String
    let width: Int
    let height: Int
    let referenceWidth: Int
    let referenceHeight: Int
    let pixelMatch: Bool
    let originalsUnchanged: Bool
  }
  /// Developer comparison only: retains two images, unlike the app's single active detail.
  static func run(raw: URL, reference: URL) async throws -> Report {
    let before = try [raw, reference].map { try MediaOperations.checksum($0) }
    let worker = DetailPipeline()
    let actual = try await worker.detail(for: raw, source: .cameraPreview)
    let expected = try await worker.detail(for: reference)
    var equal =
      actual.decodedWidth == expected.decodedWidth && actual.decodedHeight == expected.decodedHeight
    if equal {
      for y in stride(from: 0, to: actual.decodedHeight, by: 16) {
        if try band(actual.image, y: y) != band(expected.image, y: y) {
          equal = false
          break
        }
      }
    }
    return Report(
      source: actual.sourceKind.rawValue, width: actual.decodedWidth, height: actual.decodedHeight,
      referenceWidth: expected.decodedWidth, referenceHeight: expected.decodedHeight,
      pixelMatch: equal,
      originalsUnchanged: try [raw, reference].map { try MediaOperations.checksum($0) } == before)
  }
  private static func band(_ image: CGImage, y: Int) throws -> Data {
    let height = min(16, image.height - y)
    guard let color = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: image.width, height: height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: color,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let bytes = context.data
    else { throw PreviewError.unreadable }
    context.draw(image, in: CGRect(x: 0, y: -y, width: image.width, height: image.height))
    return Data(bytes: bytes, count: image.width * height * 4)
  }
}
