import Foundation
import RevenueCat

/// The single source of truth for whether the practice is paid for.
/// Watches RevenueCat's `customerInfoStream` and derives everything from
/// the `pro` entitlement — purchased on any store, granted promotionally,
/// or in trial. RevenueCat owns the StoreKit transaction queue end to end;
/// nothing else in the app observes or finishes transactions.
///
/// Local testing: select Anky.storekit in the scheme (Product → Scheme →
/// Edit Scheme… → Run → Options → StoreKit Configuration). Purchases then
/// go through the local config and validate with RevenueCat as sandbox
/// data — no App Store Connect needed. To reset test purchases: Xcode
/// menu Debug → StoreKit → Manage Transactions…, delete them there.
@MainActor
final class EntitlementStore: ObservableObject {
    /// QA override: treats the writer as NOT entitled everywhere gating
    /// decisions are made, so the paywall shows even after a test
    /// purchase (purchases persist across onboarding re-runs). MUST be
    /// set back to false before shipping a build.
    nonisolated static let ignoresEntitlementForQA = false

    @Published private(set) var isEntitled = false
    @Published private(set) var packages: [Package] = []
    @Published private(set) var isPurchasing = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var activeRenewalDate: Date?

    /// Where the active entitlement came from — `.appStore`, `.promotional`
    /// (granted, not bought), etc. Nil while not entitled.
    @Published private(set) var activeStore: Store?
    /// A granted entitlement: complimentary access, never a store charge.
    @Published private(set) var isPromotionalEntitlement = false
    /// `.trial` / `.intro` while inside an introductory period.
    @Published private(set) var activePeriodType: PeriodType?
    /// When the entitlement lapses unless renewed. Nil is valid — lifetime
    /// and open-ended promotional grants stay entitled without one.
    @Published private(set) var activeExpirationDate: Date?

    /// One quiet line for the paywall when a purchase genuinely failed
    /// (never set for a cancel). Cleared on the next attempt.
    @Published private(set) var purchaseErrorLine: String?

    /// Set when the store's offerings can't be reached (offline, App Store
    /// down, SDK unconfigured) — the paywall shows it with a retry link.
    /// Cleared the moment a load succeeds.
    @Published private(set) var offeringsErrorLine: String?
    @Published private(set) var isLoadingPackages = false

    /// Restore outcome, always set when a restore finishes: restored,
    /// nothing found, or failed. Never silent.
    @Published private(set) var restoreStatusLine: String?
    @Published private(set) var isRestoring = false

    private static let storeUnreachableLine =
        "The App Store can't be reached right now. Check your connection and try again."

    private var customerInfoTask: Task<Void, Never>?
    private var hasIdentifiedToBackendThisLaunch = false

    private nonisolated static let wasEntitledKey = "anky.subscription.wasEntitled"

    deinit {
        customerInfoTask?.cancel()
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

    /// True while the writer is inside the free trial (or a paid intro
    /// period — the same honesty applies).
    var isInIntroTrial: Bool {
        isEntitled && (activePeriodType == .trial || activePeriodType == .intro)
    }

    var yearlyPackage: Package? {
        packages.first { $0.storeProduct.productIdentifier == AnkyPurchasesConfig.yearlyProductID }
    }

    var monthlyPackage: Package? {
        packages.first { $0.storeProduct.productIdentifier == AnkyPurchasesConfig.monthlyProductID }
    }

    var activePackage: Package? {
        guard let activeProductID else {
            return nil
        }
        return packages.first { $0.storeProduct.productIdentifier == activeProductID }
    }

    /// Begins watching entitlement truth. Called from AppRoot right after
    /// `AnkyPurchases.identifyCurrentWriter()` configures the SDK — never
    /// before, and harmless to call again after an identity change.
    func start() {
        guard AnkyPurchases.isConfigured, customerInfoTask == nil else {
            return
        }
        customerInfoTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
        Task {
            await loadPackages()
        }
    }

    func loadPackages() async {
        guard packages.isEmpty, !isLoadingPackages else {
            return
        }
        guard await ensureConfigured() else {
            offeringsErrorLine = Self.storeUnreachableLine
            return
        }
        isLoadingPackages = true
        defer { isLoadingPackages = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.offering(identifier: AnkyPurchasesConfig.offeringID) ?? offerings.current
            packages = offering?.availablePackages ?? []
            offeringsErrorLine = packages.isEmpty ? Self.storeUnreachableLine : nil
        } catch {
            offeringsErrorLine = Self.storeUnreachableLine
        }
    }

    /// Retries RevenueCat configuration when the launch-time identify
    /// failed (identity unavailable in that moment) — purchase, restore,
    /// and redeem must never be silent no-ops because of a missed launch
    /// window. Returns false only when identity is still unavailable.
    func ensureConfigured() async -> Bool {
        if !AnkyPurchases.isConfigured {
            guard await AnkyPurchases.identifyCurrentWriter() != nil else {
                return false
            }
        }
        start()
        return true
    }

    /// Trial eligibility for the yearly plan's introductory offer, asked
    /// of the store through RevenueCat.
    func yearlyTrialEligibility() async -> Bool {
        guard AnkyPurchases.isConfigured else {
            return false
        }
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: [AnkyPurchasesConfig.yearlyProductID]
        )
        switch eligibility[AnkyPurchasesConfig.yearlyProductID]?.status {
        case .eligible, .unknown, .none:
            // Unknown (no ASC data yet, fresh sandbox) reads as eligible —
            // the timeline promises nothing that Apple won't honor at the
            // confirmation sheet.
            return true
        case .ineligible, .noIntroOfferExists:
            return false
        @unknown default:
            return true
        }
    }

