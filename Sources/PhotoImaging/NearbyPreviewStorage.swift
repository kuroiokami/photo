import Foundation

/// Optional reads are conservative on cards, ejectable disks, network volumes
/// and unknown storage. This check runs on the preparation worker, never the UI.
enum NearbyPreviewStorage {
  struct Unavailable: Error {}
  static func allows(local: Bool?, removable: Bool?, ejectable: Bool?) -> Bool {
    local == true && removable == false && ejectable == false
  }
  static func allows(_ file: URL) -> Bool {
    guard
      let values = try? file.resourceValues(forKeys: [
        .volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
      ])
    else { return false }
    return allows(
      local: values.volumeIsLocal, removable: values.volumeIsRemovable,
      ejectable: values.volumeIsEjectable)
  }
}
