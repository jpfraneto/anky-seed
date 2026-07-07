import Foundation
import RevenueCat

/// Price presentation over RevenueCat's `StoreProduct`. Whole prices drop
/// the cents ($88/year, never $88.00/year); everything else is the
/// store-localized string untouched.
enum SubscriptionPriceFormatter {
    static func price(_ product: StoreProduct?, fallback: String) -> String {
        guard let product else {
            return fallback
        }
        guard isWhole(product.price) else {
            return product.localizedPriceString
        }
        guard let formatter = product.priceFormatter?.copy() as? NumberFormatter else {
            return product.localizedPriceString
        }
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: product.price as NSDecimalNumber) ?? product.localizedPriceString
    }

    /// The yearly price told as a week — "$1.69/wk" honesty on the plan
    /// selector. Falls back when the store hasn't answered yet.
    static func weekly(of product: StoreProduct?, fallback: String) -> String {
        guard let product,
              let formatter = product.priceFormatter else {
            return fallback
        }
        let weekly = (product.price as NSDecimalNumber)
            .dividing(by: 52, withBehavior: Self.centsRounding)
        return formatter.string(from: weekly) ?? fallback
    }

    private static let centsRounding = NSDecimalNumberHandler(
        roundingMode: .plain,
        scale: 2,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )

    private static func isWhole(_ value: Decimal) -> Bool {
        var decimal = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, 0, .plain)
        return decimal == rounded
    }
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
