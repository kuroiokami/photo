import CoreGraphics
import Dispatch
import Foundation
import ImageIO
import PhotoCore

/// CGImage is immutable. Sharing the decoded image never shares mutable drawing state.
public struct PhotoPreview: @unchecked Sendable {
  public let image: CGImage
  public var sourceKind: PreviewSource = .image
  public var decodedWidth: Int { image.width }
  public var decodedHeight: Int { image.height }
  public let originalWidth: Int
  public let originalHeight: Int
  public var byteCost: Int { image.bytesPerRow * image.height }
}

public enum PreviewSource: String, Sendable {
  case image = "Image"
  case embedded = "Embedded preview"
  case raw = "Rendered RAW"
}

public enum PreviewError: LocalizedError {
  case unreadable
  case embeddedUnavailable
  case detailTooLarge
  public var errorDescription: String? {
    switch self {
    case .unreadable:
      "This image could not be read. It may be damaged, unsupported, or no longer available."
    case .embeddedUnavailable:
      "No readable embedded preview. RAW rendering is available through 100% inspection on supported cameras."
    case .detailTooLarge:
      "Full detail exceeds the 256 MiB decoded-image limit. Fit preview remains available."
    }
  }
}

/// Synchronous ImageIO work runs inside a bounded decode worker. A local
/// autorelease pool releases temporary decoder objects after every image.
private enum ImageDecoder {
  static func decode(
    _ url: URL, maximumPixelSize: Int,
    checkCancellation: @Sendable () throws -> Void
  ) throws -> PhotoPreview {
    try autoreleasepool {
      try checkCancellation()
      if let canon = try CanonEmbeddedPreview.decode(
        url, maximumPixelSize: maximumPixelSize, checkCancellation: checkCancellation)
      {
        return canon
      }
      let options = [kCGImageSourceShouldCache: false] as CFDictionary
      guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
        let type = CGImageSourceGetType(source) as String?,
        SupportedImageTypes.supports(type),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
      else { throw PreviewError.unreadable }
      let raw = SupportedImageTypes.raw.contains(type)
      let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
      let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: !raw,
        kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        kCGImageSourceShouldCacheImmediately: true,
      ]
      guard
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
      else { throw raw ? PreviewError.embeddedUnavailable : PreviewError.unreadable }
      try checkCancellation()
      return PhotoPreview(
        image: image, sourceKind: raw ? .embedded : .image,
        originalWidth: orientation >= 5 ? height : width,
        originalHeight: orientation >= 5 ? width : height)
    }
  }
}

public enum PreviewLoadPriority: Sendable {
  case visible, selected
}

public struct PreviewSchedulingStatistics: Sendable {
  public let activeLoads: Int
  public let queuedLoads: Int
  public let maximumActiveLoads: Int
  public let cancelledLoads: Int
  public let coalescedRequests: Int
}

