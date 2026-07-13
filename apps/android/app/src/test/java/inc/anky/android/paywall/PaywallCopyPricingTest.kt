package inc.anky.android.paywall

import inc.anky.android.R
import inc.anky.android.core.subscription.EntitlementState
import inc.anky.android.core.subscription.SubscriptionPackage
import inc.anky.android.core.subscription.SubscriptionPeriodKind
import inc.anky.android.core.subscription.SubscriptionStoreKind
import inc.anky.android.feature.paywall.PaywallArg
import inc.anky.android.feature.paywall.PaywallCopy
import inc.anky.android.feature.paywall.PaywallLine
import inc.anky.android.feature.paywall.PaywallPlan
import java.time.ZoneId
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Payment honesty, CTA labels, and plan-card titles over live store prices. */
class PaywallCopyPricingTest {

    private val locale = Locale.US
    private val zone = ZoneId.of("UTC")

    private val yearly = SubscriptionPackage(
        productId = "anky.yearly",
        priceAmountMicros = 88_000_000L,
        priceCurrencyCode = "USD",
        priceFormatted = "$88.00",
        hasFreeTrialOffer = true,
    )
    private val monthly = SubscriptionPackage(
        productId = "anky.monthly",
        priceAmountMicros = 11_990_000L,
        priceCurrencyCode = "USD",
        priceFormatted = "$11.99",
    )
    private val loaded = EntitlementState(packages = listOf(yearly, monthly))

    private fun PaywallLine.textArg(index: Int = 0): String =
        (args[index] as PaywallArg.Text).value

    private fun PaywallLine.nestedArg(index: Int = 0): PaywallLine =
        (args[index] as PaywallArg.Nested).line

    // region Prices

    @Test
    fun wholeYearlyPriceDropsTheCentsAndMonthlyStaysStoreLocalized() {
        assertEquals("$88", PaywallCopy.yearlyPriceText(loaded, locale))
        assertEquals("$11.99", PaywallCopy.monthlyPriceText(loaded, locale))
    }

    @Test
    fun pricesFallBackWhileTheStoreHasNotAnswered() {
        val empty = EntitlementState()
        assertEquals("$88", PaywallCopy.yearlyPriceText(empty, locale))
        assertEquals("$11.99", PaywallCopy.monthlyPriceText(empty, locale))
        assertEquals("$1.69", PaywallCopy.yearlyWeeklyLine(empty, locale).textArg())
    }

    @Test
    fun weeklyBreakdownDividesTheYearBy52() {
        val line = PaywallCopy.yearlyWeeklyLine(loaded, locale)
        assertEquals(R.string.paywall_weekly_breakdown, line.res)
        assertEquals("$1.69", line.textArg())
    }

    // endregion

    // region Payment line

    @Test
    fun trialEligibleYearlySpellsOutTheConversion() {
        val line = PaywallCopy.paymentLine(loaded, PaywallPlan.YEARLY, isTrialEligible = true, locale, zone)
        assertEquals(R.string.paywall_payment_trial, line.res)
        assertEquals("$88", line.textArg())
    }

    @Test
    fun monthlyOrIneligibleYearlyIsBilledToday() {
        assertEquals(
            R.string.paywall_payment_immediate,
            PaywallCopy.paymentLine(loaded, PaywallPlan.MONTHLY, isTrialEligible = true, locale, zone).res,
        )
        assertEquals(
            R.string.paywall_payment_immediate,
            PaywallCopy.paymentLine(loaded, PaywallPlan.YEARLY, isTrialEligible = false, locale, zone).res,
        )
    }

    @Test
    fun promotionalEntitlementNeverPromisesACharge() {
        val openEnded = EntitlementState(isEntitled = true, isPromotionalEntitlement = true)
        assertEquals(
            R.string.paywall_payment_promo_open_ended,
            PaywallCopy.paymentLine(openEnded, PaywallPlan.YEARLY, true, locale, zone).res,
        )
        val dated = openEnded.copy(activeExpirationDateMillis = 1_767_225_600_000L) // 2026-01-01 UTC
        val line = PaywallCopy.paymentLine(dated, PaywallPlan.YEARLY, true, locale, zone)
        assertEquals(R.string.paywall_payment_promo_through, line.res)
        assertEquals("Jan 1, 2026", line.textArg())
    }

