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
  private let preparationWorker: Int?
  private var preparationID: UUID?
  private var foreground: Request?
  private var preparationProtection: [URL] = []
  private var nearbyQueue: [Ticket] = []
  private var nearbyHead = 0
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
    let speculative: Bool
    let continuation: CheckedContinuation<PhotoPreview, any Error>
  }
  private final class Load {
    let id = UUID()
    let generation: Int
    let trace: PhotoTrace.Interval
    var selected: Bool
    let speculative: Bool
    var waiters: [UUID: Waiter] = [:]
    var worker: Int?
    var task: Task<Void, Never>?
    init(generation: Int, selected: Bool, speculative: Bool, trace: PhotoTrace.Interval) {
      self.generation = generation
      self.selected = selected
      self.speculative = speculative
      self.trace = trace
    }
  }

  public init(
    byteLimit: Int, thumbnailDiskCache: ThumbnailDiskCache? = nil,
    maximumConcurrentLoads: Int = 1, preparesNearby: Bool = false
  ) {
    memory = PreviewMemoryCache(byteLimit: byteLimit)
    disk = thumbnailDiskCache
    let count = min(4, max(1, maximumConcurrentLoads))
    preparationWorker = preparesNearby ? count : nil
    workers = (0..<(count + (preparesNearby ? 1 : 0))).map { _ in PreviewDecodeWorker() }
    loader = nil
  }
  // Deterministic gates test races without sleeping inside a production worker.
  init(
    byteLimit: Int, maximumConcurrentLoads: Int, preparesNearby: Bool = false,
    loader: @escaping @Sendable (URL, Int) async throws -> PhotoPreview
  ) {
    memory = PreviewMemoryCache(byteLimit: byteLimit)
    disk = nil
    let count = min(4, max(1, maximumConcurrentLoads))
    preparationWorker = preparesNearby ? count : nil
    workers = (0..<(count + (preparesNearby ? 1 : 0))).map { _ in PreviewDecodeWorker() }
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
    try await requestPreview(
      for: file, maximumPixelSize: maximumPixelSize, sessionID: sessionID,
      priority: priority, speculative: false)
  }
  private func requestPreview(
    for file: URL, maximumPixelSize: Int, sessionID: UUID?,
    priority: PreviewLoadPriority, speculative: Bool
  ) async throws -> PhotoPreview {
    try Task.checkCancellation()
    guard prepareSession(sessionID) else { throw CancellationError() }
    let size = min(max(maximumPixelSize, 1), 2560)
    let request = Request(file: file, size: size, session: sessionID)
    if priority == .selected, preparationWorker != nil {
      foreground = request
      preparationProtection = [file]
      preparationID = nil
      cancelPreparation(except: request)
    }
    if let cached = memory.lookup(file, size: size, session: sessionID) { return cached }
    let trace = PhotoTrace.begin(
      speculative ? "NearbyFitLoad" : (size <= 480 ? "ThumbnailLoad" : "FitLoad"))
    defer { PhotoTrace.end(trace) }
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
          load = Load(
            generation: generation, selected: priority == .selected, speculative: speculative,
            trace: trace)
          jobs[request] = load
          queued += 1
          let ticket = Ticket(request: request, id: load.id)
          if load.selected {
            selectedQueue.append(ticket)
          } else if speculative {
            nearbyQueue.append(ticket)
          } else {
            visibleQueue.append(ticket)
          }
          PhotoTrace.event("PreviewQueued", in: trace)
        }
        load.waiters[id] = Waiter(
          signal: signal, speculative: speculative, continuation: continuation)
        if priority == .selected { promote(request) }
        drain()
      }
    } onCancel: {
      signal.cancel()
      Task { await self.cancel(request, waiter: id) }
    }
  }

  /// At most two Fit neighbors, after the displayed foreground is ready and
  /// settled. The caller owns cancellation; a separate slot protects foreground
  /// admission even when an opaque speculative decode cannot be interrupted.
  public func prepareNearby(after file: URL, candidates: [URL], sessionID: UUID?) async {
    guard preparationWorker != nil, !Task.isCancelled, session == sessionID,
      memory.lookup(file, size: 2560, session: sessionID) != nil
    else { return }
    let request = Request(file: file, size: 2560, session: sessionID)
    foreground = request
    preparationProtection = [file]
    let trace = PhotoTrace.begin("NearbyFitPreparation")
    defer { PhotoTrace.end(trace) }
    cancelPreparation(except: nil)
    let id = UUID()
    preparationID = id
    let epoch = generation
    defer { if preparationID == id { preparationID = nil } }
    do {
      try await Task.sleep(for: .milliseconds(150))
      var seen: Set<URL> = [file]
      for candidate in candidates.prefix(2) where seen.insert(candidate).inserted {
        try Task.checkCancellation()
        guard preparationID == id, generation == epoch, foreground == request,
          session == sessionID
        else { return }
        do {
          _ = try await requestPreview(
            for: candidate, maximumPixelSize: 2560, sessionID: sessionID,
            priority: .visible, speculative: true)
          if preparationID == id,
            memory.lookup(candidate, size: 2560, session: sessionID) != nil
          {
            preparationProtection.append(candidate)
          }
        } catch is CancellationError { return } catch {
          // A broken neighbor must not stop browsing.
        }
      }
    } catch {
      // A disappearing/changed Fit view cancels optional work.
    }
  }
  private func cancelPreparation(except request: Request?) {
    for (key, load) in jobs where key != request {
      for (id, waiter) in load.waiters where waiter.speculative {
        waiter.signal.cancel()
        cancel(key, waiter: id)
      }
    }
  }

  /// Promote an existing queued tile when it becomes selected without
  /// cancelling/restarting its shared decode or doing another source-file read.
  public func prioritizePreview(for file: URL, maximumPixelSize: Int, sessionID: UUID?) {
    guard session == sessionID else { return }
    promote(Request(file: file, size: min(max(maximumPixelSize, 1), 2560), session: sessionID))
  }
  private func promote(_ request: Request) {
    guard let load = jobs[request], !load.selected else { return }
    load.selected = true
    if load.worker == nil { selectedQueue.append(Ticket(request: request, id: load.id)) }
  }
  private func nextTicket(preparation: Bool) -> Ticket? {
    if preparation {
      // Never start optional I/O while any foreground demand remains.
      guard !jobs.values.contains(where: { !$0.speculative || $0.selected }) else { return nil }
      while nearbyHead < nearbyQueue.count {
        let value = nearbyQueue[nearbyHead]
        nearbyHead += 1
        if let load = jobs[value.request], load.id == value.id,
          load.worker == nil, load.speculative, !load.selected
        {
          return value
        }
      }
      return nil
    }
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
        load.worker == nil, !load.selected, !load.speculative
      {
        return value
      }
    }
    return nil
  }
  private func compactQueues() {
    if nearbyQueue.count > 128 || nearbyHead == nearbyQueue.count {
      nearbyQueue = nearbyQueue.dropFirst(nearbyHead).filter { value in
        guard let load = jobs[value.request] else { return false }
        return load.id == value.id && load.worker == nil && load.speculative && !load.selected
      }
      nearbyHead = 0
    }
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
        return load.id == value.id && load.worker == nil && !load.selected && !load.speculative
      }
      visibleHead = 0
    }
  }
  private func drain() {
    for index in workers.indices where active[index] == nil {
      while let ticket = nextTicket(preparation: index == preparationWorker),
        let load = jobs[ticket.request]
      {
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
        let speculative = load.speculative
        PhotoTrace.event("PreviewWorkStarted", in: trace)
        load.task = Task(
          priority: load.selected ? .userInitiated : (speculative ? .background : .utility)
        ) {
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
              request.file, size: request.size, disk: disk, trace: trace, selected: selected,
              speculative: speculative)
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
        memory.insert(
          image, file: ticket.request.file, size: ticket.request.size,
          protecting: load.speculative ? preparationProtection : [])
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
    preparationID = nil
    foreground = nil
    preparationProtection = []
    nearbyQueue.removeAll(keepingCapacity: true)
    nearbyHead = 0
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
    selected: Bool, speculative: Bool
  ) async -> PreviewLoadOutcome {
    let signal = CancellationSignal()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        queue.async(qos: selected ? .userInitiated : (speculative ? .background : .utility)) {
          continuation.resume(
            returning: self.decode(
              file, size: size, disk: disk, trace: trace, signal: signal, speculative: speculative))
        }
      }
    } onCancel: {
      signal.cancel()
    }
  }
  private func decode(
    _ file: URL, size: Int, disk: ThumbnailDiskCache?, trace: PhotoTrace.Interval,
    signal: CancellationSignal, speculative: Bool
  ) -> PreviewLoadOutcome {
    var attempts = 0
    do {
      try signal.check()
      if speculative, !NearbyPreviewStorage.allows(file) {
        throw NearbyPreviewStorage.Unavailable()
      }
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
