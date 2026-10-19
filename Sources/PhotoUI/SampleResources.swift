import AppKit
import PhotoCore

public enum SampleResources {
  public static func url(for photo: PhotoItem) -> URL? {
    Bundle.module.url(forResource: photo.resourceName, withExtension: "png")
  }

  public static func image(for photo: PhotoItem) -> NSImage? {
    guard let url = Bundle.module.url(forResource: photo.resourceName, withExtension: "png") else {
      return nil
    }
    return NSImage(contentsOf: url)
  }
}
