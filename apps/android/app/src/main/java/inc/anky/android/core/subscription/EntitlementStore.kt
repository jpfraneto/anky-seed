package inc.anky.android.core.subscription

import android.app.Activity
import android.content.SharedPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Everything the UI needs from entitlement truth, published as one immutable
 * state. Mirrors the iOS `EntitlementStore` @Published surface.
 */
data class EntitlementState(
    val isEntitled: Boolean = false,
    val activeProductId: String? = null,
    /** Where the active entitlement came from. Null while not entitled. */
    val activeStore: SubscriptionStoreKind? = null,
    /** TRIAL / INTRO while inside an introductory period. */
    val activePeriodType: SubscriptionPeriodKind? = null,
    /** When the entitlement lapses unless renewed. Null is valid — lifetime
     * and open-ended promotional grants stay entitled without one. */
    val activeExpirationDateMillis: Long? = null,
    /** A granted entitlement: complimentary access, never a store charge. */
    val isPromotionalEntitlement: Boolean = false,
    val packages: List<SubscriptionPackage> = emptyList(),
    val isPurchasing: Boolean = false,
    val isRestoring: Boolean = false,
    val isLoadingPackages: Boolean = false,
    /** One quiet line for the paywall when a purchase genuinely failed
     * (never set for a cancel). Cleared on the next attempt. */
    val purchaseErrorLine: String? = null,
    /** Set when the store's offerings can't be reached (offline, Play down,
     * SDK unconfigured) — the paywall shows it with a retry link. Cleared
     * the moment a load succeeds. */
    val offeringsErrorLine: String? = null,
    /** Restore outcome, always set when a restore finishes: restored,
     * nothing found, or failed. Never silent. */
    val restoreStatusLine: String? = null,
) {
    val isInIntroTrial: Boolean
        get() = isEntitled &&
            (activePeriodType == SubscriptionPeriodKind.TRIAL || activePeriodType == SubscriptionPeriodKind.INTRO)

    val yearlyPackage: SubscriptionPackage?
        get() = packages.firstOrNull { it.productId == AnkyPurchasesConfig.YEARLY_PRODUCT_ID }

    val monthlyPackage: SubscriptionPackage?
        get() = packages.firstOrNull { it.productId == AnkyPurchasesConfig.MONTHLY_PRODUCT_ID }

    val activePackage: SubscriptionPackage?
        get() = activeProductId?.let { active -> packages.firstOrNull { it.productId == active } }
}

/**
 * The single source of truth for whether the practice is paid for. Watches
 * RevenueCat customer-info updates (via [SubscriptionGateway]) and derives
 * everything from the `pro` entitlement — purchased on any store, granted
 * promotionally, or in trial. RevenueCat owns the Play Billing transaction
 * queue end to end; nothing else in the app observes or finishes purchases.
 *
 * Ported from iOS `Anky/Purchases/EntitlementStore.swift`.
 */
