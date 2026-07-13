package inc.anky.android.you

import inc.anky.android.core.subscription.AnkyPurchasesConfig
import inc.anky.android.core.subscription.EntitlementState
import inc.anky.android.core.subscription.SubscriptionPackage
import inc.anky.android.core.subscription.SubscriptionPeriodKind
import inc.anky.android.core.subscription.SubscriptionStoreKind
import inc.anky.android.feature.you.FounderChatUrl
import inc.anky.android.feature.you.PlayManageSubscriptionsUrl
import inc.anky.android.feature.you.YouState
import inc.anky.android.feature.you.YouStatusCopy
import inc.anky.android.feature.you.activeSubscriptionPriceLine
import inc.anky.android.feature.you.mergeRefreshedYouState
import inc.anky.android.feature.you.recoveryImportErrorMessage
import inc.anky.android.feature.you.subscriptionStatusDetail
import inc.anky.android.feature.you.subscriptionStatusTitle
import inc.anky.android.feature.you.yearlySubscriptionPriceLine
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Subscription-era YouState tests (WS8). The credits-era assertions live in
 * the legacy `feature/you/YouViewModelStateTest` until the cleanup phase
 * deletes the inert credit stubs together with that file.
 */
class YouViewModelStateTest {
    private val yearlyPackage = SubscriptionPackage(
        productId = AnkyPurchasesConfig.YEARLY_PRODUCT_ID,
        priceAmountMicros = 88_000_000L,
        priceCurrencyCode = "USD",
        priceFormatted = "$88.00",
    )
    private val monthlyPackage = SubscriptionPackage(
        productId = AnkyPurchasesConfig.MONTHLY_PRODUCT_ID,
        priceAmountMicros = 11_990_000L,
        priceCurrencyCode = "USD",
        priceFormatted = "$11.99",
    )

    @Test
    fun subscriptionStatusTitleMatchesIosSettingsCopy() {
        assertEquals("Free", subscriptionStatusTitle(EntitlementState()))
        assertEquals(
            "Yearly subscription",
            subscriptionStatusTitle(
                EntitlementState(isEntitled = true, activeProductId = AnkyPurchasesConfig.YEARLY_PRODUCT_ID),
            ),
        )
        assertEquals(
            "Monthly subscription",
            subscriptionStatusTitle(
                EntitlementState(isEntitled = true, activeProductId = AnkyPurchasesConfig.MONTHLY_PRODUCT_ID),
            ),
        )
        assertEquals(
            "Active subscription",
            subscriptionStatusTitle(EntitlementState(isEntitled = true, activeProductId = "anky.lifetime")),
        )
        assertEquals(
            "Free trial",
            subscriptionStatusTitle(
                EntitlementState(
                    isEntitled = true,
                    activeProductId = AnkyPurchasesConfig.YEARLY_PRODUCT_ID,
                    activePeriodType = SubscriptionPeriodKind.TRIAL,
                ),
            ),
        )
        assertEquals(
            "Complimentary access",
            subscriptionStatusTitle(
                EntitlementState(
                    isEntitled = true,
                    isPromotionalEntitlement = true,
                    activeStore = SubscriptionStoreKind.PROMOTIONAL,
                ),
            ),
        )
    }

    @Test
    fun subscriptionStatusDetailTellsRenewalTruthAgainstGooglePlay() {
        val renewalMillis = 1_798_761_600_000L
        val formatDate: (Long) -> String = { millis -> if (millis == renewalMillis) "Jan 1, 2027" else "other" }

        val yearly = EntitlementState(
            isEntitled = true,
            activeProductId = AnkyPurchasesConfig.YEARLY_PRODUCT_ID,
            activeExpirationDateMillis = renewalMillis,
            packages = listOf(yearlyPackage, monthlyPackage),
        )
        assertEquals(
            "Renews Jan 1, 2027. You will be charged \$88/year unless you cancel in Google Play subscriptions.",
            subscriptionStatusDetail(yearly, isSubscriptionTruthAvailable = true, formatDate = formatDate),
        )

        val trial = yearly.copy(activePeriodType = SubscriptionPeriodKind.TRIAL)
        assertEquals(
            "Trial ends Jan 1, 2027. You will be charged \$88/year that day unless you cancel in Google Play subscriptions.",
            subscriptionStatusDetail(trial, isSubscriptionTruthAvailable = true, formatDate = formatDate),
        )

        val promotionalOpenEnded = EntitlementState(
            isEntitled = true,
            isPromotionalEntitlement = true,
            activeStore = SubscriptionStoreKind.PROMOTIONAL,
        )
        assertEquals(
            "Granted access, open-ended. Nothing is charged and nothing renews.",
            subscriptionStatusDetail(promotionalOpenEnded, isSubscriptionTruthAvailable = true, formatDate = formatDate),
        )

        val promotionalDated = promotionalOpenEnded.copy(activeExpirationDateMillis = renewalMillis)
        assertEquals(
            "Granted access through Jan 1, 2027. Nothing is charged — when it ends, the practice simply asks again.",
            subscriptionStatusDetail(promotionalDated, isSubscriptionTruthAvailable = true, formatDate = formatDate),
        )
    }

