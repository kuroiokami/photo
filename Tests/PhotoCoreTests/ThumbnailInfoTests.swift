import PhotoCore
import Testing

struct ThumbnailInfoTests {
  @Test func preferencesDropUnknownDuplicatesAndBoundExtraRows() {
    #expect(
      ThumbnailInfoField.restored(["iso", "unknown", "iso", "camera", "lens"]) == [.iso, .camera])
    #expect(ThumbnailInfoField.restored([]).isEmpty)
  }
  @Test func shootingLabelsKeepUnitsAndMakeMissingMetadataExplicit() {
    var metadata = PhotoMetadata(pixelWidth: 6000, pixelHeight: 4000)
    metadata.exposureTime = 1.0 / 250
    metadata.iso = 400
    metadata.focalLength = 40
    metadata.camera = "Camera body"
    #expect(ThumbnailInfoField.shutter.label(metadata) == "1/250 s")
    #expect(ThumbnailInfoField.iso.label(metadata) == "ISO 400")
    #expect(ThumbnailInfoField.focalLength.label(metadata) == "40 mm")
    #expect(ThumbnailInfoField.dimensions.label(metadata) == "6000 × 4000")
    #expect(ThumbnailInfoField.camera.label(metadata) == "Camera body")
    #expect(ThumbnailInfoField.lens.label(metadata) == "Lens —")
    #expect(ThumbnailInfoField.iso.label(nil) == "ISO —")
    metadata.exposureTime = .infinity
    #expect(ThumbnailInfoField.shutter.label(metadata) == "Shutter —")
  }
}
