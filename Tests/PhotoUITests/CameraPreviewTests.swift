import CoreGraphics
import Foundation
import ImageIO
import PhotoCore
import Testing
import UniformTypeIdentifiers

@testable import PhotoImaging
@testable import PhotoUI

@Suite(.serialized)
struct CameraPreviewTests {
  private func integer(_ value: UInt64, bytes: Int, little: Bool = true) -> Data {
    Data(
      (0..<bytes).map { UInt8(truncatingIfNeeded: value >> (8 * (little ? $0 : bytes - $0 - 1))) })
  }
  private func jpeg(width: Int, height: Int, p3: Bool = false) throws -> Data {
    let space = try #require(CGColorSpace(name: p3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB))
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let dest = try #require(
      CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(dest))
    return data as Data
  }
  private func tiff(_ small: Data, _ large: Data, orientation: Int = 1, little: Bool = true) -> Data
  {
    // IFD0 -> SubIFD; the larger Sony-style JPEG is in the SubIFD.
    let sub: UInt64 = 8 + 2 + 5 * 12 + 4
    let payload = sub + 2 + 3 * 12 + 4
    func entry(_ tag: UInt64, _ type: UInt64, _ value: UInt64) -> Data {
      integer(tag, bytes: 2, little: little) + integer(type, bytes: 2, little: little)
        + integer(1, bytes: 4, little: little)
        + (type == 3
          ? integer(value, bytes: 2, little: little) + Data([0, 0])
          : integer(value, bytes: 4, little: little))
    }
    var data = Data(little ? [0x49, 0x49, 42, 0] : [0x4d, 0x4d, 0, 42])
    data += integer(8, bytes: 4, little: little)
    data += integer(5, bytes: 2, little: little)
    for (tag, type, v) in [
      (259, 3, 6), (274, 3, orientation), (330, 4, Int(sub)), (513, 4, Int(payload)),
      (514, 4, small.count),
    ] {
      data += entry(UInt64(tag), UInt64(type), UInt64(v))
    }
    data += integer(0, bytes: 4, little: little)
    data += integer(3, bytes: 2, little: little)
    data += entry(259, 3, 7)
    data += entry(513, 4, payload + UInt64(small.count))
    data += entry(514, 4, UInt64(large.count))
    data += integer(0, bytes: 4, little: little)
    data += small
    data += large
    return data
  }
  private func temporary(_ data: Data, ext: String = "ARW") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(ext)
    try data.write(to: url)
    return url
  }
  @Test func largestTIFFJPEGIsChosenAndEveryOrientationAndProfileArePreserved() async throws {
    let small = try jpeg(width: 32, height: 16)
    let large = try jpeg(width: 120, height: 60, p3: true)
    for little in [false, true] {
      for orientation in 1...8 {
        let data = tiff(small, large, orientation: orientation, little: little)
        let url = try temporary(data)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try CameraPreviewDecoder.decode(url)
        #expect(result.sourceKind == .cameraJPEG)
        #expect(result.decodedWidth == (orientation >= 5 ? 60 : 120))
        #expect(result.decodedHeight == (orientation >= 5 ? 120 : 60))
        #expect(result.image.colorSpace?.name == CGColorSpace.displayP3)
        #expect(result.byteCost <= DetailPipeline.byteLimit)
        #expect(try Data(contentsOf: url) == data)
      }
    }
  }
  @Test func sensorLosslessJPEGAndOversizedFramesAreRejectedBeforeDecode() throws {
    var header = Data([
      0xff, 0xd8, 0xff, 0xc3, 0, 17, 8, 0, 40, 0, 80, 3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0, 0xff,
      0xd9,
    ])
    let url = try temporary(tiff(header, header))
    defer { try? FileManager.default.removeItem(at: url) }
    var index = CameraJPEGIndex(reader: try BufferedContainerReader(url: url))
    try index.tiff()
    #expect(try index.frame(try #require(index.ranges.first)) == nil)
    header[3] = 0xc0
    header[7] = 255
    header[8] = 255
    header[9] = 255
    header[10] = 255
    let oversized = try temporary(tiff(header, header))
    defer { try? FileManager.default.removeItem(at: oversized) }
    #expect(throws: CameraPreviewError.self) { try CameraPreviewDecoder.decode(oversized) }
    let before = try Data(contentsOf: url)
    #expect(throws: CameraPreviewError.self) { try CameraPreviewDecoder.decode(url) }
    #expect(try Data(contentsOf: url) == before)
    // A cyclic graph cannot cause unbounded traversal.
    var cyclic = before
    cyclic.replaceSubrange(70..<74, with: integer(8, bytes: 4))
    try cyclic.write(to: url)
    index = CameraJPEGIndex(reader: try BufferedContainerReader(url: url))
    try index.tiff()
    #expect(index.ranges.count <= 2)
  }
  @Test func malformedContainersAndCancellationDoNotBreakTheDetailLane() async throws {
    let url = try temporary(Data([0x49, 0x49, 42, 0, 0xff, 0xff, 0xff, 0x7f]))
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: CameraPreviewError.self) { try CameraPreviewDecoder.decode(url) }
    let pipeline = DetailPipeline()
    let task = Task { try await pipeline.detail(for: url, source: .cameraPreview) }
    task.cancel()
    do {
      _ = try await task.value
      Issue.record("Cancelled request published an image")
    } catch is CancellationError {} catch { Issue.record("Expected cancellation, got \(error)") }
    let sample = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    #expect(try await pipeline.detail(for: sample).sourceKind == .image)
  }
  @Test @MainActor func sourceSwitchingKeepsCameraPixelsSeparateAndZAlwaysRequestsRAW() {
    let session = ComparisonSession()
    session.pin(SampleLibrary.photos[0])
    session.inspectCameraPreview()
    #expect(session.request(for: .active)?.action == .cameraPreview(CGPoint(x: 0.5, y: 0.5)))
    #expect(session.request(for: .reference)?.action == session.request(for: .active)?.action)
    session.zoom(true, center: CGPoint(x: 0.3, y: 0.6), scale: 2, from: .active)
    #expect(
      session.request(for: .reference)?.action == .cameraPreview(CGPoint(x: 0.3, y: 0.6), scale: 2))
    session.toggleInspection()
    #expect(session.request(for: .active)?.action == .zoom(CGPoint(x: 0.3, y: 0.6)))
    session.toggleInspection()
    #expect(session.request(for: .active)?.action == .fit)
    session.inspectCameraPreview()
    session.resetViewports()
    session.toggleInspection()
    #expect(session.request(for: .active)?.action == .zoom(CGPoint(x: 0.5, y: 0.5)))
  }
}

