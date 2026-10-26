import Foundation

/// Arithmetic row ranges avoid copying/chunking the inventory on view updates.
struct ContactSheetRows: RandomAccessCollection {
  let photoCount: Int
  let columns: Int
  init(photoCount: Int, columns: Int) {
    self.photoCount = Swift.max(0, photoCount)
    self.columns = Swift.max(1, columns)
  }
  var startIndex: Int { 0 }
  var endIndex: Int { photoCount / columns + (photoCount % columns == 0 ? 0 : 1) }
  subscript(position: Int) -> Range<Int> {
    precondition(position >= startIndex && position < endIndex)
    let start = position * columns
    return start..<Swift.min(start + columns, photoCount)
  }
  func row(containing index: Int) -> Int? {
    guard (0..<photoCount).contains(index) else { return nil }
    return index / columns
  }
}

/// ScrollViewReader must target a known lazy row, including offscreen photos.
struct ContactSheetRowTarget: Hashable {
  let index: Int
}
