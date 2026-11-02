import Foundation
import Testing

@testable import PhotoCore

@MainActor
struct SaveQueueLifetimeTests {
  private final class Payload {
    var value = 0
  }
  @Test(.timeLimit(.minutes(1))) func completedSavesReleaseTheirCapturedWorkspacePayloads() async {
    let queue = DecisionSaveQueue()
    var references: [WeakPayload] = []
    for index in 0..<512 {
      let payload = Payload()
      payload.value = index
      references.append(WeakPayload(payload))
      queue.enqueue {
        await Task.yield()
        #expect(payload.value == index)
      }
    }
    #expect(queue.hasPending)
    await queue.flush()
    #expect(!queue.hasPending)
    #expect(queue.pendingOperationCount == 0)
    // A completed Task must release its work/capture chain even while the queue
    // retains its final tail. Otherwise long culling sessions retain old models.
    for _ in 0..<20 where references.contains(where: { $0.value != nil }) { await Task.yield() }
    #expect(references.allSatisfy { $0.value == nil })
    var savedAfterIdle = false
    queue.enqueue { savedAfterIdle = true }
    await queue.flush()
    #expect(savedAfterIdle)
  }
  private final class WeakPayload {
    weak var value: Payload?
    init(_ value: Payload) { self.value = value }
  }
}
