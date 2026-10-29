import Foundation

/// Immutable membership inputs. Bulk evaluation does not repeatedly enter the
/// workspace's Observation accessors, and sorting can evaluate it off-main.
struct PhotoVisibility: Sendable {
  let grouped: Bool
  let families: [String: [PhotoItem]]
  let review: Set<String>?
  let filter: FlagFilter
  let minimumRating: Int
  let loading: Bool
  let decisions: [String: CullingDecision]
  let ready: Set<String>

  var filtersDecisions: Bool { filter != .all || minimumRating > 0 }
  var unrestricted: Bool { !grouped && review == nil && !filtersDecisions }
  func contains(_ photo: PhotoItem) -> Bool {
    if grouped, (families[photo.id]?.first?.id ?? photo.id) != photo.id { return false }
    if let review, !review.contains(photo.id),
      !(grouped && (families[photo.id]?.contains { review.contains($0.id) } ?? false))
    {
      return false
    }
    guard filtersDecisions else { return true }
    guard ready.contains(photo.id) else { return false }
    let decision = decisions[photo.id] ?? CullingDecision()
    return filter.includes(decision.flag) && decision.rating >= minimumRating
  }
  func photos(in candidates: [PhotoItem]) -> [PhotoItem] {
    if loading && filtersDecisions { return [] }
    if unrestricted { return candidates }
    return candidates.filter { contains($0) }
  }
}

/// Prepared away from the main actor; publishing transfers aligned arrays/indexes.
struct PreparedPhotoCollection: Sendable {
  let ordered: [PhotoItem]
  let visible: [PhotoItem]
  let fullIndex: [String: Int]
  let index: [String: Int]
}
