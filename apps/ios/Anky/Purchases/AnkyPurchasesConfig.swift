import Foundation
import RevenueCat

/// The one configuration surface for everything purchases. RevenueCat is
/// the single transaction owner (it observes and finishes every StoreKit
/// transaction); the app never talks to StoreKit directly.
///
/// These values must stay in sync with the RevenueCat dashboard
/// (entitlement + offering), Anky.storekit (local testing), and App Store
/// Connect (production).
enum AnkyPurchasesConfig {
    /// RevenueCat public Apple API key (safe to ship in the binary).
    static let revenueCatPublicKey = "appl_mvCsxolPWZmQjtULGLQhmOUhGMY"

    /// The single entitlement every gate checks — purchased or granted.
    static let entitlementID = "pro"

    /// The only offering the iOS app accepts. A differently named current
    /// offering must never silently replace it.
    static let offeringID = "default"

    static let subscriptionGroupName = "Anky"
    static let annualProductID = "anky.annual"
    static let monthlyProductID = "anky.monthly"
    /// The lean gate's third door (user decision, 2026-07-17: "skin in the
    /// game opens the gate" — weekly, monthly or yearly). Must be created in
    /// App Store Connect and added to the RevenueCat `default` offering
    /// before release; until then the weekly line renders unpriced.
    static let weeklyProductID = "anky.weekly"
    static let allProductIDs: Set<String> = [annualProductID, monthlyProductID, weeklyProductID]

    /// The honest reminder fires this long BEFORE the trial converts —
    /// "your trial ends tomorrow", while there is still real time to
    /// cancel. (28h before the end of a 72h trial ≈ the old 44h-in mark.)
    static let trialReminderLeadTime: TimeInterval = 28 * 60 * 60
}

/// Launch-time RevenueCat configuration. Called from AppRoot once identity
/// is loaded — never lazily from a feature path, so every surface sees the
/// same configured SDK from the first frame on.
///
/// Pattern choice: `Purchases.configure(withAPIKey:appUserID:)` with the
/// wallet address directly, NOT configure-anonymous-then-logIn. Identity
/// is created synchronously before this runs, so there is never a window
/// where a purchase could attach to an anonymous RevenueCat ID. If
/// identity creation fails we fail closed: the SDK stays unconfigured, no
/// purchase path opens, and the next foreground retries.
enum AnkyPurchases {
    @MainActor
    private(set) static var configuredAccountId: String?

    /// True once the SDK is configured under a real writer identity.
    @MainActor
    static var isConfigured: Bool {
        configuredAccountId != nil
    }

    /// Configures on first call, re-identifies via `logIn` if the wallet
    /// changed (iCloud restore adopting another writer's identity).
    /// Returns the active appUserID, or nil when identity is unavailable
    /// (fail closed — retry on next foreground).
    @MainActor
    @discardableResult
    static func identifyCurrentWriter(
        identityStore: WriterIdentityStore = WriterIdentityStore()
    ) async -> String? {
        guard let identity = try? identityStore.loadOrCreate(),
              !identity.address.isEmpty else {
            return nil
        }
        let accountId = identity.address

        guard let configured = configuredAccountId else {
            #if DEBUG
            Purchases.logLevel = .debug
            #endif
            Purchases.configure(
                withAPIKey: AnkyPurchasesConfig.revenueCatPublicKey,
                appUserID: accountId
            )
            configuredAccountId = accountId
            return accountId
        }

        guard configured != accountId else {
            return accountId
        }
        guard (try? await Purchases.shared.logIn(accountId)) != nil else {
            return configured
        }
        configuredAccountId = accountId
        return accountId
    }
}
