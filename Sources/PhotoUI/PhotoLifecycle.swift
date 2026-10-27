import AppKit
import Darwin
import Foundation
import MachO
import PhotoCore
import os

/// Local, fixed-field diagnostics only: no photo names, paths, metadata or pixels.
/// Explicit Quit and save/file-operation barriers keep their existing behavior.
@MainActor
public final class PhotoLifecycle {
  public enum Event: String, Codable, Sendable {
    case launch, ready, active, background, heartbeat, sleep, wake
    case quitRequested, waitingForSaves, willTerminate, memoryWarning, memoryCritical, memoryNormal
  }
  struct Record: Codable, Sendable {
    let event: Event
    let processID: Int32
    let buildUUID: String?
    let uptimeSeconds: Double
    let residentBytes: UInt64?
    let physicalFootprintBytes: UInt64?
    let active: Bool
    let windowCount: Int
    let automaticTerminationSupported: Bool
    let pendingDecisions: Bool
    let pendingFileWork: Bool
  }
  public static let shared = PhotoLifecycle()
  private static let logger = Logger(subsystem: "org.photo.lifecycle", category: "stability")
  private let sample: @MainActor (Event) -> Record
  private let emit: @MainActor (Record) -> Void
  private let interval: Duration
  private var pulse: Task<Void, Never>?
  private var pressure: (any DispatchSourceMemoryPressure)?
  private var observers: [NSObjectProtocol] = []
  private var started = false

  private convenience init() {
    let began = ProcessInfo.processInfo.systemUptime
    let build = Self.loadedExecutableUUID()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.init(
      interval: .seconds(60),
      sample: { event in
        Self.capture(event, began: began, build: build)
      },
      emit: { record in
        guard let data = try? encoder.encode(record) else { return }
        Self.logger.notice(
          "PhotoLifecycle \(String(decoding: data, as: UTF8.self), privacy: .public)")
      })
  }
  // Injectable sampling/sink make lifecycle and timer behavior testable without
  // reading a user's windows, changing system termination policy or uploading logs.
  init(
    interval: Duration, sample: @escaping @MainActor (Event) -> Record,
    emit: @escaping @MainActor (Record) -> Void
  ) {
    self.interval = interval
    self.sample = sample
    self.emit = emit
  }
  public func record(_ event: Event) { emit(sample(event)) }

  public func start() { start(observeSystem: true) }
  func start(observeSystem: Bool) {
    guard !started else { return }
    started = true
    record(.ready)
    pulse = Task(priority: .background) { [weak self, interval] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: interval) } catch { return }
        guard !Task.isCancelled else { return }
        guard let self else { return }
        self.record(.heartbeat)
      }
    }
    guard observeSystem else { return }
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.normal, .warning, .critical], queue: .main)
    source.setEventHandler { [weak self] in
      Task { @MainActor in self?.recordPressure() }
    }
    pressure = source
    source.resume()
    let center = NSWorkspace.shared.notificationCenter
    for (name, event) in [
      (NSWorkspace.willSleepNotification, Event.sleep),
      (NSWorkspace.didWakeNotification, Event.wake),
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in self?.record(event) }
        })
    }
  }
  public func stop() {
    pulse?.cancel()
    pulse = nil
    pressure?.cancel()
    pressure = nil
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    observers.removeAll()
    started = false
  }
  private func recordPressure() {
    guard let flags = pressure?.data else { return }
    record(
      flags.contains(.critical)
        ? .memoryCritical : (flags.contains(.warning) ? .memoryWarning : .memoryNormal))
  }
  private static func capture(_ event: Event, began: Double, build: String?) -> Record {
    var basic = mach_task_basic_info()
    var basicCount = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let basicStatus = withUnsafeMutablePointer(to: &basic) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
      }
    }
    var vm = task_vm_info_data_t()
    var vmCount = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let vmStatus = withUnsafeMutablePointer(to: &vm) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
      }
    }
    return Record(
      event: event, processID: ProcessInfo.processInfo.processIdentifier, buildUUID: build,
      uptimeSeconds: max(0, ProcessInfo.processInfo.systemUptime - began),
      residentBytes: basicStatus == KERN_SUCCESS ? UInt64(basic.resident_size) : nil,
      physicalFootprintBytes: vmStatus == KERN_SUCCESS ? UInt64(vm.phys_footprint) : nil,
      active: NSApp?.isActive ?? false, windowCount: NSApp?.windows.count ?? 0,
      automaticTerminationSupported: ProcessInfo.processInfo.automaticTerminationSupportEnabled,
      pendingDecisions: DecisionSaveQueue.shared.hasPending,
      pendingFileWork: WorkflowOperationBarrier.shared.hasPending)
  }
  /// Read only the UUID command in the already loaded main executable. The
  /// diagnostic identifies actual running code even when its bundle is updated.
  static func loadedExecutableUUID() -> String? {
    guard let header = _dyld_get_image_header(0), header.pointee.magic == MH_MAGIC_64 else {
      return nil
    }
    let raw = UnsafeRawPointer(header)
    let value = raw.load(as: mach_header_64.self)
    var offset = MemoryLayout<mach_header_64>.size
    let end = offset + Int(value.sizeofcmds)
    for _ in 0..<value.ncmds {
      guard offset <= end - MemoryLayout<load_command>.size else { return nil }
      let command = raw.advanced(by: offset).load(as: load_command.self)
      let size = Int(command.cmdsize)
      guard size >= MemoryLayout<load_command>.size, size <= end - offset else { return nil }
      if command.cmd == LC_UUID {
        guard size >= MemoryLayout<uuid_command>.size else { return nil }
        return UUID(uuid: raw.advanced(by: offset).load(as: uuid_command.self).uuid).uuidString
      }
      offset += size
    }
    return nil
  }
}
