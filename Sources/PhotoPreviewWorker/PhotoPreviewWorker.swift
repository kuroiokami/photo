import Foundation
import PhotoImaging

@main
struct PhotoPreviewWorkerMain {
  static func main() {
    guard CommandLine.arguments.count == 2 else { exit(64) }
    do {
      try autoreleasepool {
        try CameraPreviewWorker.writePreview(
          URL(fileURLWithPath: CommandLine.arguments[1]), descriptor: 0)
      }
    } catch CameraPreviewError.tooLarge { exit(2) } catch CameraPreviewError.changed {
      exit(3)
    } catch { exit(1) }
  }
}
