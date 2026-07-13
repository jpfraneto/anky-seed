package inc.anky.android.subscription

import inc.anky.android.core.subscription.SubscriptionPackage
import inc.anky.android.core.subscription.SubscriptionPriceFormatter
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class SubscriptionPriceFormatterTest {
    private val locale = Locale.US

    private fun usdPackage(amountMicros: Long, formatted: String) = SubscriptionPackage(
        productId = "anky.yearly",
        priceAmountMicros = amountMicros,
        priceCurrencyCode = "USD",
        priceFormatted = formatted,
        hasFreeTrialOffer = true,
    )

    @Test
    fun wholePriceDropsTheCents() {
        // $88/year, never $88.00/year — the PaywallView promise.
        assertEquals(
            "$88",
            SubscriptionPriceFormatter.price(usdPackage(88_000_000L, "$88.00"), "$88", locale),
        )
    }

    @Test
    fun nonWholePriceKeepsTheStoreLocalizedString() {
        assertEquals(
            "$11.99",
            SubscriptionPriceFormatter.price(usdPackage(11_990_000L, "$11.99"), "$11.99", locale),
        )
        assertEquals(
            "$88.50",
            SubscriptionPriceFormatter.price(usdPackage(88_500_000L, "$88.50"), "$88", locale),
        )
    }

    @Test
    fun missingProductFallsBack() {
        assertEquals("$88", SubscriptionPriceFormatter.price(null, "$88", locale))
        assertEquals("$1.69", SubscriptionPriceFormatter.weekly(null, "$1.69", locale))
    }

    @Test
    fun missingPriceDataFallsBackToStoreStringThenFallback() {
        val noMicros = SubscriptionPackage(
            productId = "anky.yearly",
            priceAmountMicros = null,
            priceCurrencyCode = null,
            priceFormatted = "$88.00",
        )
        assertEquals("$88.00", SubscriptionPriceFormatter.price(noMicros, "$88", locale))

        val nothing = noMicros.copy(priceFormatted = null)
        assertEquals("$88", SubscriptionPriceFormatter.price(nothing, "$88", locale))
    }

    @Test
    fun weeklyBreakdownOfYearlyPrice() {
        // The $88 plan told as a week: 88 / 52 = 1.6923… → "$1.69".
        assertEquals(
            "$1.69",
            SubscriptionPriceFormatter.weekly(usdPackage(88_000_000L, "$88.00"), "$0", locale),
        )
    }

    @Test
    fun weeklyRoundsHalfUpAtCents() {
        // 99.99 / 52 = 1.92288… → $1.92; 104 / 52 = exactly $2.00.
        assertEquals(
            "$1.92",
            SubscriptionPriceFormatter.weekly(usdPackage(99_990_000L, "$99.99"), "$0", locale),
        )
        assertEquals(
            "$2.00",
            SubscriptionPriceFormatter.weekly(usdPackage(104_000_000L, "$104.00"), "$0", locale),
        )
        // 78 / 52 = 1.5 exactly at the cents scale boundary: 1.50.
        assertEquals(
            "$1.50",
            SubscriptionPriceFormatter.weekly(usdPackage(78_000_000L, "$78.00"), "$0", locale),
        )
    }
}