    /// Runs the purchase through RevenueCat, which finishes the
    /// transaction and refreshes entitlement truth. Returns true only when
    /// the writer is entitled when it finishes. A cancel is silent; a real
    /// failure sets one gentle line for the paywall.
    @discardableResult
    func purchase(_ package: Package) async -> Bool {
        guard !isPurchasing else {
            return false
        }
        purchaseErrorLine = nil
        guard await ensureConfigured() else {
            purchaseErrorLine = Self.storeUnreachableLine
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                return false
            }
            apply(result.customerInfo)
            // Race-safe pay → confirm → generate: the server must know
            // before any gated work (painting generation) is attempted.
            // Offline here is fine — gates fail closed and the next
            // foreground identify heals it.
            await identifyToBackend()
            return isEntitled
        } catch {
            if (error as? RevenueCat.ErrorCode) == .purchaseCancelledError {
                return false
            }
            purchaseErrorLine = "The App Store couldn't finish that. Nothing was charged — the door is still here when you're ready."
            return false
        }
    }

    /// Always reports how it went — restored, nothing to restore, or
    /// failed — via `restoreStatusLine`.
    func restore() async {
        guard !isRestoring else {
            return
        }
        restoreStatusLine = nil
        guard await ensureConfigured() else {
            restoreStatusLine = Self.storeUnreachableLine
            return
        }
        isRestoring = true
        defer { isRestoring = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            if isEntitled {
                restoreStatusLine = "Restored. Your practice is active."
                AnkyFunnel.report(AnkyFunnel.restored)
                await identifyToBackend()
            } else {
                restoreStatusLine = "No purchases to restore on this Apple ID."
            }
        } catch {
            restoreStatusLine = "Restore didn't finish. Check your connection and try again."
        }
    }

    /// The paywall's guard for the rare offering that loads without the
    /// selected plan — never a silent tap.
    func noteSelectedPackageUnavailable() {
        purchaseErrorLine = "That plan isn't available right now. Try the other one, or come back in a moment."
    }

    /// For surfaces (redeem) that need the SDK but found it unreachable.
    func noteStoreUnreachable() {
        purchaseErrorLine = Self.storeUnreachableLine
    }

    /// Foreground reconcile: fetch fresh truth (renewal, cancellation, a
    /// promotional grant landing) and re-tell the backend when entitled.
    func reconcileOnForeground() async {
        guard AnkyPurchases.isConfigured else {
            return
        }
        if let info = try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent) {
            apply(info)
        }
        await identifyToBackendIfNeeded()
    }

    // MARK: - Server truth

    /// Tells the mirror which appUserID this wallet is — the signed
    /// EIP-712 headers prove the wallet, the body carries nothing the
    /// server doesn't already know. The server answers from its
    /// webhook-maintained entitlement state. Nil when unreachable.
    @discardableResult
    func identifyToBackend() async -> Bool? {
        guard let identity = try? WriterIdentityStore().loadOrCreate() else {
            return nil
        }
        guard let state = try? await LevelSyncClient().identifySubscription(identity: identity) else {
            return nil
        }
        hasIdentifiedToBackendThisLaunch = true
        return state.entitled
    }

    /// Launch/foreground-time identify, deduped to once per launch while
    /// entitled — purchases and restores always push explicitly.
    func identifyToBackendIfNeeded() async {
        guard isEntitled, !hasIdentifiedToBackendThisLaunch else {
            return
        }
        await identifyToBackend()
    }

    // MARK: - Entitlement truth

    private func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements[AnkyPurchasesConfig.entitlementID]
        let entitled = entitlement?.isActive == true

        activeProductID = entitled ? entitlement?.productIdentifier : nil
        activeExpirationDate = entitled ? entitlement?.expirationDate : nil
        activeRenewalDate = activeExpirationDate
        activeStore = entitled ? entitlement?.store : nil
        isPromotionalEntitlement = entitled && entitlement?.store == .promotional
        activePeriodType = entitled ? entitlement?.periodType : nil

        noteEntitlementTransition(entitled: entitled)
        isEntitled = entitled

        Task {
            await syncTrialReminder()
        }
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

    // MARK: - The honest reminder

    /// Places the trial-ending notification 28 hours before the trial
    /// converts, from the entitlement's own expiration date — no local
    /// timestamp heuristics. Re-run on every customerInfo change: a
    /// cancelled or converted trial removes the reminder, a fresher end
    /// date moves it. Called again after notification permission is
    /// granted, since the paywall comes one screen before the ask.
    func syncTrialReminder() async {
        guard isInIntroTrial, let endDate = activeExpirationDate else {
            LocalNotificationScheduler().cancelTrialEndingReminder()
            return
        }
        let fireDate = endDate.addingTimeInterval(-AnkyPurchasesConfig.trialReminderLeadTime)
        guard fireDate > Date() else {
            return
        }
        try? await LocalNotificationScheduler().scheduleTrialEndingReminder(at: fireDate)
    }
}
