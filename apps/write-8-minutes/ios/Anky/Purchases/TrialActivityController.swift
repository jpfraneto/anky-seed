import Foundation
import StoreKit
#if canImport(ActivityKit)
import ActivityKit

/// Phase-2 §5: starts the lock-screen trial presence for writers who have
/// completed at least one session and not subscribed. Honesty rules:
/// real StoreKit price or nothing, start at most once per rolling week,
/// end the moment they subscribe, and a dismissal counts as an answer.
@available(iOS 16.1, *)
enum TrialActivityController {
    static let lastStartedAtKey = "anky.trialActivity.lastStartedAt"
    private static let weekSeconds: TimeInterval = 7 * 24 * 60 * 60

    @MainActor
    static func evaluate(entitlements: EntitlementStore) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard !entitlements.isEntitledForGating else {
            endAll()
            return
        }
        guard !SessionIndexStore().load().isEmpty else { return }
        // Real values or no surface at all.
        guard let product = entitlements.yearlyProduct else { return }
        guard Activity<TrialActivityAttributes>.activities.isEmpty else { return }
        if let last = UserDefaults.standard.object(forKey: lastStartedAtKey) as? Date,
           Date().timeIntervalSince(last) < weekSeconds {
            return
        }
        // Phase-3 §5: one rolling-week window across ALL paywall-adjacent
        // surfaces — a writer who saw the ask this week (any veil, any
        // boundary) is not asked again by an ambient surface.
        guard !PaywallPressureLedger.isWithinQuietWindow() else { return }

        let trialLine: String
        if let offer = product.subscription?.introductoryOffer,
           offer.paymentMode == .freeTrial,
           let trialDays = Self.days(of: offer.period) {
            trialLine = AnkyCopyRegistry.trialSurfaceTrialLine(
                days: trialDays,
                price: product.displayPrice
            )
        } else {
            trialLine = AnkyCopyRegistry.trialSurfacePriceLine(price: product.displayPrice)
        }
        let attributes = TrialActivityAttributes(
            headline: AnkyCopyRegistry.trialSurfaceHeadline,
            trialLine: trialLine
        )
        guard (try? Activity.request(
            attributes: attributes,
            contentState: TrialActivityAttributes.ContentState()
        )) != nil else {
            return
        }
        UserDefaults.standard.set(Date(), forKey: lastStartedAtKey)
    }

    private static func days(of period: Product.SubscriptionPeriod) -> Int? {
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        default: return nil // months/years read wrong as "N days free"
        }
    }

    @MainActor
    static func endAll() {
        for activity in Activity<TrialActivityAttributes>.activities {
            Task {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
