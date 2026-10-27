//
//  SubscriptionService.swift
//  Anky
//
//  The one owner of everything purchases. RevenueCat is the single
//  transaction owner (it observes and finishes every StoreKit transaction);
//  the app never talks to StoreKit directly and has no other purchase path.
//
//  What is sold (audited 2026-10-27 against App Store Connect and the
//  RevenueCat offering — not against older docs):
//    • `anky.monthly` — auto-renewing monthly, subscription group "Anky Pro",
//      no App Store introductory offer. RevenueCat offering `default`,
//      package `$rc_monthly`, entitlement `pro`.
//    • `anky.annual` also exists but carries a 3-day App Store free trial.
//      The seven free days are app-managed and must never be confused with a
//      store trial that converts into billing, so annual is not offered.
//
//  The seven free days are NOT an App Store offer. Nothing is billed when
//  they end; payment begins only when the person taps Subscribe and
//  confirms with Apple.
//

import Foundation
import RevenueCat

enum AnkyPurchasesConfig {
    /// RevenueCat public Apple SDK key (safe to ship in the binary).
    static let revenueCatPublicKey = "appl_mvCsxolPWZmQjtULGLQhmOUhGMY"
    static let entitlementID = "pro"
    static let offeringID = "default"
    static let monthlyProductID = "anky.monthly"

    static let privacyPolicyURL = URL(string: "https://anky.app/privacy-policy/")!
    /// Apple's standard EULA, which the App Store listing also uses.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
}

/// The monthly plan as StoreKit reports it, localized. Never invented: if
/// the store has not answered, there is no plan to show.
struct SubscriptionPlan: Equatable {
    let productID: String
    let localizedPrice: String
    /// e.g. "month"; from StoreKit's period, not assumed.
    let periodUnit: String
    let periodValue: Int
}

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    enum Activity: Equatable {
        case idle
        case loadingPlan
        case purchasing
        case restoring
    }

    enum Outcome: Equatable {
        case activated
        case cancelled
        case nothingToRestore
        case failed(String)
        case pending
    }

    @Published private(set) var status: SubscriptionStatus
    @Published private(set) var plan: SubscriptionPlan?
    @Published private(set) var planUnavailable = false
    @Published private(set) var activity: Activity = .idle
    /// Apple reported a billing problem; access continues through Apple's
    /// grace period while RevenueCat keeps the entitlement active.
    @Published private(set) var hasBillingIssue = false
    /// The subscription is active but will not renew (cancelled).
    @Published private(set) var willNotRenew = false

    private var package: Package?
    private var configuredAccountId: String?
    private var streamTask: Task<Void, Never>?
    private let statusStore = SubscriptionStatusStore()

    private init() {
        status = statusStore.load() ?? .unknown
    }

    var isConfigured: Bool { configuredAccountId != nil }

    /// Configures RevenueCat under the writer's account id (the same id the
    /// server uses), so a purchase can never attach to an anonymous user.
    /// Fails closed: without identity there is no purchase path.
    func configure(accountId: String) {
        guard configuredAccountId == nil else {
            if configuredAccountId != accountId {
                Task { _ = try? await Purchases.shared.logIn(accountId) }
                configuredAccountId = accountId
            }
            return
        }
        #if DEBUG
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: AnkyPurchasesConfig.revenueCatPublicKey, appUserID: accountId)
        configuredAccountId = accountId
        streamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    /// Re-verifies with RevenueCat. Called on launch and every foreground.
    func refresh() async {
        guard isConfigured else { return }
        if let info = try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent) {
            apply(info)
        }
    }

    func loadPlan() async {
        guard isConfigured else {
            // No identity, no purchase path (fail closed) — say so plainly.
            planUnavailable = true
            return
        }
        guard plan == nil, activity == .idle else { return }
        activity = .loadingPlan
        defer { if activity == .loadingPlan { activity = .idle } }
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.offering(identifier: AnkyPurchasesConfig.offeringID) ?? offerings.current
            guard let monthly = offering?.availablePackages.first(where: {
                $0.storeProduct.productIdentifier == AnkyPurchasesConfig.monthlyProductID
            }), let period = monthly.storeProduct.subscriptionPeriod,
               period.unit == .month, period.value == 1 else {
                planUnavailable = true
                return
            }
            package = monthly
            plan = SubscriptionPlan(
                productID: monthly.storeProduct.productIdentifier,
                localizedPrice: monthly.storeProduct.localizedPriceString,
                periodUnit: "month",
                periodValue: period.value
            )
            planUnavailable = false
        } catch {
            planUnavailable = true
        }
    }

    func purchase() async -> Outcome {
        guard let package, activity == .idle else { return .failed(AnkyLocalization.ui("The subscription is not available right now.")) }
        activity = .purchasing
        defer { activity = .idle }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            apply(result.customerInfo)
            if result.userCancelled { return .cancelled }
            return isEntitled(result.customerInfo) ? .activated : .pending
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            return .cancelled
        } catch let error as ErrorCode where error == .paymentPendingError {
            return .pending
        } catch {
            return .failed(AnkyLocalization.ui("The purchase did not go through. You were not charged."))
        }
    }

    func restore() async -> Outcome {
        guard isConfigured, activity == .idle else { return .failed(AnkyLocalization.ui("Restore is not available right now.")) }
        activity = .restoring
        defer { activity = .idle }
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            return isEntitled(info) ? .activated : .nothingToRestore
        } catch {
            return .failed(AnkyLocalization.ui("Could not reach the App Store. Try again in a moment."))
        }
    }

    private func isEntitled(_ info: CustomerInfo) -> Bool {
        info.entitlements[AnkyPurchasesConfig.entitlementID]?.isActive == true
    }

    private func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements[AnkyPurchasesConfig.entitlementID]
        let verifiedAt = info.requestDate
        if let entitlement, entitlement.isActive {
            status = .active(verifiedAt: verifiedAt, expiresAt: entitlement.expirationDate)
            hasBillingIssue = entitlement.billingIssueDetectedAt != nil
            willNotRenew = !entitlement.willRenew
        } else {
            status = .inactive(verifiedAt: verifiedAt)
            hasBillingIssue = false
            willNotRenew = false
        }
        statusStore.save(status)
    }
}

/// The last verified subscription answer, so a launch without network still
/// knows (within AccessPolicy's bound) who subscribed.
struct SubscriptionStatusStore {
    private let defaults: UserDefaults
    private static let key = "anky.access.subscription.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private struct Stored: Codable {
        var active: Bool
        var verifiedAt: Date
        var expiresAt: Date?
    }

    func load() -> SubscriptionStatus? {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder.accessDecoder.decode(Stored.self, from: data) else { return nil }
        return stored.active
            ? .active(verifiedAt: stored.verifiedAt, expiresAt: stored.expiresAt)
            : .inactive(verifiedAt: stored.verifiedAt)
    }

    func save(_ status: SubscriptionStatus) {
        let stored: Stored
        switch status {
        case .unknown:
            defaults.removeObject(forKey: Self.key)
            return
        case .active(let verifiedAt, let expiresAt):
            stored = Stored(active: true, verifiedAt: verifiedAt, expiresAt: expiresAt)
        case .inactive(let verifiedAt):
            stored = Stored(active: false, verifiedAt: verifiedAt, expiresAt: nil)
        }
        if let data = try? JSONEncoder.accessEncoder.encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