    @Test
    fun subscriptionStatusDetailWhileFreeExplainsWritingStaysFree() {
        assertEquals(
            "Plans are loading. You can still write for free.",
            subscriptionStatusDetail(EntitlementState(), isSubscriptionTruthAvailable = false),
        )
        assertEquals(
            "Plans are loading. You can still write for free.",
            subscriptionStatusDetail(EntitlementState(), isSubscriptionTruthAvailable = true),
        )
        val freeWithPackages = EntitlementState(packages = listOf(yearlyPackage, monthlyPackage))
        val detail = subscriptionStatusDetail(freeWithPackages, isSubscriptionTruthAvailable = true)
        assertTrue(detail, detail.startsWith("Writing is free. The full practice starts at "))
        assertTrue(detail, detail.contains("/year"))
    }

    @Test
    fun subscriptionPriceLinesDropWholeCentsLikeIos() {
        val yearly = EntitlementState(
            isEntitled = true,
            activeProductId = AnkyPurchasesConfig.YEARLY_PRODUCT_ID,
            packages = listOf(yearlyPackage, monthlyPackage),
        )
        assertEquals("$88/year", activeSubscriptionPriceLine(yearly, Locale.US))

        val monthly = yearly.copy(activeProductId = AnkyPurchasesConfig.MONTHLY_PRODUCT_ID)
        assertEquals("$11.99/month", activeSubscriptionPriceLine(monthly, Locale.US))

        assertEquals("$88/year", yearlySubscriptionPriceLine(yearly, Locale.US))
        // Store silent -> honest fallbacks, never a blank price.
        assertEquals("$88/year", activeSubscriptionPriceLine(EntitlementState(), Locale.US))
        assertEquals("$88/year", yearlySubscriptionPriceLine(EntitlementState(), Locale.US))
    }

    @Test
    fun mergeRefreshedStatePreservesSubscriptionTruthAndTransientFields() {
        val subscription = EntitlementState(isEntitled = true, activeProductId = AnkyPurchasesConfig.YEARLY_PRODUCT_ID)
        val previous = YouState(
            accountId = "old",
            subscription = subscription,
            isSubscriptionTruthAvailable = true,
            isRestoringPurchases = true,
            statusMessage = "Restored. Your practice is active.",
        )
        val refreshed = YouState(accountId = "new", completeAnkyCount = 3)

        val merged = mergeRefreshedYouState(previous, refreshed)

        assertEquals("new", merged.accountId)
        assertEquals(3, merged.completeAnkyCount)
        assertEquals(subscription, merged.subscription)
        assertEquals(true, merged.isSubscriptionTruthAvailable)
        assertEquals(true, merged.isRestoringPurchases)
        assertEquals("Restored. Your practice is active.", merged.statusMessage)
    }

    @Test
    fun recoveryImportChecksumFailureSurfacesCurrentIosCopyWithoutReplacingAccess() {
        assertEquals(
            YouStatusCopy.RecoveryWordsInvalidChecksum,
            recoveryImportErrorMessage(IllegalArgumentException("Recovery phrase checksum is invalid.")),
        )
        assertEquals(
            "These words don't form a valid recovery phrase — one of them is probably mistyped. Check each word and try again. Nothing was changed.",
            YouStatusCopy.RecoveryWordsInvalidChecksum,
        )
        assertEquals(
            "Recovery words must be 12 words.",
            recoveryImportErrorMessage(IllegalArgumentException("Recovery phrase must contain 12 words.")),
        )
        assertEquals(
            "Could not recover that identity.",
            recoveryImportErrorMessage(IllegalArgumentException("boom")),
        )
    }

    @Test
    fun manageSubscriptionAndFounderChatLinksMatchTaskContract() {
        assertEquals("https://play.google.com/store/account/subscriptions", PlayManageSubscriptionsUrl)
        assertEquals("https://t.me/ankytheapp", FounderChatUrl)
    }

    @Test
    fun supportFeedbackEmailUrlKeepsIosMailtoShape() {
        val state = YouState(accountId = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94")

        assertTrue(state.supportFeedbackEmailUrl.startsWith("mailto:support@anky.app?"))
        assertTrue(state.supportFeedbackEmailUrl.contains("subject=Anky%20support%20%2F%20feedback"))
        assertTrue(state.supportFeedbackEmailUrl.contains("body=account%20id%3A%200x9858EfFD232B4033E47d90003D41EC34EcaEda94"))
    }
}
