import CryptoKit
import Foundation
import StoreKit

/// The single source of truth for whether the practice is paid for.
/// Listens to `Transaction.updates` for renewals, revocations, and
/// Ask-to-Buy approvals, and derives `isEntitled` from
/// `Transaction.currentEntitlements`.
///
/// Local testing: select Anky.storekit in the scheme (Product → Scheme →
/// Edit Scheme… → Run → Options → StoreKit Configuration). Purchases then
/// go through the local config — no App Store Connect, works on device.
/// To reset test purchases: Xcode menu Debug → StoreKit → Manage
/// Transactions…, select the transactions and delete them.
@MainActor
final class EntitlementStore: ObservableObject {
    /// QA override: treats the writer as NOT entitled everywhere gating
    /// decisions are made, so the paywall shows even after a test
    /// purchase (purchases persist across onboarding re-runs). MUST be
    /// set back to false before shipping a build.
    static let ignoresEntitlementForQA = false

    @Published private(set) var isEntitled = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false

    /// The signed StoreKit 2 representation of the current entitlement —
    /// what the backend verifies against Apple's certificate chain.
    private(set) var latestTransactionJws: String?

    private var updatesTask: Task<Void, Never>?

    private static let wasEntitledKey = "anky.subscription.wasEntitled"
    private static let lastSyncedJwsHashKey = "anky.subscription.lastSyncedJwsHash"
    private static let lastSyncedAtKey = "anky.subscription.lastSyncedAt"

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await refreshEntitlement()
            await loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// What gates should consult — `isEntitled` filtered through the QA
    /// override, so a forced paywall run behaves exactly like a lapsed one.
    var isEntitledForGating: Bool {
        Self.ignoresEntitlementForQA ? false : isEntitled
    }

    /// Presentation-level snapshot for surfaces outside AppRoot's object
    /// graph (archive reveal, sealing flow). Written on every entitlement
    /// refresh; respects the QA override like every other gate.
    nonisolated static var lastKnownEntitledForGating: Bool {
        ignoresEntitlementForQA ? false : UserDefaults.standard.bool(forKey: wasEntitledKey)
    }

