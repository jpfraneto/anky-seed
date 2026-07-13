import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Phase-2 §5: the honest trial surface. Entirely static — no ContentState
/// updates, no countdown, no scarcity. The copy is fixed when the activity
/// starts and never changes.
@available(iOS 16.1, *)
struct TrialActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}

    var headline: String
    var trialLine: String
}
#endif
