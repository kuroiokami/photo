import Foundation
import PhotoCore

/// Actual ImageIO source types, never inferred solely from the filename.
enum SupportedImageTypes {
  static let raw: Set<String> = [
    "com.sony.arw-raw-image", "com.canon.cr2-raw-image", "com.canon.cr3-raw-image",
    "com.canon.crw-raw-image", "com.canon.tif-raw-image",
    "com.olympus.or-raw-image", "com.olympus.raw-image", "com.olympus.sr-raw-image",
  ]
  static func supports(_ type: String) -> Bool {
    raw.contains(type) || ["public.jpeg", "public.png"].contains(type)
  }
}