extension CameraPreviewTests {
  private func box(_ type: String, _ bytes: Data) -> Data {
    integer(UInt64(bytes.count + 8), bytes: 4, little: false) + Data(type.utf8) + bytes
  }
  private func cr3(_ jpeg: Data, sampleOffset: UInt64? = nil) -> Data {
    let be: (UInt64) -> Data = { integer($0, bytes: 4, little: false) }
    let tiff = Data([
      0x49, 0x49, 42, 0, 8, 0, 0, 0, 1, 0, 0x12, 1, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0,
    ])
    let uuid = Data([
      0x85, 0xc0, 0xb6, 0x87, 0x82, 0x0f, 0x11, 0xe0, 0x81, 0x11, 0xf4, 0xce, 0x46, 0x2b, 0x6a,
      0x48,
    ])
    let metadata = box("uuid", uuid + box("CMT1", tiff))
    let ftyp = box("ftyp", Data("crx ".utf8))
    func movie(_ offset: UInt64) -> Data {
      let entry = box(
        "CRAW", Data(repeating: 0, count: 82) + box("JPEG", Data(repeating: 0, count: 4)))
      let stsd = box("stsd", be(0) + be(1) + entry)
      let stsc = box("stsc", be(0) + be(1) + be(1) + be(1) + be(1))
      let stsz = box("stsz", be(0) + be(UInt64(jpeg.count)) + be(1))
      let co64 = box("co64", be(0) + be(1) + integer(offset, bytes: 8, little: false))
      return box(
        "moov",
        metadata + box("trak", box("mdia", box("minf", box("stbl", stsd + stsc + stsz + co64)))))
    }
    let offset = sampleOffset ?? UInt64(ftyp.count + movie(0).count + 8)
    return ftyp + movie(offset) + box("mdat", jpeg)
  }
  @Test func cr3SingleSampleTrackUsesVerifiedMediaBoundsAndContainerOrientation() async throws {
    let jpeg = try jpeg(width: 120, height: 60)
    let data = cr3(jpeg)
    let url = try temporary(data, ext: "cr3")
    defer { try? FileManager.default.removeItem(at: url) }
    let result = try CameraPreviewDecoder.decode(url)
    #expect(result.sourceKind == .cameraJPEG)
    #expect(result.decodedWidth == 60 && result.decodedHeight == 120)
    #expect(try Data(contentsOf: url) == data)
    let wrong = try temporary(cr3(jpeg, sampleOffset: 8), ext: "cr3")
    defer { try? FileManager.default.removeItem(at: wrong) }
    var index = CameraJPEGIndex(reader: try BufferedContainerReader(url: wrong))
    try index.cr3()
    #expect(index.ranges.isEmpty)
  }
  @Test func cameraOrientationMatchesImageIOPixels() throws {
    let original = try #require(SampleResources.url(for: SampleLibrary.photos[0]))
    let source = try #require(CGImageSourceCreateWithURL(original as CFURL, nil))
    func rgba(_ image: CGImage) throws -> Data {
      let ctx = try #require(
        CGContext(
          data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
          bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return Data(bytes: try #require(ctx.data), count: image.width * image.height * 4)
    }
    for orientation in 1...8 {
      let data = NSMutableData()
      let dest = try #require(
        CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
      CGImageDestinationAddImageFromSource(
        dest, source, 0, [kCGImagePropertyOrientation: orientation] as CFDictionary)
      #expect(CGImageDestinationFinalize(dest))
      let jpegSource = try #require(CGImageSourceCreateWithData(data, nil))
      let raw = try #require(CGImageSourceCreateImageAtIndex(jpegSource, 0, nil))
      let expected = try #require(
        CGImageSourceCreateThumbnailAtIndex(
          jpegSource, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
          ] as CFDictionary))
      let actual = try #require(CameraPreviewDecoder.oriented(raw, orientation: orientation))
      #expect(try rgba(actual) == rgba(expected))
    }
  }
}

