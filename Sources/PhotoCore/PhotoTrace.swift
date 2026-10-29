import os

/// Local Instruments markers only. Never attach filenames, paths, EXIF or captions.
public enum PhotoTrace {
  private static let signposter = OSSignposter(
    subsystem: "org.photo.performance", category: .pointsOfInterest)
  public struct Interval: Sendable {
    fileprivate let name: StaticString
    fileprivate let id: OSSignpostID
    fileprivate let state: OSSignpostIntervalState?
  }
  @TaskLocal public static var request: Interval?

  public static func begin(_ name: StaticString, parent: Interval? = nil) -> Interval {
    guard signposter.isEnabled else {
      return Interval(name: name, id: .null, state: nil)
    }
    let ancestor = parent ?? request
    let id = ancestor?.state != nil ? ancestor!.id : signposter.makeSignpostID()
    return Interval(name: name, id: id, state: signposter.beginInterval(name, id: id))
  }
  public static func end(_ interval: Interval) {
    guard let state = interval.state else { return }
    signposter.endInterval(interval.name, state)
  }
  public static func event(_ name: StaticString, in interval: Interval? = nil) {
    guard signposter.isEnabled else { return }
    let ancestor = interval ?? request
    let id = ancestor?.state != nil ? ancestor!.id : signposter.makeSignpostID()
    signposter.emitEvent(name, id: id)
  }
}

/// Counts publication operations, not SwiftUI body evaluations or rendered frames.
public struct WorkspacePublicationMetrics: Codable, Sendable {
  public internal(set) var metadata = 0
  public internal(set) var decisions = 0
  public internal(set) var metadataWork = PublicationWork()
  public internal(set) var decisionWork = PublicationWork()
}