/// Owns admission, single-flight requests and the bounded RAM cache. Blocking
/// file/ImageIO work belongs to separate workers, never this scheduling actor.
public actor ImagePipeline: PhotoPreviewLoading {
  private nonisolated let memory: PreviewMemoryCache
  private let disk: ThumbnailDiskCache?
  private let workers: [PreviewDecodeWorker]
  private let loader: (@Sendable (URL, Int) async throws -> PhotoPreview)?
  private var session: UUID?
  private var retiredSessions: Set<UUID> = []
  private var generation = 0
  private var jobs: [Request: Load] = [:]
  private var active: [Int: UUID] = [:]
  private var selectedQueue: [Ticket] = []
  private var visibleQueue: [Ticket] = []
  private var selectedHead = 0
  private var visibleHead = 0
  private var queued = 0
  private var peakActive = 0
  private var cancelled = 0
  private var coalesced = 0
  private(set) var decodedImageCount = 0
  private(set) var diskHitCount = 0
  public var cachedByteCount: Int { memory.byteCount }

  private struct Request: Hashable, Sendable {
    let file: URL
    let size: Int
    let session: UUID?
  }
  private struct Ticket {
    let request: Request
    let id: UUID
  }
  private struct Waiter {
    let signal: CancellationSignal
    let continuation: CheckedContinuation<PhotoPreview, any Error>
  }
  private final class Load {
    let id = UUID()
    let generation: Int
    let trace: PhotoTrace.Interval
    var selected: Bool
    var waiters: [UUID: Waiter] = [:]
    var worker: Int?
    var task: Task<Void, Never>?
    init(generation: Int, selected: Bool, trace: PhotoTrace.Interval) {
      self.generation = generation
      self.selected = selected
      self.trace = trace
    }
  }

  public init(
    byteLimit: Int, thumbnailDiskCache: ThumbnailDiskCache? = nil,
    maximumConcurrentLoads: Int = 1
  ) {
    memory = PreviewMemoryCache(byteLimit: byteLimit)
    disk = thumbnailDiskCache
    workers = (0..<min(4, max(1, maximumConcurrentLoads))).map { _ in PreviewDecodeWorker() }
    loader = nil
  }
  // Deterministic gates test races without sleeping inside a production worker.
  init(
    byteLimit: Int, maximumConcurrentLoads: Int,
    loader: @escaping @Sendable (URL, Int) async throws -> PhotoPreview
  ) {
    memory = PreviewMemoryCache(byteLimit: byteLimit)
    disk = nil
    workers = (0..<min(4, max(1, maximumConcurrentLoads))).map { _ in PreviewDecodeWorker() }
    self.loader = loader
  }

  /// RAM only: safe for a view to use without waiting behind an image decode.
  public nonisolated func immediateCachedPreview(
    for file: URL, maximumPixelSize: Int, sessionID: UUID? = nil
  ) -> PhotoPreview? {
    guard !Task.isCancelled else { return nil }
    return memory.lookup(file, size: maximumPixelSize, session: sessionID)
  }
  public func preview(for file: URL, maximumPixelSize: Int, sessionID: UUID? = nil)
    async throws -> PhotoPreview
  {
    try await preview(
      for: file, maximumPixelSize: maximumPixelSize,
      sessionID: sessionID, priority: .visible)
  }
  public func preview(
    for file: URL, maximumPixelSize: Int, sessionID: UUID? = nil,
    priority: PreviewLoadPriority
  ) async throws -> PhotoPreview {
    try Task.checkCancellation()
    guard prepareSession(sessionID) else { throw CancellationError() }
    let size = min(max(maximumPixelSize, 1), 2560)
    if let cached = memory.lookup(file, size: size, session: sessionID) { return cached }
    let trace = PhotoTrace.begin(size <= 480 ? "ThumbnailLoad" : "FitLoad")
    defer { PhotoTrace.end(trace) }
    let request = Request(file: file, size: size, session: sessionID)
    let id = UUID()
    let signal = CancellationSignal()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !signal.isCancelled, !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }
        let load: Load
        if let existing = jobs[request] {
          load = existing
          coalesced += 1
        } else {
          load = Load(generation: generation, selected: priority == .selected, trace: trace)
          jobs[request] = load
          queued += 1
          let ticket = Ticket(request: request, id: load.id)
          if load.selected { selectedQueue.append(ticket) } else { visibleQueue.append(ticket) }
          PhotoTrace.event("PreviewQueued", in: trace)
        }
        load.waiters[id] = Waiter(signal: signal, continuation: continuation)
        if priority == .selected { promote(request) }
        drain()
      }
    } onCancel: {
      signal.cancel()
      Task { await self.cancel(request, waiter: id) }
    }
  }

  /// Promote an existing queued tile when it becomes selected without
  /// cancelling/restarting its shared decode or doing another source-file read.
  public func prioritizePreview(for file: URL, maximumPixelSize: Int, sessionID: UUID?) {
    guard session == sessionID else { return }
    promote(Request(file: file, size: min(max(maximumPixelSize, 1), 2560), session: sessionID))
  }
  private func promote(_ request: Request) {
    guard let load = jobs[request], !load.selected, load.worker == nil else { return }
    load.selected = true
    selectedQueue.append(Ticket(request: request, id: load.id))
  }
  private func nextTicket() -> Ticket? {
    while selectedHead < selectedQueue.count {
      let value = selectedQueue[selectedHead]
      selectedHead += 1
      if let load = jobs[value.request], load.id == value.id,
        load.worker == nil, load.selected
      {
        return value
      }
    }
    while visibleHead < visibleQueue.count {
      let value = visibleQueue[visibleHead]
      visibleHead += 1
      if let load = jobs[value.request], load.id == value.id,
        load.worker == nil, !load.selected
      {
        return value
      }
    }
    return nil
  }
  private func compactQueues() {
    if selectedQueue.count > 128 || selectedHead == selectedQueue.count {
      selectedQueue = selectedQueue.dropFirst(selectedHead).filter { value in
        guard let load = jobs[value.request] else { return false }
        return load.id == value.id && load.worker == nil && load.selected
      }
      selectedHead = 0
    }
    if visibleQueue.count > 128 || visibleHead == visibleQueue.count {
      visibleQueue = visibleQueue.dropFirst(visibleHead).filter { value in
        guard let load = jobs[value.request] else { return false }
        return load.id == value.id && load.worker == nil && !load.selected
      }
      visibleHead = 0
    }
  }
  private func drain() {
    for index in workers.indices where active[index] == nil {
      while let ticket = nextTicket(), let load = jobs[ticket.request] {
        pruneCancelled(load)
        guard !load.waiters.isEmpty else {
          jobs.removeValue(forKey: ticket.request)
          queued -= 1
          cancelled += 1
          continue
        }
        load.worker = index
        queued -= 1
        active[index] = load.id
        peakActive = max(peakActive, active.count)
        let worker = workers[index]
        let request = ticket.request
        let disk = disk
        let loader = loader
        let trace = load.trace
        let selected = load.selected
        PhotoTrace.event("PreviewWorkStarted", in: trace)
        load.task = Task(priority: load.selected ? .userInitiated : .utility) {
          let outcome: PreviewLoadOutcome
          if let loader {
            do {
              try Task.checkCancellation()
              let image = try await loader(request.file, request.size)
              outcome = PreviewLoadOutcome(result: .success(image), sourceDecodes: 1)
            } catch {
              outcome = PreviewLoadOutcome(result: .failure(error), sourceDecodes: 1)
            }
          } else {
            outcome = await worker.load(
              request.file, size: request.size, disk: disk, trace: trace, selected: selected)
          }
          self.finish(ticket, worker: index, outcome: outcome)
        }
        break
      }
    }
    compactQueues()
  }
  private func pruneCancelled(_ load: Load) {
    for (id, waiter) in load.waiters where waiter.signal.isCancelled {
      load.waiters.removeValue(forKey: id)
      waiter.continuation.resume(throwing: CancellationError())
    }
  }
  private func cancel(_ request: Request, waiter id: UUID) {
    guard let load = jobs[request], let waiter = load.waiters.removeValue(forKey: id) else {
      return
    }
    waiter.continuation.resume(throwing: CancellationError())
    if load.waiters.isEmpty {
      jobs.removeValue(forKey: request)
      if load.worker == nil { queued -= 1 }
      load.task?.cancel()
      cancelled += 1
      PhotoTrace.event("PreviewWorkCancelled", in: load.trace)
    }
    compactQueues()
  }
  private func finish(_ ticket: Ticket, worker: Int, outcome: PreviewLoadOutcome) {
    guard active[worker] == ticket.id else { return }
    active.removeValue(forKey: worker)
    decodedImageCount += outcome.sourceDecodes
    diskHitCount += outcome.diskHits
    if let load = jobs[ticket.request], load.id == ticket.id {
      jobs.removeValue(forKey: ticket.request)
      pruneCancelled(load)
      let current = load.generation == generation && ticket.request.session == session
      if current, !load.waiters.isEmpty, case .success(let image) = outcome.result {
        memory.insert(image, file: ticket.request.file, size: ticket.request.size)
        if let stamp = outcome.stamp {
          disk?.enqueue(image, file: ticket.request.file, size: ticket.request.size, stamp: stamp)
        }
      }
      for waiter in load.waiters.values {
        if current && !waiter.signal.isCancelled {
          waiter.continuation.resume(with: outcome.result)
        } else {
          waiter.continuation.resume(throwing: CancellationError())
        }
      }
    }
    drain()
  }
  private func invalidate() {
    generation += 1
    for load in jobs.values {
      load.task?.cancel()
      for waiter in load.waiters.values {
        waiter.continuation.resume(throwing: CancellationError())
      }
      cancelled += 1
    }
    jobs.removeAll(keepingCapacity: true)
    selectedQueue.removeAll(keepingCapacity: true)
    visibleQueue.removeAll(keepingCapacity: true)
    selectedHead = 0
    visibleHead = 0
    queued = 0
    // Active slots stay occupied until opaque ImageIO work actually returns.
  }
  @discardableResult
  private func prepareSession(_ value: UUID?) -> Bool {
    // A late request/reset from an old view must never restore a retired
    // folder session and invalidate the new folder's in-flight requests.
    if let value, retiredSessions.contains(value) { return false }
    guard session != value else { return true }
    if let session { retiredSessions.insert(session) }
    invalidate()
    session = value
    memory.startSession(value)
    return true
  }
  public func cachedPreview(for file: URL, maximumPixelSize: Int, sessionID: UUID? = nil)
    -> PhotoPreview?
  {
    immediateCachedPreview(for: file, maximumPixelSize: maximumPixelSize, sessionID: sessionID)
  }
  public func startSession(_ sessionID: UUID?) {
    guard !Task.isCancelled else { return }
    prepareSession(sessionID)
  }
  public func cacheStatistics() -> (sourceDecodes: Int, diskHits: Int, memoryBytes: Int) {
    (decodedImageCount, diskHitCount, memory.byteCount)
  }
  public func schedulingStatistics() -> PreviewSchedulingStatistics {
    PreviewSchedulingStatistics(
      activeLoads: active.count, queuedLoads: queued,
      maximumActiveLoads: peakActive, cancelledLoads: cancelled, coalescedRequests: coalesced)
  }
  public func clearThumbnailCache() {
    invalidate()
    memory.clear()
    disk?.clear()
  }
}

