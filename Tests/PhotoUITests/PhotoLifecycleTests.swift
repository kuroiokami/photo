import Foundation
import Testing

@testable import PhotoUI

@MainActor
struct PhotoLifecycleTests {
  private enum Timeout: Error { case waiting }
  @Test func lifecycleSamplingIsIdempotentAndStopsAfterTermination() async throws {
    var events: [PhotoLifecycle.Event] = []
    let lifecycle = PhotoLifecycle(
      interval: .milliseconds(5),
      sample: { event in
        PhotoLifecycle.Record(
          event: event, processID: 1, buildUUID: nil, uptimeSeconds: 0,
          residentBytes: nil, physicalFootprintBytes: nil, active: false, windowCount: 0,
          automaticTerminationSupported: false, pendingDecisions: false, pendingFileWork: false)
      }, emit: { events.append($0.event) })
    defer { lifecycle.stop() }
    lifecycle.record(.launch)
    lifecycle.start(observeSystem: false)
    lifecycle.start(observeSystem: false)
    let until = ContinuousClock.now.advanced(by: .seconds(2))
    while !events.contains(.heartbeat) {
      guard ContinuousClock.now < until else { throw Timeout.waiting }
      try await Task.sleep(for: .milliseconds(1))
    }
    lifecycle.record(.quitRequested)
    lifecycle.record(.waitingForSaves)
    lifecycle.record(.willTerminate)
    lifecycle.stop()
    let stopped = events.count
    try await Task.sleep(for: .milliseconds(20))
    #expect(events.count == stopped)
    #expect(events.filter { $0 == .ready }.count == 1)
    #expect(Array(events.suffix(3)) == [.quitRequested, .waitingForSaves, .willTerminate])
  }
  @Test func diagnosticsHaveFixedFieldsAndLoadedExecutableIdentity() throws {
    let build = try #require(PhotoLifecycle.loadedExecutableUUID())
    #expect(UUID(uuidString: build) != nil)
    let record = PhotoLifecycle.Record(
      event: .background, processID: 1, buildUUID: build,
      uptimeSeconds: 123, residentBytes: 1024, physicalFootprintBytes: nil, active: false,
      windowCount: 1, automaticTerminationSupported: false, pendingDecisions: false,
      pendingFileWork: false)
    let value = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
    #expect(
      Set(value.keys) == [
        "event", "processID", "buildUUID", "uptimeSeconds", "residentBytes", "active",
        "windowCount", "automaticTerminationSupported", "pendingDecisions", "pendingFileWork",
      ])
    #expect(value["event"] as? String == "background")
  }
}
