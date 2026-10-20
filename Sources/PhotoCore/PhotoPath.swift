import Darwin
import Foundation

/// Stable file-URL identity even when a destination does not exist yet. Resolve
/// the closest existing ancestor with realpath, then append missing components.
public enum PhotoPath {
  public static func canonical(_ url: URL) -> URL {
    guard url.isFileURL else { return url }
    var ancestor = url.standardizedFileURL
    var suffix: [String] = []
    while true {
      if let pointer = realpath(ancestor.path, nil) {
        defer { free(pointer) }
        let base = String(cString: pointer)
        let components = suffix.reversed().joined(separator: "/")
        let path = components.isEmpty ? base : base + (base == "/" ? "" : "/") + components
        // Do not standardize again: Foundation can reintroduce system aliases
        // and infer a trailing slash only after a folder comes into existence.
        return URL(fileURLWithPath: path, isDirectory: false)
      }
      guard ancestor.path != "/" else { return url.standardizedFileURL }
      suffix.append(ancestor.lastPathComponent)
      ancestor.deleteLastPathComponent()
    }
  }
}