private final class CancellationSignal: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  var isCancelled: Bool { lock.withLock { cancelled } }
  func cancel() { lock.withLock { cancelled = true } }
  func check() throws { if isCancelled { throw CancellationError() } }
}
private struct PreviewLoadOutcome: Sendable {
  let result: Result<PhotoPreview, any Error>
  var sourceDecodes = 0
  var diskHits = 0
  var stamp: ThumbnailDiskCache.SourceStamp?
}
/// Dedicated serial queues keep opaque ImageIO/file calls out of Swift's
/// cooperative executor. The coordinator admits one job per worker at a time.
private final class PreviewDecodeWorker: @unchecked Sendable {
  private let queue = DispatchQueue(
    label: "Photo.PreviewDecode", qos: .utility, autoreleaseFrequency: .workItem)
  func load(
    _ file: URL, size: Int, disk: ThumbnailDiskCache?, trace: PhotoTrace.Interval,
    selected: Bool
  ) async -> PreviewLoadOutcome {
    let signal = CancellationSignal()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        queue.async(qos: selected ? .userInitiated : .utility) {
          continuation.resume(
            returning: self.decode(file, size: size, disk: disk, trace: trace, signal: signal))
        }
      }
    } onCancel: {
      signal.cancel()
    }
  }
  private func decode(
    _ file: URL, size: Int, disk: ThumbnailDiskCache?, trace: PhotoTrace.Interval,
    signal: CancellationSignal
  ) -> PreviewLoadOutcome {
    var attempts = 0
    do {
      try signal.check()
      let stamp = disk?.stamp(for: file, size: size)
      if let stamp, let image = disk?.read(stamp.key),
        disk?.matches(stamp, file: file, size: size) == true
      {
        try signal.check()
        PhotoTrace.event("DiskThumbnailHit", in: trace)
        return PreviewLoadOutcome(result: .success(image), diskHits: 1)
      }
      attempts = 1
      let decode = PhotoTrace.begin("SourceDecode", parent: trace)
      let image: PhotoPreview
      do {
        defer { PhotoTrace.end(decode) }
        image = try ImageDecoder.decode(
          file, maximumPixelSize: size, checkCancellation: signal.check)
      }
      try signal.check()
      let validStamp = stamp.flatMap {
        disk?.matches($0, file: file, size: size) == true ? $0 : nil
      }
      return PreviewLoadOutcome(result: .success(image), sourceDecodes: 1, stamp: validStamp)
    } catch {
      return PreviewLoadOutcome(result: .failure(error), sourceDecodes: attempts)
    }
  }
}