    @Test
    fun activeSubscriptionNamesPriceAndRenewalDate() {
        val active = EntitlementState(
            isEntitled = true,
            activeProductId = "anky.yearly",
            activeStore = SubscriptionStoreKind.PLAY_STORE,
            activeExpirationDateMillis = 1_767_225_600_000L,
            packages = listOf(yearly, monthly),
        )
        val line = PaywallCopy.paymentLine(active, PaywallPlan.YEARLY, false, locale, zone)
        assertEquals(R.string.paywall_payment_active, line.res)
        assertEquals(R.string.paywall_price_per_year, line.nestedArg(0).res)
        assertEquals("$88", line.nestedArg(0).textArg())
        assertEquals("Jan 1, 2026", line.textArg(1))

        val trialing = active.copy(activePeriodType = SubscriptionPeriodKind.TRIAL)
        assertEquals(
            R.string.paywall_payment_active_trial,
            PaywallCopy.paymentLine(trialing, PaywallPlan.YEARLY, false, locale, zone).res,
        )

        val monthlyActive = active.copy(activeProductId = "anky.monthly")
        val monthlyPrice = PaywallCopy.paymentLine(monthlyActive, PaywallPlan.YEARLY, false, locale, zone).nestedArg(0)
        assertEquals(R.string.paywall_price_per_month, monthlyPrice.res)
        assertEquals("$11.99", monthlyPrice.textArg())
    }

    @Test
    fun activeWithoutRenewalDatePointsAtPlaySubscriptions() {
        val active = EntitlementState(isEntitled = true, activeProductId = "anky.yearly")
        assertEquals(
            R.string.paywall_payment_active_unknown_renewal,
            PaywallCopy.paymentLine(active, PaywallPlan.YEARLY, false, locale, zone).res,
        )
    }

    // endregion

    // region CTA & plan cards

    @Test
    fun ctaFollowsPlanTrialAndEntitlement() {
        assertEquals(R.string.paywall_cta_trial, PaywallCopy.ctaTitle(loaded, PaywallPlan.YEARLY, true, locale).res)
        val yearlyCta = PaywallCopy.ctaTitle(loaded, PaywallPlan.YEARLY, false, locale)
        assertEquals(R.string.paywall_cta_yearly, yearlyCta.res)
        assertEquals("$88", yearlyCta.textArg())
        val monthlyCta = PaywallCopy.ctaTitle(loaded, PaywallPlan.MONTHLY, true, locale)
        assertEquals(R.string.paywall_cta_monthly, monthlyCta.res)
        assertEquals("$11.99", monthlyCta.textArg())
        assertEquals(
            R.string.paywall_cta_done,
            PaywallCopy.ctaTitle(EntitlementState(isEntitled = true), PaywallPlan.YEARLY, true, locale).res,
        )
    }

    @Test
    fun planCardTitlesCarryThePrices() {
        val trialCard = PaywallCopy.yearlyPlanTitle(loaded, isTrialEligible = true, locale)
        assertEquals(R.string.paywall_plan_yearly_trial, trialCard.res)
        assertEquals("$88", trialCard.textArg())
        assertEquals(
            R.string.paywall_plan_yearly,
            PaywallCopy.yearlyPlanTitle(loaded, isTrialEligible = false, locale).res,
        )
        val monthlyCard = PaywallCopy.monthlyPlanTitle(loaded, locale)
        assertEquals(R.string.paywall_plan_monthly, monthlyCard.res)
        assertEquals("$11.99", monthlyCard.textArg())
    }

    @Test
    fun yearlyPackageIsTheTrialBearer() {
        assertTrue(loaded.yearlyPackage!!.hasFreeTrialOffer)
    }

    // endregion
}