    var yearlyProduct: Product? {
        products.first { $0.id == PurchaseConstants.yearlyProductID }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == PurchaseConstants.monthlyProductID }
    }

    func loadProducts() async {
        guard products.isEmpty else {
            return
        }
        products = (try? await Product.products(for: PurchaseConstants.allProductIDs)) ?? []
    }

    func refreshEntitlement() async {
        var entitled = false
        var jws: String?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  PurchaseConstants.allProductIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else {
                continue
            }
            entitled = true
            jws = result.jwsRepresentation
        }
        latestTransactionJws = jws
        noteEntitlementTransition(entitled: entitled)
        isEntitled = entitled
    }

    /// Fires the `lapsed` funnel event exactly once per narrowing — the
    /// moment a previously entitled writer's subscription ends locally.
    private func noteEntitlementTransition(entitled: Bool) {
        let wasEntitled = UserDefaults.standard.bool(forKey: Self.wasEntitledKey)
        if wasEntitled, !entitled {
            AnkyFunnel.report(AnkyFunnel.lapsed)
        }
        UserDefaults.standard.set(entitled, forKey: Self.wasEntitledKey)
    }

    /// Runs the StoreKit purchase. Returns true only when the writer is
    /// entitled when it finishes. `.pending` (Ask to Buy / SCA) returns
    /// false — `Transaction.updates` will land the entitlement if it is
    /// later approved. `.userCancelled` returns false, silently.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard !isPurchasing else {
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }

        // The appAccountToken binds the receipt to the writer's wallet in
        // App Store Server Notifications, so refunds and renewals map back
        // to the account even if the app never opens again.
        var options: Set<Product.PurchaseOption> = []
        if let token = Self.walletAppAccountToken() {
            options.insert(.appAccountToken(token))
        }
        guard let result = try? await product.purchase(options: options) else {
            return false
        }
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                return false
            }
            await transaction.finish()
            await refreshEntitlement()
            // Race-safe pay → confirm → generate: the server must know
            // before any gated work (painting generation) is attempted.
            // Offline here is fine — gates fail closed and the next
            // foreground sync heals it.
            await syncEntitlementToBackend()
            return isEntitled
        case .pending, .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
        if isEntitled {
            AnkyFunnel.report(AnkyFunnel.restored)
            await syncEntitlementToBackend()
        }
    }

    // MARK: - Server truth (phase-3 §4)

    /// Deterministic UUID derived from the wallet address, so the same
    /// writer always presents the same appAccountToken to the App Store.
    static func walletAppAccountToken(
        identityStore: WriterIdentityStore = WriterIdentityStore()
    ) -> UUID? {
        guard let identity = try? identityStore.loadOrCreate() else {
            return nil
        }
        let digest = SHA256.hash(data: Data(identity.address.lowercased().utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Pushes the current entitlement JWS to the mirror, which verifies it
    /// against Apple's certificate chain and caches entitlement for every
    /// gated endpoint. Returns the server's answer, nil when unreachable.
    @discardableResult
    func syncEntitlementToBackend() async -> Bool? {
        guard let jws = latestTransactionJws,
              let identity = try? WriterIdentityStore().loadOrCreate() else {
            return nil
        }
        guard let state = try? await LevelSyncClient().syncSubscription(
            signedTransaction: jws,
            identity: identity
        ) else {
            return nil
        }
        let defaults = UserDefaults.standard
        defaults.set(Self.hash(of: jws), forKey: Self.lastSyncedJwsHashKey)
        defaults.set(Date(), forKey: Self.lastSyncedAtKey)
        return state.entitled
    }

    /// Foreground-time sync, deduped: only when the entitlement JWS changed
    /// (purchase, renewal, revocation) or the last push is over a day old.
    func syncEntitlementToBackendIfNeeded() async {
        guard let jws = latestTransactionJws else {
            return
        }
        let defaults = UserDefaults.standard
        let lastHash = defaults.string(forKey: Self.lastSyncedJwsHashKey)
        let lastAt = defaults.object(forKey: Self.lastSyncedAtKey) as? Date
        let fresh = lastAt.map { Date().timeIntervalSince($0) < 24 * 60 * 60 } ?? false
        if lastHash == Self.hash(of: jws), fresh {
            return
        }
        await syncEntitlementToBackend()
    }

    private static func hash(of jws: String) -> String {
        SHA256.hash(data: Data(jws.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - The honest reminder

    /// Called when a purchase that includes the 3-day free trial succeeds.
    func recordTrialStarted(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: PurchaseConstants.trialStartedAtKey)
        Task {
            await syncTrialReminder()
        }
    }

    /// Places (or re-places) the trial-ending notification at
    /// trialStart + 44h. Safe to call any time — it is a no-op without a
    /// recorded trial, and re-scheduling replaces the pending request.
    /// Called again after notification permission is granted, since the
    /// paywall comes one screen before the permission ask.
    func syncTrialReminder() async {
        guard let startedAt = UserDefaults.standard.object(forKey: PurchaseConstants.trialStartedAtKey) as? Date else {
            return
        }
        guard isEntitled else {
            LocalNotificationScheduler().cancelTrialEndingReminder()
            return
        }
        let fireDate = startedAt.addingTimeInterval(PurchaseConstants.trialReminderDelay)
        guard fireDate > Date() else {
            return
        }
        try? await LocalNotificationScheduler().scheduleTrialEndingReminder(at: fireDate)
    }

    /// Foreground check: if the trial (or subscription) was cancelled in
    /// Settings, the reminder has nothing honest left to say — remove it.
    func reconcileOnForeground() async {
        await refreshEntitlement()
        if !isEntitled {
            LocalNotificationScheduler().cancelTrialEndingReminder()
        }
        await syncEntitlementToBackendIfNeeded()
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else {
            return
        }
        await transaction.finish()
        await refreshEntitlement()
        await syncTrialReminder()
        // Renewals, Ask-to-Buy approvals, and revocations land here — push
        // the fresh truth so server gates match what StoreKit just learned.
        await syncEntitlementToBackendIfNeeded()
    }
}
