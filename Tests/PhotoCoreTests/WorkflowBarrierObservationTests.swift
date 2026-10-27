import Foundation
import Observation
import Testing

@testable import PhotoCore

private final class WorkflowNotification: @unchecked Sendable {
  private let lock = NSLock()
  private var changed = false
  func record() { lock.withLock { changed = true } }
  var value: Bool { lock.withLock { changed } }
}
private actor WorkflowGate {
  private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
  private var released: Set<Int> = []
  func wait(_ id: Int) async {
    guard !released.contains(id) else { return }
    await withCheckedContinuation { gates[id] = $0 }
  }
  func release(_ id: Int) {
    released.insert(id)
    gates.removeValue(forKey: id)?.resume()
  }
}
struct WorkflowBarrierObservationTests {
  @MainActor @Test func allWindowsCanObserveFileWorkStartingAndFinishing() async {
    let barrier = WorkflowOperationBarrier()
    let gate = WorkflowGate()
    let began = WorkflowNotification()
    withObservationTracking {
      _ = barrier.hasPending
    } onChange: {
      began.record()
    }
    let first = Task { await gate.wait(1) }
    let second = Task { await gate.wait(2) }
    barrier.track(first)
    barrier.track(second)
    #expect(barrier.hasPending)
    #expect(began.value)
    await gate.release(1)
    await first.value
    #expect(barrier.hasPending)
    let ended = WorkflowNotification()
    withObservationTracking {
      _ = barrier.hasPending
    } onChange: {
      ended.record()
    }
    await gate.release(2)
    await barrier.flush()
    #expect(!barrier.hasPending)
    #expect(ended.value)
  }
}