class EntitlementStore(
    private val gateway: SubscriptionGateway,
    private val backend: SubscriptionBackend,
    private val preferences: SharedPreferences,
    private val scope: CoroutineScope,
    private val trialReminder: TrialReminderSync? = null,
    private val ignoresEntitlementForQA: Boolean = IGNORES_ENTITLEMENT_FOR_QA,
) {
    private val mutableState = MutableStateFlow(EntitlementState())
    val state: StateFlow<EntitlementState> = mutableState.asStateFlow()

    private var started = false
    private var hasIdentifiedToBackendThisLaunch = false

    /**
     * What gates should consult — `isEntitled` filtered through the QA
     * override, so a forced paywall run behaves exactly like a lapsed one.
     */
    val isEntitledForGating: Boolean
        get() = if (ignoresEntitlementForQA) false else state.value.isEntitled

    /**
     * Begins watching entitlement truth. Called from the app root right after
     * [AnkyPurchases.identifyCurrentWriter] configures the SDK — never
     * before, and harmless to call again after an identity change.
     */
    fun start() {
        if (gateway.identifiedAppUserId == null || started) {
            return
        }
        started = true
        gateway.observeCustomerInfo { snapshot ->
            scope.launch { applyCustomerInfo(snapshot) }
        }
        scope.launch { loadPackages() }
    }

    /**
     * Retries RevenueCat configuration when the launch-time identify failed
     * (identity unavailable in that moment) — purchase, restore, and redeem
     * must never be silent no-ops because of a missed launch window.
     * Returns false only when identity is still unavailable.
     */
    suspend fun ensureConfigured(): Boolean {
        if (gateway.identifiedAppUserId == null) {
            gateway.ensureIdentified() ?: return false
        }
        start()
        return true
    }

    suspend fun loadPackages() {
        val current = state.value
        if (current.packages.isNotEmpty() || current.isLoadingPackages) {
            return
        }
        if (!ensureConfigured()) {
            mutableState.update { it.copy(offeringsErrorLine = STORE_UNREACHABLE_LINE) }
            return
        }
        mutableState.update { it.copy(isLoadingPackages = true) }
        try {
            val packages = runCatching { gateway.loadPackages() }.getOrElse { emptyList() }
            mutableState.update {
                it.copy(
                    packages = packages,
                    offeringsErrorLine = if (packages.isEmpty()) STORE_UNREACHABLE_LINE else null,
                )
            }
        } finally {
            mutableState.update { it.copy(isLoadingPackages = false) }
        }
    }

    /**
     * Trial eligibility for the yearly plan's introductory offer. Play
     * Billing only returns offers the writer can use, so unknown (store not
     * answering yet) reads as eligible — the timeline promises nothing that
     * Google won't honor at the purchase sheet.
     */
    suspend fun yearlyTrialEligibility(): Boolean {
        if (gateway.identifiedAppUserId == null) {
            return false
        }
        return runCatching { gateway.yearlyTrialEligibility() }.getOrDefault(true)
    }

    /**
     * Runs the purchase through RevenueCat, which finishes the transaction
     * and refreshes entitlement truth. Returns true only when the writer is
     * entitled when it finishes. A cancel is silent; a real failure sets one
     * gentle line for the paywall.
     *
     * Race-safe pay → confirm → generate: the backend identify is awaited
     * BEFORE this returns, so the server knows before any gated work
     * (painting generation) is attempted. Offline there is fine — gates fail
     * closed and the next foreground identify heals it.
     */
    suspend fun purchase(pkg: SubscriptionPackage, activity: Activity?): Boolean {
        if (state.value.isPurchasing) {
            return false
        }
        mutableState.update { it.copy(purchaseErrorLine = null) }
        if (!ensureConfigured()) {
            mutableState.update { it.copy(purchaseErrorLine = STORE_UNREACHABLE_LINE) }
            return false
        }
        mutableState.update { it.copy(isPurchasing = true) }
        try {
            return when (val outcome = runCatching { gateway.purchase(pkg, activity) }
                .getOrDefault(SubscriptionPurchaseOutcome.Failed)) {
                is SubscriptionPurchaseOutcome.Cancelled -> false
                is SubscriptionPurchaseOutcome.Failed -> {
                    mutableState.update { it.copy(purchaseErrorLine = PURCHASE_FAILED_LINE) }
                    false
                }
                is SubscriptionPurchaseOutcome.Completed -> {
                    applyCustomerInfo(outcome.snapshot)
                    identifyToBackend()
                    state.value.isEntitled
                }
            }
        } finally {
            mutableState.update { it.copy(isPurchasing = false) }
        }
    }

    /**
     * Always reports how it went — restored, nothing to restore, or failed —
     * via `restoreStatusLine`.
     */
    suspend fun restore() {
        if (state.value.isRestoring) {
            return
        }
        mutableState.update { it.copy(restoreStatusLine = null) }
        if (!ensureConfigured()) {
            mutableState.update { it.copy(restoreStatusLine = STORE_UNREACHABLE_LINE) }
            return
        }
        mutableState.update { it.copy(isRestoring = true) }
        try {
            val snapshot = gateway.restore()
            applyCustomerInfo(snapshot)
            if (state.value.isEntitled) {
                mutableState.update { it.copy(restoreStatusLine = RESTORE_SUCCESS_LINE) }
                reportFunnel(SubscriptionFunnelEvent.RESTORED)
                identifyToBackend()
            } else {
                mutableState.update { it.copy(restoreStatusLine = RESTORE_NOTHING_LINE) }
            }
        } catch (error: Throwable) {
            mutableState.update { it.copy(restoreStatusLine = RESTORE_FAILED_LINE) }
        } finally {
            mutableState.update { it.copy(isRestoring = false) }
        }
    }

    /**
     * The paywall's guard for the rare offering that loads without the
     * selected plan — never a silent tap.
     */
    fun noteSelectedPackageUnavailable() {
        mutableState.update { it.copy(purchaseErrorLine = PACKAGE_UNAVAILABLE_LINE) }
    }

    /** For surfaces that need the SDK but found it unreachable. */
    fun noteStoreUnreachable() {
        mutableState.update { it.copy(purchaseErrorLine = STORE_UNREACHABLE_LINE) }
    }

    /**
     * Foreground reconcile: fetch fresh truth (renewal, cancellation, a
     * promotional grant landing) and re-tell the backend when entitled. Also
     * heals the trial reminder — a trial cancelled in Play settings loses its
     * entitlement here, and [applyCustomerInfo] cancels the reminder.
     */
    suspend fun reconcileOnForeground() {
        if (gateway.identifiedAppUserId == null) {
            return
        }
        gateway.fetchCurrentSnapshot()?.let { applyCustomerInfo(it) }
        identifyToBackendIfNeeded()
    }

    // region Server truth

    /**
     * Tells the mirror which appUserID this wallet is. The server answers
     * from its webhook-maintained entitlement state. Null when unreachable.
     */
    suspend fun identifyToBackend(): Boolean? {
        val appUserId = gateway.identifiedAppUserId
            ?: gateway.ensureIdentified()
            ?: return null
        val entitled = runCatching { backend.identify(appUserId) }.getOrNull() ?: return null
        hasIdentifiedToBackendThisLaunch = true
        return entitled
    }

    /**
     * Launch/foreground-time identify, deduped to once per launch while
     * entitled — purchases and restores always push explicitly.
     */
    suspend fun identifyToBackendIfNeeded() {
        if (!state.value.isEntitled || hasIdentifiedToBackendThisLaunch) {
            return
        }
        identifyToBackend()
    }

    // endregion

    // region Entitlement truth

    /**
     * Applies one customer-info snapshot: publishes the derived state, fires
     * the `lapsed` funnel event exactly once per narrowing, persists the
     * last-known gate answer, and re-syncs the honest trial reminder.
     */
    internal suspend fun applyCustomerInfo(snapshot: EntitlementSnapshot) {
        val entitled = snapshot.isEntitled
        mutableState.update {
            it.copy(
                isEntitled = entitled,
                activeProductId = if (entitled) snapshot.productId else null,
                activeExpirationDateMillis = if (entitled) snapshot.expirationDateMillis else null,
                activeStore = if (entitled) snapshot.store else null,
                isPromotionalEntitlement = entitled && snapshot.store == SubscriptionStoreKind.PROMOTIONAL,
                activePeriodType = if (entitled) snapshot.periodType else null,
            )
        }
        noteEntitlementTransition(entitled)
        trialReminder?.sync(snapshot)
    }

    /**
     * Fires the `lapsed` funnel event exactly once per narrowing — the moment
     * a previously entitled writer's subscription ends locally — and keeps
     * the persisted presentation-level snapshot fresh.
     */
    private fun noteEntitlementTransition(entitled: Boolean) {
        val wasEntitled = preferences.getBoolean(WAS_ENTITLED_KEY, false)
        if (wasEntitled && !entitled) {
            reportFunnel(SubscriptionFunnelEvent.LAPSED)
        }
        preferences.edit().putBoolean(WAS_ENTITLED_KEY, entitled).apply()
    }

    private fun reportFunnel(event: String) {
        scope.launch {
            runCatching { backend.funnel(event) }
        }
    }

    // endregion

    companion object {
        /**
         * QA override: treats the writer as NOT entitled everywhere gating
         * decisions are made, so the paywall shows even after a test purchase
         * (purchases persist across onboarding re-runs). MUST be false in
         * every shipped build.
         */
        const val IGNORES_ENTITLEMENT_FOR_QA = false

        /** Same key as iOS UserDefaults — the persisted gate snapshot. */
        const val WAS_ENTITLED_KEY = "anky.subscription.wasEntitled"

        /**
         * Presentation-level snapshot for surfaces outside the app root's
         * object graph (widget sync, sealed-session nudges). Written on every
         * entitlement refresh; respects the QA override like every other gate.
         */
        fun lastKnownEntitledForGating(
            preferences: SharedPreferences,
            ignoresEntitlementForQA: Boolean = IGNORES_ENTITLEMENT_FOR_QA,
        ): Boolean =
            if (ignoresEntitlementForQA) false else preferences.getBoolean(WAS_ENTITLED_KEY, false)

        const val STORE_UNREACHABLE_LINE =
            "Google Play can't be reached right now. Check your connection and try again."
        const val PURCHASE_FAILED_LINE =
            "Google Play couldn't finish that. Nothing was charged — the door is still here when you're ready."
        const val PACKAGE_UNAVAILABLE_LINE =
            "That plan isn't available right now. Try the other one, or come back in a moment."
        const val RESTORE_SUCCESS_LINE = "Restored. Your practice is active."
        const val RESTORE_NOTHING_LINE = "No purchases to restore on this Google account."
        const val RESTORE_FAILED_LINE = "Restore didn't finish. Check your connection and try again."
    }
}
