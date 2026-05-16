package inc.anky.android.core.credits

import android.app.Activity
import android.content.Context
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Offerings
import com.revenuecat.purchases.Package as RevenueCatPackage
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitGetVirtualCurrencies
import com.revenuecat.purchases.awaitLogIn
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import inc.anky.android.BuildConfig

data class CreditPackage(
    val packageId: String,
    val productId: String,
    val title: String,
    val subtitle: String = "",
    val price: String,
)

data class CreditState(
    val isConfigured: Boolean,
    val balance: Int?,
    val message: String,
    val packages: List<CreditPackage> = emptyList(),
    val isLoading: Boolean = false,
)

interface CreditsClient {
    suspend fun configure(appUserId: String)
    suspend fun refresh(): CreditState
    suspend fun purchase(packageId: String, activity: Activity?): CreditState
}

class RevenueCatCreditsClient(
    context: Context,
) : CreditsClient {
    private val appContext = context.applicationContext
    private var configured = false
    private var configuredAppUserId: String? = null
    private var configureFailure: String? = null
    private val revenueCatPackages = mutableMapOf<String, RevenueCatPackage>()

    override suspend fun configure(appUserId: String) {
        val apiKey = BuildConfig.REVENUECAT_ANDROID_PUBLIC_KEY.trim()
        if (apiKey.isBlank() || appUserId.isBlank()) {
            configured = false
            configuredAppUserId = null
            configureFailure = null
            revenueCatPackages.clear()
            return
        }

        Purchases.logLevel = LogLevel.ERROR
        try {
            if (!Purchases.isConfigured) {
                Purchases.configure(
                    PurchasesConfiguration.Builder(appContext, apiKey)
                        .appUserID(appUserId)
                        .diagnosticsEnabled(false)
                        .automaticDeviceIdentifierCollectionEnabled(false)
                        .build(),
                )
            } else if (configuredAppUserId != appUserId && Purchases.sharedInstance.appUserID != appUserId) {
                Purchases.sharedInstance.awaitLogIn(appUserId)
            }
        } catch (error: Throwable) {
            configured = false
            configuredAppUserId = null
            configureFailure = "Could not load credits."
            revenueCatPackages.clear()
            return
        }
        configured = true
        configuredAppUserId = appUserId
        configureFailure = null
    }

    override suspend fun refresh(): CreditState {
        configureFailure?.let { return CreditState(isConfigured = false, balance = null, message = it) }
        if (!configured) return unconfiguredState()
        return runCatching {
            val purchases = Purchases.sharedInstance
            purchases.invalidateVirtualCurrenciesCache()
            val balance = purchases.awaitGetVirtualCurrencies()[CreditCatalog.CurrencyCode]?.balance
            val packages = loadCreditPackages(purchases)
            val message = when {
                balance == null && packages.isEmpty() -> "no credit packs available"
                balance == null -> "Could not load credits."
                packages.isEmpty() -> "no credit packs available"
                else -> "credits refreshed."
            }
            CreditState(
                isConfigured = true,
                balance = balance,
                message = message,
                packages = packages.map { it.toCreditPackage() },
            )
        }.getOrElse { error ->
            CreditState(
                isConfigured = true,
                balance = null,
                message = "Could not load credits.",
            )
        }
    }

    override suspend fun purchase(packageId: String, activity: Activity?): CreditState {
        if (!configured) return unconfiguredState()
        if (activity == null) {
            return CreditState(true, null, "Could not complete that credit purchase.")
        }
        val packageToPurchase = revenueCatPackages[packageId] ?: run {
            val refreshed = refresh()
            revenueCatPackages[packageId]
                ?: return refreshed.copy(message = "That credit package is not available.")
        }

        return runCatching {
            Purchases.sharedInstance.awaitPurchase(PurchaseParams.Builder(activity, packageToPurchase).build())
            Purchases.sharedInstance.invalidateVirtualCurrenciesCache()
            refresh().copy(message = "Credits updated.")
        }.getOrElse { error ->
            refresh().copy(message = CreditCatalog.purchaseFailureMessage(error))
        }
    }

    private suspend fun loadCreditPackages(purchases: Purchases): List<RevenueCatPackage> {
        val offering = CreditCatalog.selectOffering(purchases.awaitOfferings())
            ?: return emptyList<RevenueCatPackage>().also { revenueCatPackages.clear() }
        val packages = offering.availablePackages.sortedWith(compareBy({ CreditCatalog.productRank(it.product.id) }, { it.product.id }))
        revenueCatPackages.clear()
        packages.forEach { packageToCache ->
            revenueCatPackages[packageToCache.identifier] = packageToCache
            revenueCatPackages[packageToCache.product.id] = packageToCache
        }
        return packages
    }

    private fun RevenueCatPackage.toCreditPackage(): CreditPackage {
        val productId = product.id
        return CreditPackage(
            packageId = productId,
            productId = productId,
            title = CreditCatalog.titleForProduct(productId) ?: product.title.ifBlank { product.name.ifBlank { identifier } },
            subtitle = product.title,
            price = product.price.formatted,
        )
    }

    private fun unconfiguredState(): CreditState =
        CreditState(
            isConfigured = false,
            balance = null,
            message = "no credit packs available",
        )
}

internal object CreditCatalog {
    const val CurrencyCode = "CRD"
    const val OfferingIdentifier = "credits DEV"
    val ProductOrder = listOf(
        "inc.dev.anky.credits.22",
        "inc.dev.anky.credits.88_bonus_11",
        "inc.dev.anky.credits.333_bonus_88",
    )
    private val productTitles = mapOf(
        "inc.dev.anky.credits.22" to "22 credits",
        "inc.dev.anky.credits.88_bonus_11" to "99 credits",
        "inc.dev.anky.credits.333_bonus_88" to "421 credits",
    )

    fun productRank(productId: String): Int {
        val index = ProductOrder.indexOf(productId)
        return if (index >= 0) index else Int.MAX_VALUE
    }

    fun titleForProduct(productId: String): String? = productTitles[productId]

    fun selectOffering(offerings: Offerings): Offering? =
        offerings[OfferingIdentifier] ?: offerings.current

    fun purchaseFailureMessage(error: Throwable): String =
        if (error is PurchasesTransactionException && error.userCancelled) {
            "Credits updated."
        } else {
            "Could not complete that credit purchase."
        }
}
