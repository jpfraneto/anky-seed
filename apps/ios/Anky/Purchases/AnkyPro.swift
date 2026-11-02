//
//  AnkyPro.swift
//  Anky
//
//  Anky Pro is the price of the loom: three days free, then monthly.
//  Without it the app does not open past the paywall.
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

    static let monthlyID = "anky.monthly"
    /// Every product that has ever granted Pro. The annual plan is off sale,
    /// but anyone still holding one keeps the loom.
    private static let entitlingIDs: Set<String> = ["anky.monthly", "anky.annual"]

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
    @Published private(set) var product: Product?
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
        if product == nil { await loadProduct() }
    }

    func loadProduct() async {
        guard let loaded = try? await Product.products(for: [Self.monthlyID]).first else { return }
        product = loaded
        if let subscription = loaded.subscription {
            isEligibleForTrial = await subscription.isEligibleForIntroOffer
                && subscription.introductoryOffer != nil
        }
    }

    func purchase() async -> PurchaseOutcome {
        if product == nil { await loadProduct() }
        guard let product else {
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
            : .failed(AnkyLocalization.ui("No Anky Pro subscription was found for this Apple ID."))
    }

    // MARK: - What the paywall says

    var priceText: String {
        product?.displayPrice ?? "$8.99"
    }

    var trialDays: Int {
        guard let offer = product?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return 3 }
        switch offer.period.unit {
        case .day: return offer.period.value
        case .week: return offer.period.value * 7
        default: return 3
        }
    }
}
