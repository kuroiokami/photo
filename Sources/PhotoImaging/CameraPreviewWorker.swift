import CCameraMemory
import CoreGraphics
import Darwin
import Foundation

/// A single request's shared RAM. The name is unlinked immediately; the child
/// inherits its descriptor as stdin. No image bytes are written to disk.
final class CameraSharedPixels: @unchecked Sendable {
  static let headerBytes = 1024 * 1024
  static let capacity = headerBytes + DetailPipeline.byteLimit
  let pointer: UnsafeMutableRawPointer
  let descriptor: Int32
  var publishedBytes = 0
  init() throws {
    let name = "/photo-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
    descriptor = photo_camera_memory_create(name, Self.capacity)
    guard descriptor >= 0 else { throw CameraPreviewError.unavailable }
    let address = mmap(nil, Self.capacity, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0)
    guard address != MAP_FAILED, let address else {
      close(descriptor)
      throw CameraPreviewError.unavailable
    }
    pointer = address
  }
  deinit {
    if publishedBytes > 0 { CameraBitmapAccounting.shared.change(-publishedBytes) }
    munmap(pointer, Self.capacity)
    close(descriptor)
  }
}

public enum CameraPreviewWorker {
  struct Header: Codable {
    let version: Int
    let width: Int
    let height: Int
    let stride: Int
    let bytes: Int
    let source: String
    let profile: Data?
    let peakResidentBytes: UInt64
  }
  public static func executable() -> URL? {
    guard let parent = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
    let url = parent.appendingPathComponent("PhotoPreviewWorker")
    return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
  }
  /// Entry point for the bundled, one-photo worker; never falls through to RAW rendering.
  public static func writePreview(_ url: URL, descriptor: Int32) throws {
    var status = stat()
    guard fstat(descriptor, &status) == 0, status.st_size == off_t(CameraSharedPixels.capacity)
    else {
      throw CameraPreviewError.unavailable
    }
    let address = mmap(
      nil, CameraSharedPixels.capacity, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0)
    guard address != MAP_FAILED, let address else { throw CameraPreviewError.unavailable }
    defer { munmap(address, CameraSharedPixels.capacity) }
    let preview = try CameraPreviewDecoder.decode(url)
    guard let provider = preview.image.dataProvider, let pixels = provider.data,
      CFDataGetLength(pixels) == preview.byteCost,
      preview.byteCost <= DetailPipeline.byteLimit
    else { throw CameraPreviewError.tooLarge }
    let profile = preview.image.colorSpace?.copyICCData() as Data?
    guard profile?.count ?? 0 <= 256 * 1024 else { throw CameraPreviewError.unavailable }
    address.advanced(by: CameraSharedPixels.headerBytes).copyMemory(
      from: CFDataGetBytePtr(pixels), byteCount: preview.byteCost)
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let header = try JSONEncoder().encode(
      Header(
        version: 1, width: preview.decodedWidth, height: preview.decodedHeight,
        stride: preview.image.bytesPerRow, bytes: preview.byteCost,
        source: preview.sourceKind.rawValue, profile: profile,
        peakResidentBytes: UInt64(max(0, usage.ru_maxrss))))
    guard header.count <= CameraSharedPixels.headerBytes - 4 else {
      throw CameraPreviewError.unavailable
    }
    header.withUnsafeBytes { data in
      address.advanced(by: 4).copyMemory(from: data.baseAddress!, byteCount: header.count)
    }
    var length = UInt32(header.count).bigEndian
    withUnsafeBytes(of: &length) { address.copyMemory(from: $0.baseAddress!, byteCount: 4) }
  }
  static func image(_ memory: CameraSharedPixels) throws -> PhotoPreview {
    let count = memory.pointer.load(as: UInt32.self).bigEndian
    guard count > 0, count <= CameraSharedPixels.headerBytes - 4 else {
      throw CameraPreviewError.unavailable
    }
    let data = Data(bytes: memory.pointer.advanced(by: 4), count: Int(count))
    let h = try JSONDecoder().decode(Header.self, from: data)
    guard h.version == 1, DetailPipeline.fits(width: h.width, height: h.height),
      h.stride >= h.width * 4, h.stride <= DetailPipeline.byteLimit / h.height,
      h.bytes == h.stride * h.height, h.bytes <= DetailPipeline.byteLimit,
      h.profile?.count ?? 0 <= 256 * 1024,
      let source = PreviewSource(rawValue: h.source), [.cameraJPEG, .embedded].contains(source)
    else { throw CameraPreviewError.unavailable }
    let space: CGColorSpace
    if let profile = h.profile {
      guard let decoded = CGColorSpace(iccData: profile as CFData), decoded.model == .rgb else {
        throw CameraPreviewError.unavailable
      }
      space = decoded
    } else {
      space = CGColorSpaceCreateDeviceRGB()
    }
    guard memory.publishedBytes == 0 else { throw CameraPreviewError.unavailable }
    memory.publishedBytes = h.bytes
    CameraBitmapAccounting.shared.change(h.bytes)
    let retained = Unmanaged.passRetained(memory)
    guard
      let provider = CGDataProvider(
        dataInfo: retained.toOpaque(),
        data: memory.pointer.advanced(by: CameraSharedPixels.headerBytes), size: h.bytes,
        releaseData: { info, _, _ in
          if let info { Unmanaged<CameraSharedPixels>.fromOpaque(info).release() }
        })
    else {
      retained.release()
      throw CameraPreviewError.unavailable
    }
    guard
      let image = CGImage(
        width: h.width, height: h.height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: h.stride, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw CameraPreviewError.unavailable }
    return PhotoPreview(
      image: image, sourceKind: source, originalWidth: h.width, originalHeight: h.height,
      workerPeakResidentBytes: h.peakResidentBytes)
  }
}

