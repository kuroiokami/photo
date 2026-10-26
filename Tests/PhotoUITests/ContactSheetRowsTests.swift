import Testing

@testable import PhotoUI

struct ContactSheetRowsTests {
  @Test func rowsCoverEveryPhotoOnceIncludingPartialLastRowsAndReflow() {
    for count in [0, 1, 4, 5, 6, 115, 10_000] {
      for columns in [1, 3, 5, 8] {
        let rows = ContactSheetRows(photoCount: count, columns: columns)
        #expect(rows.flatMap { $0 } == Array(0..<count))
        for index in 0..<count {
          let row = rows.row(containing: index)
          #expect(row != nil && rows[row!].contains(index))
        }
        #expect(rows.row(containing: -1) == nil)
        #expect(rows.row(containing: count) == nil)
      }
    }
  }
}
