import Foundation

/// StoreKit product identifiers and trial constants. Must stay in sync
/// with Anky.storekit (local testing) and App Store Connect (production).
enum PurchaseConstants {
    static let subscriptionGroupName = "Anky"
    static let yearlyProductID = "anky.yearly"
    static let monthlyProductID = "anky.monthly"
    static let allProductIDs: Set<String> = [yearlyProductID, monthlyProductID]

    /// The honest reminder: 44 hours into the 72-hour trial — "your trial
    /// ends tomorrow", while there is still real time to cancel. (The
    /// notification identifier lives in LocalNotificationScheduler, which
    /// cannot see this file from the SwiftPM AnkyCore target.)
    static let trialReminderDelay: TimeInterval = 44 * 60 * 60

    /// UserDefaults key for when the free trial began (Date). Local only;
    /// used to place the trial-ending reminder.
    static let trialStartedAtKey = "anky.trialStartedAt"
}

/// Phase-3 §5: the once-per-rolling-week cap on *Anky-initiated* paywall
/// pressure, shared across every paywall-adjacent surface (today: the trial
/// Live Activity). A writer tapping a veil is asking — that is always
/// answered; this ledger only restrains what Anky starts on its own.
enum PaywallPressureLedger {
    static let windowSeconds: TimeInterval = 7 * 24 * 60 * 60
    private static let lastShownKey = "anky.paywallPressure.lastShownAt"

    static func recordPaywallShown(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastShownKey)
    }

    /// True while the writer saw a paywall within the rolling week —
    /// ambient surfaces stay quiet until the window passes.
    static func isWithinQuietWindow(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard let last = defaults.object(forKey: lastShownKey) as? Date else {
            return false
        }
        return now.timeIntervalSince(last) < windowSeconds
    }
}
