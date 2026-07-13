package inc.anky.android.core.subscription

import android.content.Context
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.awaitLogIn
import inc.anky.android.BuildConfig
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The one configuration surface for everything purchases. RevenueCat is the
 * single transaction owner (it observes and finishes every Play Billing
 * transaction); the app never talks to Play Billing directly.
 *
 * These values must stay in sync with the RevenueCat dashboard (entitlement +
 * offering) and Play Console (production). The product ids intentionally match
 * iOS (`anky.yearly` / `anky.monthly`): Play Console must define subscriptions
 * with these exact ids so RevenueCat's cross-platform `pro` entitlement maps
 * one-to-one. On Android the yearly base plan carries the 3-day free trial as
 * an offer; Play Billing only returns trial offers the writer is eligible for.
 *
 * Ported from iOS `Anky/Purchases/AnkyPurchasesConfig.swift`.
 */
object AnkyPurchasesConfig {
    /** The single entitlement every gate checks — purchased or granted. */
    const val ENTITLEMENT_ID = "pro"

    /** The paywall's offering; its packages carry yearly and monthly. */
    const val OFFERING_ID = "default"

    const val YEARLY_PRODUCT_ID = "anky.yearly"
    const val MONTHLY_PRODUCT_ID = "anky.monthly"
    val ALL_PRODUCT_IDS: Set<String> = setOf(YEARLY_PRODUCT_ID, MONTHLY_PRODUCT_ID)

    /**
     * The honest reminder fires this long BEFORE the trial converts —
     * "your trial ends tomorrow", while there is still real time to cancel.
     * (28h before the end of a 72h trial ≈ the old 44h-in mark.)
     */
    const val TRIAL_REMINDER_LEAD_TIME_MILLIS: Long = 28L * 60L * 60L * 1000L
}

/**
 * Launch-time RevenueCat configuration. Called from the app root once identity
 * is loaded — never lazily from a feature path, so every surface sees the same
 * configured SDK from the first frame on.
 *
 * Pattern choice: `Purchases.configure` with the wallet address as appUserID
 * directly, NOT configure-anonymous-then-logIn. Identity is created
 * synchronously before this runs, so there is never a window where a purchase
 * could attach to an anonymous RevenueCat ID. If identity is unavailable we
 * fail closed: the SDK stays unconfigured, no purchase path opens, and the
 * next foreground retries.
 *
 * Ported from iOS `AnkyPurchases` in `AnkyPurchasesConfig.swift`. The API key
 * comes from `BuildConfig.REVENUECAT_ANDROID_PUBLIC_KEY` (a public key, safe
 * to ship in the binary).
 */
object AnkyPurchases {
    private val mutex = Mutex()

    /** The appUserID the SDK is configured under, or null while unconfigured. */
    @Volatile
    var configuredAccountId: String? = null
        private set

    /** True once the SDK is configured under a real writer identity. */
    val isConfigured: Boolean
        get() = configuredAccountId != null

    /**
     * Configures on first call, re-identifies via `logIn` if the wallet
     * changed (a backup import adopting another writer's identity). Returns
     * the active appUserID, or null when identity is unavailable (fail
     * closed — retry on next foreground).
     *
     * @param appUserId the writer's wallet address — never an anonymous id.
     */
    suspend fun identifyCurrentWriter(context: Context, appUserId: String?): String? =
        mutex.withLock {
            val apiKey = BuildConfig.REVENUECAT_ANDROID_PUBLIC_KEY.trim()
            if (apiKey.isBlank() || appUserId.isNullOrBlank()) {
                return@withLock null
            }

            val configured = configuredAccountId
            if (configured == null) {
                Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
                val outcome = runCatching {
                    if (!Purchases.isConfigured) {
                        Purchases.configure(
                            PurchasesConfiguration.Builder(context.applicationContext, apiKey)
                                .appUserID(appUserId)
                                .diagnosticsEnabled(false)
                                .automaticDeviceIdentifierCollectionEnabled(false)
                                .build(),
                        )
                    } else if (Purchases.sharedInstance.appUserID != appUserId) {
                        // Another surface (legacy credits client) configured
                        // first — adopt the shared instance under our writer.
                        Purchases.sharedInstance.awaitLogIn(appUserId)
                    }
                }
                if (outcome.isFailure) {
                    return@withLock null
                }
                configuredAccountId = appUserId
                return@withLock appUserId
            }

            if (configured == appUserId) {
                return@withLock appUserId
            }
            val logIn = runCatching { Purchases.sharedInstance.awaitLogIn(appUserId) }
            if (logIn.isFailure) {
                return@withLock configured
            }
            configuredAccountId = appUserId
            appUserId
        }
}
