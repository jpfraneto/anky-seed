package inc.anky.android.core.subscription

import android.app.Activity
import android.content.Context
import com.revenuecat.purchases.CacheFetchPolicy
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.PeriodType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.Store
import com.revenuecat.purchases.Package as RevenueCatPackage
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener

/**
 * The production [SubscriptionGateway]: a thin, logic-free mapping between
 * the RevenueCat Android SDK and this package's SDK-free models. All behavior
 * (error lines, gating, funnel, persistence) lives in [EntitlementStore] so
 * it can be tested without the SDK.
 *
 * @param appUserIdProvider supplies the writer's wallet address (from
 * WriterIdentityStore at the wiring layer) — never an anonymous id.
 */
class RevenueCatSubscriptionGateway(
    context: Context,
    private val appUserIdProvider: suspend () -> String?,
) : SubscriptionGateway {
    private val appContext = context.applicationContext

    override val identifiedAppUserId: String?
        get() = AnkyPurchases.configuredAccountId

    override suspend fun ensureIdentified(): String? =
        AnkyPurchases.identifyCurrentWriter(appContext, appUserIdProvider())

    override fun observeCustomerInfo(onSnapshot: (EntitlementSnapshot) -> Unit) {
        if (!Purchases.isConfigured) {
            return
        }
        // Setting the listener also delivers the latest cached CustomerInfo
        // immediately — the analogue of iOS customerInfoStream's first value.
        Purchases.sharedInstance.updatedCustomerInfoListener =
            UpdatedCustomerInfoListener { info -> onSnapshot(info.toSnapshot()) }
    }

    override suspend fun fetchCurrentSnapshot(): EntitlementSnapshot? =
        runCatching {
            Purchases.sharedInstance
                .awaitCustomerInfo(CacheFetchPolicy.FETCH_CURRENT)
                .toSnapshot()
        }.getOrNull()

    override suspend fun loadPackages(): List<SubscriptionPackage> {
        val offerings = Purchases.sharedInstance.awaitOfferings()
        val offering = offerings[AnkyPurchasesConfig.OFFERING_ID] ?: offerings.current
        return offering?.availablePackages.orEmpty().map { it.toSubscriptionPackage() }
    }

    override suspend fun purchase(
        pkg: SubscriptionPackage,
        activity: Activity?,
    ): SubscriptionPurchaseOutcome {
        val rcPackage = pkg.raw as? RevenueCatPackage ?: return SubscriptionPurchaseOutcome.Failed
        if (activity == null) {
            return SubscriptionPurchaseOutcome.Failed
        }
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(
                PurchaseParams.Builder(activity, rcPackage).build(),
            )
            SubscriptionPurchaseOutcome.Completed(result.customerInfo.toSnapshot())
        } catch (error: PurchasesTransactionException) {
            if (error.userCancelled) {
                SubscriptionPurchaseOutcome.Cancelled
            } else {
                SubscriptionPurchaseOutcome.Failed
            }
        }
    }

    override suspend fun restore(): EntitlementSnapshot =
        Purchases.sharedInstance.awaitRestore().toSnapshot()

    /**
     * Play Billing only returns subscription offers the writer is eligible
     * for, so a present free-trial option on the yearly product IS the
     * eligibility answer. Unknown (offerings unreachable) reads as eligible,
     * like iOS — the timeline promises nothing Google won't honor at the
     * purchase sheet.
     */
    override suspend fun yearlyTrialEligibility(): Boolean =
        runCatching {
            loadPackages()
                .firstOrNull { it.productId == AnkyPurchasesConfig.YEARLY_PRODUCT_ID }
                ?.hasFreeTrialOffer
                ?: true
        }.getOrDefault(true)

    private fun CustomerInfo.toSnapshot(): EntitlementSnapshot {
        val entitlement = entitlements[AnkyPurchasesConfig.ENTITLEMENT_ID]
        val entitled = entitlement?.isActive == true
        if (entitlement == null || !entitled) {
            return EntitlementSnapshot.NOT_ENTITLED
        }
        return EntitlementSnapshot(
            isEntitled = true,
            productId = entitlement.productIdentifier.substringBefore(':'),
            store = entitlement.store.toKind(),
            periodType = entitlement.periodType.toKind(),
            expirationDateMillis = entitlement.expirationDate?.time,
        )
    }

    private fun Store.toKind(): SubscriptionStoreKind = when (this) {
        Store.PLAY_STORE -> SubscriptionStoreKind.PLAY_STORE
        Store.APP_STORE, Store.MAC_APP_STORE -> SubscriptionStoreKind.APP_STORE
        Store.PROMOTIONAL -> SubscriptionStoreKind.PROMOTIONAL
        else -> SubscriptionStoreKind.OTHER
    }

    private fun PeriodType.toKind(): SubscriptionPeriodKind = when (this) {
        PeriodType.NORMAL -> SubscriptionPeriodKind.NORMAL
        PeriodType.INTRO -> SubscriptionPeriodKind.INTRO
        PeriodType.TRIAL -> SubscriptionPeriodKind.TRIAL
        PeriodType.PREPAID -> SubscriptionPeriodKind.PREPAID
    }

    private fun RevenueCatPackage.toSubscriptionPackage(): SubscriptionPackage =
        SubscriptionPackage(
            // RC Android subscription product ids carry a ":basePlanId"
            // suffix; gates and the paywall match on the plain Play id.
            productId = product.id.substringBefore(':'),
            priceAmountMicros = product.price.amountMicros,
            priceCurrencyCode = product.price.currencyCode,
            priceFormatted = product.price.formatted,
            hasFreeTrialOffer = product.subscriptionOptions?.freeTrial != null,
            raw = this,
        )
}
