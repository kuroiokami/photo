import Foundation

public enum PhotoFormats {
  public static let rawExtensions: Set<String> = ["arw", "cr2", "cr3", "crw", "orf"]
  public static let imageExtensions: Set<String> = rawExtensions.union(["jpg", "jpeg", "png"])
  public static func isRaw(_ url: URL) -> Bool {
    rawExtensions.contains(url.pathExtension.lowercased())
  }
  public static func supports(_ url: URL) -> Bool {
    imageExtensions.contains(url.pathExtension.lowercased())
  }
  public static let rawExtensionSpellings: [String] = rawExtensions.sorted().flatMap { ext in
    ext.reduce([""]) { partial, character in
      partial.flatMap { prefix in
        let lower = String(character)
        let upper = lower.uppercased()
        return lower == upper ? [prefix + lower] : [prefix + lower, prefix + upper]
      }
    }
  }
}

/// Same-folder, same-stem families. Multiple RAWs or JPEGs are ambiguous and
/// stay independent rather than silently sharing decisions or a rename stem.
public struct PhotoFamily: Sendable {
  public let primary: URL
  public let images: [URL]
  public let sidecars: [URL]
  public var files: [URL] { images + sidecars }

  public static func groups(_ images: [URL], contents: [URL]) throws -> [PhotoFamily] {
    let companions = Dictionary(
      grouping: contents.filter { ["xmp", "acr"].contains($0.pathExtension.lowercased()) }
    ) { $0.lastPathComponent.lowercased().precomposedStringWithCanonicalMapping }
    let buckets = Dictionary(grouping: images) {
      $0.deletingLastPathComponent().path + "/"
        + $0.deletingPathExtension().lastPathComponent.lowercased()
        .precomposedStringWithCanonicalMapping
    }
    var result: [PhotoFamily] = []
    for bucket in buckets.values {
      let raws = bucket.filter(PhotoFormats.isRaw)
      let jpegs = bucket.filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
      // Only a unique RAW+JPEG pair is grouped. PNGs remain independent.
      let other = bucket.filter {
        !PhotoFormats.isRaw($0) && !["jpg", "jpeg"].contains($0.pathExtension.lowercased())
      }
      let grouped: [[URL]] =
        raws.count == 1 && jpegs.count == 1
        ? [raws + jpegs] + other.map { [$0] } : bucket.map { [$0] }
      for members in grouped {
        let primary = members.first!
        let expected = Set(
          members.flatMap { image -> [String] in
            let base =
              PhotoFormats.isRaw(image)
              ? image.deletingPathExtension().lastPathComponent : image.lastPathComponent
            return [base + ".xmp", base + ".acr"]
          }.map { $0.lowercased().precomposedStringWithCanonicalMapping })
        let sidecars = expected.flatMap { companions[$0] ?? [] }
        if raws.count > 1 && !sidecars.isEmpty { throw SidecarError.ambiguous }
        result.append(PhotoFamily(primary: primary, images: members, sidecars: sidecars))
      }
    }
    return result
  }
}
