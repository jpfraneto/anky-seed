package inc.anky.android.core.credits

import android.app.Activity
import android.content.Context
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Offerings
import com.revenuecat.purchases.Package as RevenueCatPackage
import com.revenuecat.purchases.ProductType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.PurchasesException
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitGetProducts
import com.revenuecat.purchases.awaitGetVirtualCurrencies
import com.revenuecat.purchases.awaitLogIn
import com.revenuecat.purchases.awaitLogOut
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.interfaces.ReceiveCustomerInfoCallback
import com.revenuecat.purchases.models.StoreProduct
import inc.anky.android.BuildConfig
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

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
    suspend fun restorePurchases(): CreditState
    suspend fun invalidateCreditBalanceCache()
    suspend fun logOutIfConfigured()
}

class RevenueCatCreditsClient(
    context: Context,
) : CreditsClient {
    private val appContext = context.applicationContext
    private var configured = false
    private var configuredAppUserId: String? = null
    private var configureFailure: String? = null
    private val revenueCatPackages = mutableMapOf<String, RevenueCatPackage>()
    private val revenueCatProducts = mutableMapOf<String, StoreProduct>()

    override suspend fun configure(appUserId: String) {
        val apiKey = BuildConfig.REVENUECAT_ANDROID_PUBLIC_KEY.trim()
        if (apiKey.isBlank() || appUserId.isBlank()) {
            configured = false
            configuredAppUserId = null
            configureFailure = null
            revenueCatPackages.clear()
            revenueCatProducts.clear()
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
            revenueCatProducts.clear()
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
            val products = loadCreditProducts(purchases)
            val message = when {
                balance == null && products.isEmpty() -> "no credit packs available"
                balance == null -> "Could not load credits."
                products.isEmpty() -> "no credit packs available"
                else -> "credits refreshed."
            }
            CreditState(
                isConfigured = true,
                balance = balance,
                message = message,
                packages = products.map { it.toCreditPackage() },
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
        }
        val productToPurchase = revenueCatProducts[packageId] ?: revenueCatProducts[packageToPurchase?.product?.id]

        if (packageToPurchase == null && productToPurchase == null) {
            return refresh().copy(message = "That credit package is not available.")
        }

        return runCatching {
            val params = if (packageToPurchase != null) {
                PurchaseParams.Builder(activity, packageToPurchase).build()
            } else {
                PurchaseParams.Builder(activity, checkNotNull(productToPurchase)).build()
            }
            Purchases.sharedInstance.awaitPurchase(params)
            Purchases.sharedInstance.invalidateVirtualCurrenciesCache()
            refresh().copy(message = "Credits updated.")
        }.getOrElse { error ->
            refresh().copy(message = CreditCatalog.purchaseFailureMessage(error))
        }
    }

    override suspend fun restorePurchases(): CreditState {
        if (!configured) return unconfiguredState()
        return runCatching {
            val purchases = Purchases.sharedInstance
            purchases.awaitRestorePurchases()
            purchases.invalidateVirtualCurrenciesCache()
            refresh().copy(message = CreditCatalog.RestoreSuccessMessage)
        }.getOrElse {
            refresh().copy(message = CreditCatalog.RestoreFailureMessage)
        }
    }

    override suspend fun invalidateCreditBalanceCache() {
        if (configured) {
            runCatching { Purchases.sharedInstance.invalidateVirtualCurrenciesCache() }
        }
    }

    override suspend fun logOutIfConfigured() {
        if (!configured || !Purchases.isConfigured) return
        runCatching { Purchases.sharedInstance.awaitLogOut() }
        configured = false
        configuredAppUserId = null
        configureFailure = null
        revenueCatPackages.clear()
        revenueCatProducts.clear()
    }

    private suspend fun loadCreditProducts(purchases: Purchases): List<StoreProduct> {
        val offering = CreditCatalog.selectOffering(purchases.awaitOfferings())
        val packages = offering?.availablePackages.orEmpty()
        val packageProducts = packages.map { it.product }
        val packagedProductIds = packageProducts.map { it.id }.toSet()
        val missingProductIds = CreditCatalog.ProductOrder.filter { it !in packagedProductIds }
        val directProducts = if (missingProductIds.isEmpty()) {
            emptyList()
        } else {
            purchases.awaitGetProducts(missingProductIds, ProductType.INAPP)
        }
        val products = (packageProducts + directProducts)
            .distinctBy { it.id }
            .sortedWith(compareBy({ CreditCatalog.productRank(it.id) }, { it.id }))
        revenueCatPackages.clear()
        packages.forEach { packageToCache ->
            revenueCatPackages[packageToCache.identifier] = packageToCache
            revenueCatPackages[packageToCache.product.id] = packageToCache
        }
        revenueCatProducts.clear()
        products.forEach { product ->
            revenueCatProducts[product.id] = product
        }
        return products
    }

    private fun StoreProduct.toCreditPackage(): CreditPackage {
        val productId = id
        return CreditPackage(
            packageId = productId,
            productId = productId,
            title = CreditCatalog.titleForProduct(productId) ?: title.ifBlank { name.ifBlank { productId } },
            subtitle = CreditCatalog.subtitleForProduct(productId) ?: title,
            price = price.formatted,
        )
    }

    private fun unconfiguredState(): CreditState =
        CreditState(
            isConfigured = false,
            balance = null,
            message = "no credit packs available",
        )

    private suspend fun Purchases.awaitRestorePurchases(): Unit =
        suspendCancellableCoroutine { continuation ->
            restorePurchases(
                object : ReceiveCustomerInfoCallback {
                    override fun onReceived(customerInfo: CustomerInfo) {
                        if (continuation.isActive) continuation.resume(Unit)
                    }

                    override fun onError(error: PurchasesError) {
                        if (continuation.isActive) continuation.resumeWithException(PurchasesException(error))
                    }
                },
            )
        }
}

internal object CreditCatalog {
    const val CurrencyCode = "CRD"
    const val OfferingIdentifier = "Credits"
    const val RestoreSuccessMessage = "Purchases restored for this Anky identity."
    const val RestoreFailureMessage = "Could not restore purchases for this Anky identity."
    const val RestoreIdentityNote = "Restores purchases linked to this Anky address. Spent credits may not reappear if this is not the same Anky identity used to buy them."
    val ProductOrder = listOf(
        "inc.anky.credits.3",
        "inc.anky.credits.11",
        "inc.anky.credits.33",
    )
    private val productTitles = mapOf(
        "inc.anky.credits.3" to "3 reflections",
        "inc.anky.credits.11" to "11 reflections",
        "inc.anky.credits.33" to "33 reflections",
    )
    private val productSubtitles = mapOf(
        "inc.anky.credits.3" to "Starter pack",
        "inc.anky.credits.11" to "Stay with it",
        "inc.anky.credits.33" to "Daily practice",
    )

    fun productRank(productId: String): Int {
        val index = ProductOrder.indexOf(productId)
        return if (index >= 0) index else Int.MAX_VALUE
    }

    fun titleForProduct(productId: String): String? = productTitles[productId]

    fun subtitleForProduct(productId: String): String? = productSubtitles[productId]

    fun selectOffering(offerings: Offerings): Offering? =
        offerings[OfferingIdentifier] ?: offerings.current

    fun purchaseFailureMessage(error: Throwable): String =
        if (error is PurchasesTransactionException && error.userCancelled) {
            "Credits updated."
        } else {
            "Could not complete that credit purchase."
        }
}
