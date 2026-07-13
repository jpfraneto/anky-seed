package inc.anky.android.core.subscription

import android.app.Activity

/**
 * SDK-free snapshot of the `pro` entitlement, derived from RevenueCat's
 * CustomerInfo. Everything the store publishes flows from one of these, which
 * keeps the store's truth-deriving logic pure and JVM-testable.
 */
data class EntitlementSnapshot(
    val isEntitled: Boolean = false,
    /** Product id normalized to the plain Play product id (no base-plan suffix). */
    val productId: String? = null,
    val store: SubscriptionStoreKind? = null,
    val periodType: SubscriptionPeriodKind? = null,
    /** When the entitlement lapses unless renewed. Null is valid — lifetime
     * and open-ended promotional grants stay entitled without one. */
    val expirationDateMillis: Long? = null,
) {
    /** True while the writer is inside the free trial (or a paid intro
     * period — the same honesty applies). */
    val isInIntroTrial: Boolean
        get() = isEntitled &&
            (periodType == SubscriptionPeriodKind.TRIAL || periodType == SubscriptionPeriodKind.INTRO)

    companion object {
        val NOT_ENTITLED = EntitlementSnapshot()
    }
}

/** Where the active entitlement came from. Promotional = granted, not bought. */
enum class SubscriptionStoreKind {
    PLAY_STORE,
    APP_STORE,
    PROMOTIONAL,
    OTHER,
}

/** Mirrors RevenueCat's PeriodType. TRIAL/INTRO gate the honest reminder. */
enum class SubscriptionPeriodKind {
    NORMAL,
    INTRO,
    TRIAL,
    PREPAID,
}

/**
 * A purchasable plan from the `default` offering, flattened so the paywall and
 * price formatter never touch the SDK types directly.
 */
data class SubscriptionPackage(
    /** Plain Play product id (`anky.yearly` / `anky.monthly`), base-plan suffix stripped. */
    val productId: String,
    val priceAmountMicros: Long?,
    val priceCurrencyCode: String?,
    /** The store-localized price string, untouched (e.g. "$88.00"). */
    val priceFormatted: String?,
    /** Play returns only offers the writer is eligible for — a present free
     * trial option means the trial timeline may be promised. */
    val hasFreeTrialOffer: Boolean = false,
    /** The underlying `com.revenuecat.purchases.Package`, kept opaque so
     * tests and previews stay JVM-pure. Null in fakes. */
    val raw: Any? = null,
)

/** Outcome of a purchase attempt. A cancel is silent; a failure gets one quiet line. */
sealed interface SubscriptionPurchaseOutcome {
    data class Completed(val snapshot: EntitlementSnapshot) : SubscriptionPurchaseOutcome
    data object Cancelled : SubscriptionPurchaseOutcome
    data object Failed : SubscriptionPurchaseOutcome
}

/**
 * The mirror-server half of subscription truth. Deliberately minimal — the
 * level workstream owns the real `LevelSyncClient`/`AnkyFunnel`; wiring adapts
 * them to this interface so this package never imports `core/level`.
 */
interface SubscriptionBackend {
    /**
     * `POST /subscription/identify` — tells the mirror which appUserID this
     * wallet is; the server answers from its webhook-maintained entitlement
     * state. Returns the server's `entitled`, or null when unreachable
     * (offline is fine — gates fail closed and the next foreground heals it).
     */
    suspend fun identify(appUserId: String): Boolean?

    /** One whitelisted funnel event (`lapsed`, `restored`, ...). Best-effort. */
    suspend fun funnel(event: String, origin: String? = null)
}

/** Funnel event names this package emits. The full registry lives with AnkyFunnel. */
object SubscriptionFunnelEvent {
    const val RESTORED = "restored"
    const val LAPSED = "lapsed"
}

/**
 * Everything [EntitlementStore] needs from the RevenueCat SDK, behind one
 * seam so the store's behavior is unit-testable. The production
 * implementation is [RevenueCatSubscriptionGateway].
 */
interface SubscriptionGateway {
    /** The appUserID the SDK is currently identified as, or null while unconfigured. */
    val identifiedAppUserId: String?

    /** Configure/identify (fail closed). Returns the active appUserID or null. */
    suspend fun ensureIdentified(): String?

    /**
     * Registers the single customer-info observer. Implementations must also
     * deliver the latest cached snapshot immediately when available (the
     * RevenueCat listener does this on set).
     */
    fun observeCustomerInfo(onSnapshot: (EntitlementSnapshot) -> Unit)

    /** Fresh (network) truth for foreground reconciles. Null when unreachable. */
    suspend fun fetchCurrentSnapshot(): EntitlementSnapshot?

    /** The `default` offering's packages. Throws when the store is unreachable. */
    suspend fun loadPackages(): List<SubscriptionPackage>

    /** Runs the purchase through RevenueCat, which finishes the transaction. */
    suspend fun purchase(pkg: SubscriptionPackage, activity: Activity?): SubscriptionPurchaseOutcome

    /** Restores and returns the refreshed snapshot. Throws on failure. */
    suspend fun restore(): EntitlementSnapshot

    /** Trial eligibility for the yearly plan's introductory offer. */
    suspend fun yearlyTrialEligibility(): Boolean
}