/// Serial per detail pane. Cancellation can terminate a decoder stuck in a synchronous SDK call.
final class CameraPreviewProcessLane: @unchecked Sendable {
  private let queue = DispatchQueue(label: "org.photo.camera-preview", qos: .userInitiated)
  func decode(_ url: URL, executable: URL) async throws -> PhotoPreview {
    let job = Job()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        queue.async {
          do { continuation.resume(returning: try job.run(url, executable: executable)) } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    } onCancel: {
      job.cancel()
    }
  }
  private final class Job: @unchecked Sendable {
    let lock = NSLock()
    var cancelled = false
    var timedOut = false
    var process: Process?
    func cancel() {
      lock.withLock {
        cancelled = true
        if process?.isRunning == true { process?.terminate() }
      }
    }
    func check() throws {
      try lock.withLock {
        if cancelled { throw CancellationError() }
        if timedOut { throw CameraPreviewError.unavailable }
      }
    }
    func run(_ url: URL, executable: URL) throws -> PhotoPreview {
      try check()
      guard let before = CameraPreviewDecoder.Stamp(url) else {
        throw CameraPreviewError.unavailable
      }
      let memory = try CameraSharedPixels()
      let child = Process()
      child.executableURL = executable
      child.arguments = [url.path]
      child.standardInput = FileHandle(fileDescriptor: memory.descriptor, closeOnDealloc: false)
      child.standardOutput = FileHandle.nullDevice
      child.standardError = FileHandle.nullDevice
      try lock.withLock {
        if cancelled { throw CancellationError() }
        process = child
        try child.run()
      }
      let timeout = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.lock.withLock {
          self.timedOut = true
          if self.process?.isRunning == true { self.process?.terminate() }
        }
      }
      DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
      defer {
        timeout.cancel()
        lock.withLock { process = nil }
      }
      child.waitUntilExit()
      try check()
      guard child.terminationReason == .exit else { throw CameraPreviewError.unavailable }
      if child.terminationStatus == 2 { throw CameraPreviewError.tooLarge }
      if child.terminationStatus == 3 { throw CameraPreviewError.changed }
      guard child.terminationStatus == 0 else { throw CameraPreviewError.unavailable }
      guard CameraPreviewDecoder.Stamp(url) == before else { throw CameraPreviewError.changed }
      return try CameraPreviewWorker.image(memory)
    }
  }
}
