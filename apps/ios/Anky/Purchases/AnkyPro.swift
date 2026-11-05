//
//  AnkyPro.swift
//  Anky
//
//  The subscription is the price of Anky: three days free, then yearly
//  or monthly. Without it the app does not open past the paywall. There is
//  no "Pro": only Anky (founder, 2026-11-04).
//
//  StoreKit 2 only, straight with Apple. No Anky server and no third
//  party: the entitlement is read from the transactions on this device,
//  which StoreKit keeps signed and available offline.
//

import Foundation
import StoreKit

@MainActor
final class AnkyPro: ObservableObject {
    static let shared = AnkyPro()

    static let annualID = "anky.annual"
    static let monthlyID = "anky.monthly"
    /// Every product that opens Anky.
    private static let entitlingIDs: Set<String> = [annualID, monthlyID]

    /// The two ways to pay. Yearly is the one offered first.
    enum Plan: String, CaseIterable, Identifiable {
        case annual
        case monthly

        var id: String { rawValue }

        var productID: String {
            switch self {
            case .annual: return AnkyPro.annualID
            case .monthly: return AnkyPro.monthlyID
            }
        }
    }

    enum Access: Equatable {
        /// Never confirmed on this device yet; the gate waits quietly.
        case checking
        case active
        case inactive
    }

    enum PurchaseOutcome: Equatable {
        case activated
        case cancelled
        case pending
        case failed(String)
    }

    @Published private(set) var access: Access
    @Published private(set) var products: [Plan: Product] = [:]
    @Published private(set) var isEligibleForTrial = true
    @Published private(set) var isWorking = false

    /// The last known end of an active subscription, so a subscriber never
    /// sees the paywall flash while StoreKit answers at launch.
    private static let cachedExpiryKey = "anky.pro.cachedExpiry.v1"
    private var updatesTask: Task<Void, Never>?

    private init() {
        let cached = UserDefaults.standard.object(forKey: Self.cachedExpiryKey) as? Date
        access = (cached.map { $0 > Date() } ?? false) ? .active : .checking
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ankyProActive") || ScreenshotMode.isActive {
            access = .active
        }
        #endif
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    /// Launch, every foreground, and after any transaction.
    func refresh() async {
        #if DEBUG
        // Simulator QA without a purchase: `-ankyProActive`.
        // Screenshot scenes stage the page itself: the door stays open.
        if ProcessInfo.processInfo.arguments.contains("-ankyProActive") || ScreenshotMode.isActive {
            access = .active
            return
        }
        #endif
        var activeUntil: Date?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  Self.entitlingIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            let end = transaction.expirationDate ?? .distantFuture
            if end > Date() {
                activeUntil = max(activeUntil ?? end, end)
            }
        }
        if let activeUntil {
            UserDefaults.standard.set(activeUntil, forKey: Self.cachedExpiryKey)
            access = .active
        } else {
            UserDefaults.standard.removeObject(forKey: Self.cachedExpiryKey)
            access = .inactive
        }
        if products.count < Plan.allCases.count { await loadProducts() }
    }

    func loadProducts() async {
        guard let loaded = try? await Product.products(for: Plan.allCases.map(\.productID)) else { return }
        var byPlan: [Plan: Product] = [:]
        for product in loaded {
            if let plan = Plan.allCases.first(where: { $0.productID == product.id }) {
                byPlan[plan] = product
            }
        }
        guard !byPlan.isEmpty else { return }
        products = byPlan
        // Trial eligibility is per subscription group: both plans agree.
        if let subscription = (byPlan[.annual] ?? byPlan[.monthly])?.subscription {
            isEligibleForTrial = await subscription.isEligibleForIntroOffer
                && subscription.introductoryOffer != nil
        }
    }

    func purchase(_ plan: Plan) async -> PurchaseOutcome {
        if products[plan] == nil { await loadProducts() }
        guard let product = products[plan] else {
            return .failed(AnkyLocalization.ui("The App Store isn't answering. Check your connection and try again."))
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    return .failed(AnkyLocalization.ui("Apple couldn't verify this purchase. Nothing was charged."))
                }
                await transaction.finish()
                await refresh()
                return access == .active ? .activated : .pending
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(AnkyLocalization.ui("The purchase didn't go through. Nothing was charged."))
        }
    }

    /// Asks Apple for this Apple ID's purchases again.
    func restore() async -> PurchaseOutcome {
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        await refresh()
        return access == .active
            ? .activated
            : .failed(AnkyLocalization.ui("No Anky subscription was found for this Apple ID."))
    }

    // MARK: - What the paywall says

    /// The localized price, with the App Store's own answer when it has one.
    func priceText(_ plan: Plan) -> String {
        if let product = products[plan] { return product.displayPrice }
        switch plan {
        case .annual: return "$49.99"
        case .monthly: return "$8.99"
        }
    }

    /// What the yearly plan comes to per month, rounded down.
    var annualPerMonthText: String? {
        guard let annual = products[.annual] else { return nil }
        var monthly = annual.price / 12
        var rounded = Decimal()
        NSDecimalRound(&rounded, &monthly, 2, .down)
        return rounded.formatted(annual.priceFormatStyle)
    }

    /// How much less the yearly plan costs than twelve months, rounded down.
    var annualSavingsPercent: Int? {
        guard let annual = products[.annual], let monthly = products[.monthly] else { return nil }
        let twelveMonths = monthly.price * 12
        guard twelveMonths > 0 else { return nil }
        let saved = NSDecimalNumber(decimal: 1 - annual.price / twelveMonths).doubleValue
        let percent = Int((saved * 100).rounded(.down))
        return percent > 0 ? percent : nil
    }

    var trialDays: Int {
        guard let offer = (products[.annual] ?? products[.monthly])?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return 3 }
        switch offer.period.unit {
        case .day: return offer.period.value
        case .week: return offer.period.value * 7
        default: return 3
        }
    }
}
