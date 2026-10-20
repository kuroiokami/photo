import Foundation
import ImageIO
import PhotoCore

/// Explicit export only. Writes derived JPEG/PNG copies in a handoff folder;
/// the source library is never passed to this writer by the workflow.
public actor HandoffMetadataWriter {
  private let sourceProtection: SourceProtection
  public init(sourceProtection: SourceProtection = .shared) {
    self.sourceProtection = sourceProtection
  }
  public func embed(in copy: URL, sidecar: URL) throws -> String {
    return try sourceProtection.withWritable([copy]) {
      try Task.checkCancellation()
      let bytes = try Data(contentsOf: sidecar)
      _ = try XMPSidecar.descriptive(bytes)
      let oldHash = try MediaOperations.checksum(copy)
      let temporary = copy.deletingLastPathComponent().appendingPathComponent(
        ".photo-export-\(UUID())")
      defer { try? FileManager.default.removeItem(at: temporary) }
      try autoreleasepool {
        guard
          let source = CGImageSourceCreateWithURL(
            copy as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
          let type = CGImageSourceGetType(source),
          ["public.jpeg", "public.png"].contains(type as String)
        else { throw MediaOperationError.invalid("Cannot read the JPEG/PNG handoff copy.") }
        guard let metadata = CGImageMetadataCreateFromXMPData(bytes as CFData) else {
          throw MediaOperationError.invalid("ImageIO could not parse the prepared XMP metadata.")
        }
        guard let output = CGImageDestinationCreateWithURL(temporary as CFURL, type, 1, nil) else {
          throw MediaOperationError.invalid("Cannot create the temporary metadata export.")
        }
        var error: Unmanaged<CFError>?
        let options: [CFString: Any] = [
          kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: true,
        ]
        guard CGImageDestinationCopyImageSource(output, source, options as CFDictionary, &error)
        else {
          if let error { throw error.takeRetainedValue() as any Error }
          throw MediaOperationError.invalid("ImageIO could not copy the image with its metadata.")
        }
      }
      // Release the destination before reopening it. Older ImageIO versions can
      // retain buffered output until the destination closes; CopyImageSource must
      // not be followed by CGImageDestinationFinalize.
      try autoreleasepool {
        guard let check = CGImageSourceCreateWithURL(temporary as CFURL, nil) else {
          throw MediaOperationError.invalid("Cannot reopen the metadata export for verification.")
        }
        guard let outputMetadata = CGImageSourceCopyMetadataAtIndex(check, 0, nil),
          let xmp = CGImageMetadataCreateXMPData(outputMetadata, nil)
        else {
          throw MediaOperationError.invalid("ImageIO did not expose XMP in the metadata export.")
        }
        let wanted = try XMPSidecar.descriptive(bytes)
        let actual = try XMPSidecar.descriptive(xmp as Data)
        guard wanted.fields.allSatisfy({ (actual.fields[$0.key] ?? "") == $0.value }),
          !wanted.keywordsPresent || actual.keywords == wanted.keywords,
          !wanted.hierarchyPresent || actual.hierarchy == wanted.hierarchy,
          try XMPSidecar.read(xmp as Data) == XMPSidecar.read(bytes)
        else {
          throw MediaOperationError.invalid(
            "The handoff copy did not retain all requested metadata. Its verified original-byte copy was left in place."
          )
        }
      }
      try Task.checkCancellation()
      guard try MediaOperations.checksum(copy) == oldHash else {
        throw DecisionStoreError.fileChanged
      }
      _ = try FileManager.default.replaceItemAt(copy, withItemAt: temporary)
      return try MediaOperations.checksum(copy)

    }
  }
}
