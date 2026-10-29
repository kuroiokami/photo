import Observation
import SwiftUI

/// Per-window review layout. Focus temporarily hides panels, then restores the
/// photographer's sidebar and filmstrip choices rather than resetting them.
@MainActor @Observable
final class WorkspaceLayout {
  var sidebar: NavigationSplitViewVisibility = .all
  var filmstrip = true
  private(set) var focused = false
  private var previousSidebar: NavigationSplitViewVisibility = .all
  func toggleFocus() {
    if focused {
      sidebar = previousSidebar
    } else {
      previousSidebar = sidebar
      sidebar = .detailOnly
    }
    focused.toggle()
  }
  func leaveFocus() { if focused { toggleFocus() } }
  var showsFilmstrip: Bool { filmstrip && !focused }
  static func filmstripHeight(edge: Double, labels: Int, folders: Bool) -> Double {
    edge * 0.7 + 80 + Double(labels * 14) + (folders ? 14 : 0)
  }
}
