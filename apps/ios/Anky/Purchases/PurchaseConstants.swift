import Foundation
import RevenueCat

enum AnkySubscriptionPlan: String, CaseIterable, Hashable {
    case annual
    case monthly

    var productID: String {
        switch self {
        case .annual:
            return AnkyPurchasesConfig.annualProductID
        case .monthly:
            return AnkyPurchasesConfig.monthlyProductID
        }
    }

    /// Billing duration is presentation/configuration truth only. Feature
    /// access never branches on this value; both plans grant the same `pro`
    /// entitlement.
    var expectedPeriod: (value: Int, unit: SubscriptionPeriod.Unit) {
        switch self {
        case .annual:
            return (1, .year)
        case .monthly:
            return (1, .month)
        }
    }

    var entitlementID: String {
        AnkyPurchasesConfig.entitlementID
    }
}

enum SubscriptionCatalogPolicy {
    static func discoveredPlans(productIDs: Set<String>) -> Set<AnkySubscriptionPlan> {
        Set(AnkySubscriptionPlan.allCases.filter { productIDs.contains($0.productID) })
    }

    static func packageMatchesExpectedPeriod(_ package: Package, plan: AnkySubscriptionPlan) -> Bool {
        guard package.storeProduct.productIdentifier == plan.productID,
              let period = package.storeProduct.subscriptionPeriod else {
            return false
        }
        return period.value == plan.expectedPeriod.value && period.unit == plan.expectedPeriod.unit
    }

    static func hasExpectedAnnualFreeTrial(_ product: StoreProduct?) -> Bool {
        guard let offer = product?.introductoryDiscount else {
            return false
        }
        return offer.paymentMode == .freeTrial
            && offer.subscriptionPeriod.value == 3
            && offer.subscriptionPeriod.unit == .day
            && offer.numberOfPeriods == 1
    }
}

/// Trial copy is legal only in the single positively-confirmed state. Every
/// other state deliberately renders the ordinary annual purchase terms.
enum AnnualTrialEligibilityState: Equatable {
    case loading
    case eligible
    case ineligible
    case unknown
    case failed
    case noOffer
    case unsupported

    var displaysTrial: Bool {
        self == .eligible
    }

    static func fromRevenueCat(_ status: IntroEligibilityStatus?) -> Self {
        guard let status else {
            return .failed
        }
        switch status {
        case .eligible:
            return .eligible
        case .ineligible:
            return .ineligible
        case .unknown:
            return .unknown
        case .noIntroOfferExists:
            return .noOffer
        @unknown default:
            return .unsupported
        }
    }
}

enum EntitlementVerificationState: Equatable {
    case unverified
    case refreshing
    case verifiedActive
    case verifiedInactive
    case refreshFailed

    var hasVerifiedPro: Bool {
        self == .verifiedActive
    }

    var isCurrent: Bool {
        self == .verifiedActive || self == .verifiedInactive
    }
}

enum SubscriptionTransactionResolution: Equatable {
    case activated
    case cancelled
    case failed
    case missingProEntitlement
    case nothingToRestore
}

enum SubscriptionTransactionPolicy {
    static func purchaseSucceeded(
        userCancelled: Bool,
        activeEntitlementIDs: Set<String>
    ) -> SubscriptionTransactionResolution {
        if userCancelled {
            return .cancelled
        }
        return activeEntitlementIDs.contains(AnkyPurchasesConfig.entitlementID)
            ? .activated
            : .missingProEntitlement
    }

    static func restoreSucceeded(
        activeEntitlementIDs: Set<String>
    ) -> SubscriptionTransactionResolution {
        activeEntitlementIDs.contains(AnkyPurchasesConfig.entitlementID)
            ? .activated
            : .nothingToRestore
    }
}

enum OnboardingSubscriptionAction: Equatable {
    case purchaseActivated
    case restoreActivated
    case continueFree
    case purchaseCancelled
    case purchaseFailed
    case restoreWithoutEntitlement
    case productsUnavailable
}

enum SubscriptionCatalogPresentationState: Equatable {
    case loading
    case available
    case unavailable
}

enum OnboardingSubscriptionPolicy {
    static func shouldAdvance(after action: OnboardingSubscriptionAction) -> Bool {
        switch action {
        case .purchaseActivated, .restoreActivated, .continueFree:
            return true
        case .purchaseCancelled, .purchaseFailed, .restoreWithoutEntitlement, .productsUnavailable:
            return false
        }
    }

    /// Store availability never turns the onboarding paywall into a hard
    /// gate. This explicit invariant keeps the free action independent from
    /// RevenueCat/StoreKit loading and failure states.
    static func allowsFreeContinuation(
        while catalogState: SubscriptionCatalogPresentationState
    ) -> Bool {
        switch catalogState {
        case .loading, .available, .unavailable:
            return true
        }
    }
}

enum AnkyFeature: CaseIterable {
    case writing
    case localWritingNudge
    case existingReflection
    case gate
    case quickPass
    case emergencyUnlock
    case staticPaintingLevelsOneThroughEight
    case deliveredPersonalizedPainting
    case archiveAndHistory
    case backupAndSettings
    case newAIReflection
    case serverWritingNudge
    case journey
    case automaticDailyTargetUnlock
    case adaptiveTargetSuggestions
    case personalizedPaintingAfterLevelEight
}

enum AnkyFeatureAccessPolicy {
    static func requiresPro(_ feature: AnkyFeature) -> Bool {
        switch feature {
        case .newAIReflection,
             .serverWritingNudge,
             .journey,
             .automaticDailyTargetUnlock,
             .adaptiveTargetSuggestions,
             .personalizedPaintingAfterLevelEight:
            return true
        case .writing,
             .localWritingNudge,
             .existingReflection,
             .gate,
             .quickPass,
             .emergencyUnlock,
             .staticPaintingLevelsOneThroughEight,
             .deliveredPersonalizedPainting,
             .archiveAndHistory,
             .backupAndSettings:
            return false
        }
    }
}

enum SubscriptionLegalLinks {
    static let privacyPolicyURL = URL(string: "https://anky.app/privacy-policy")!
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// StoreKit/RevenueCat is the only source of customer-facing prices. A missing
/// product stays missing so callers can render loading, unavailable, or retry;
/// this formatter never invents a currency or amount.
enum SubscriptionPriceFormatter {
    static func price(_ product: StoreProduct?) -> String? {
        price(localizedStorePrice: product?.localizedPriceString)
    }

    static func price(localizedStorePrice: String?) -> String? {
        guard let localizedStorePrice else {
            return nil
        }
        let trimmed = localizedStorePrice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