extension CameraPreviewTests {
  @Test func exportedCameraPixelsReleaseWhenTheRequestOwnerReleasesItsImage() async throws {
    let baseline = DetailPipeline.retainedCameraPreviewBytes
    let small = try jpeg(width: 32, height: 16)
    let large = try jpeg(width: 120, height: 60)
    let url = try temporary(tiff(small, large))
    defer { try? FileManager.default.removeItem(at: url) }
    func request() async throws {
      let image = try CameraPreviewDecoder.decode(url)
      #expect(DetailPipeline.retainedCameraPreviewBytes >= baseline + image.byteCost)
    }
    for _ in 0..<4 { try await request() }
    #expect(DetailPipeline.retainedCameraPreviewBytes == baseline)
  }
}

extension CameraPreviewTests {
  private func bundledTestWorker() throws -> URL {
    if let path = ProcessInfo.processInfo.environment["PHOTO_PREVIEW_WORKER_TEST_EXECUTABLE"] {
      let url = URL(fileURLWithPath: path)
      guard FileManager.default.isExecutableFile(atPath: path) else {
        throw CameraPreviewError.unavailable
      }
      return url
    }
    var directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    for _ in 0..<6 {
      let candidate = directory.appendingPathComponent("PhotoPreviewWorker")
      if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
      directory.deleteLastPathComponent()
    }
    throw CameraPreviewError.unavailable
  }
  @Test func isolatedWorkerTransfersProfiledPixelsAndReleasesSharedMemory() async throws {
    let small = try jpeg(width: 32, height: 16)
    let large = try jpeg(width: 120, height: 60, p3: true)
    let url = try temporary(tiff(small, large, orientation: 6))
    defer { try? FileManager.default.removeItem(at: url) }
    let worker = DetailPipeline(cameraPreviewWorker: try bundledTestWorker())
    let baseline = DetailPipeline.retainedCameraPreviewBytes
    func request() async throws {
      let result = try await worker.detail(for: url, source: .cameraPreview)
      #expect(
        result.sourceKind == .cameraJPEG && result.decodedWidth == 60 && result.decodedHeight == 120
      )
      #expect(result.image.colorSpace?.name == CGColorSpace.displayP3)
      #expect(DetailPipeline.retainedCameraPreviewBytes == baseline + result.byteCost)
    }
    for _ in 0..<3 { try await request() }
    #expect(DetailPipeline.retainedCameraPreviewBytes == baseline)
    let cancelled = Task { try await worker.detail(for: url, source: .cameraPreview) }
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      Issue.record("Cancelled camera worker published pixels")
    } catch is CancellationError {} catch { Issue.record("Expected cancellation") }
    try await request()
    #expect(DetailPipeline.retainedCameraPreviewBytes == baseline)
  }
  @Test func corruptSharedHeaderCannotAllocateAnOversizedImage() throws {
    let memory = try CameraSharedPixels()
    var size = UInt32.max.bigEndian
    withUnsafeBytes(of: &size) { memory.pointer.copyMemory(from: $0.baseAddress!, byteCount: 4) }
    #expect(throws: CameraPreviewError.self) { try CameraPreviewWorker.image(memory) }
  }
}

extension CameraPreviewTests {
  @Test(.timeLimit(.minutes(1))) func cancellationTerminatesAnAlreadyRunningWorker() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let helper = root.appendingPathComponent("waiting-worker")
    let marker = root.appendingPathComponent("started")
    let quoted = "'" + marker.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    try ("#!/bin/sh\nprintf ready > " + quoted + "\nexec /bin/sleep 60\n").write(
      to: helper, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let url = root.appendingPathComponent("source.arw")
    try Data([1]).write(to: url)
    let lane = CameraPreviewProcessLane()
    let job = Task { try await lane.decode(url, executable: helper) }
    defer { job.cancel() }
    while !FileManager.default.fileExists(atPath: marker.path) {
      try await Task.sleep(for: .milliseconds(10))
    }
    job.cancel()
    do {
      _ = try await job.value
      Issue.record("Cancelled worker returned an image")
    } catch is CancellationError {} catch { Issue.record("Expected cancellation, got \(error)") }
  }
}
