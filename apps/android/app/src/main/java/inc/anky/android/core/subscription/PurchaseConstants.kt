package inc.anky.android.core.subscription

import android.content.SharedPreferences
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/**
 * Price presentation over the store's price data. Whole prices drop the
 * cents ($88/year, never $88.00/year); everything else is the
 * store-localized string untouched.
 *
 * Ported from iOS `Anky/Purchases/PurchaseConstants.swift`
 * (`SubscriptionPriceFormatter`). On Android the inputs are RevenueCat's
 * `Price` fields (amountMicros + currencyCode + formatted) instead of
 * StoreKit's Decimal + NumberFormatter.
 */
object SubscriptionPriceFormatter {
    private const val MICROS_PER_UNIT = 1_000_000L
    private val WEEKS_PER_YEAR = BigDecimal(52)

    fun price(pkg: SubscriptionPackage?, fallback: String, locale: Locale = Locale.getDefault()): String {
        if (pkg == null) {
            return fallback
        }
        return price(pkg.priceAmountMicros, pkg.priceCurrencyCode, pkg.priceFormatted, fallback, locale)
    }

    fun price(
        amountMicros: Long?,
        currencyCode: String?,
        storeFormatted: String?,
        fallback: String,
        locale: Locale = Locale.getDefault(),
    ): String {
        if (amountMicros == null || currencyCode == null) {
            return storeFormatted ?: fallback
        }
        if (amountMicros % MICROS_PER_UNIT != 0L) {
            // Not a whole price — the store-localized string, untouched.
            return storeFormatted ?: fallback
        }
        val formatter = currencyFormatter(currencyCode, locale)
            ?: return storeFormatted ?: fallback
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.format(BigDecimal.valueOf(amountMicros).movePointLeft(6))
    }

    /**
     * The yearly price told as a week — "$1.69" honesty on the plan selector
     * (the caller appends "/wk"). Falls back when the store hasn't answered.
     */
    fun weekly(pkg: SubscriptionPackage?, fallback: String, locale: Locale = Locale.getDefault()): String {
        if (pkg == null) {
            return fallback
        }
        return weekly(pkg.priceAmountMicros, pkg.priceCurrencyCode, fallback, locale)
    }

    fun weekly(
        amountMicros: Long?,
        currencyCode: String?,
        fallback: String,
        locale: Locale = Locale.getDefault(),
    ): String {
        if (amountMicros == null || currencyCode == null) {
            return fallback
        }
        val formatter = currencyFormatter(currencyCode, locale) ?: return fallback
        // iOS divides with plain (half-up) rounding at cents scale.
        val weekly = BigDecimal.valueOf(amountMicros)
            .movePointLeft(6)
            .divide(WEEKS_PER_YEAR, 2, RoundingMode.HALF_UP)
        return formatter.format(weekly)
    }

    private fun currencyFormatter(currencyCode: String, locale: Locale): NumberFormat =
        NumberFormat.getCurrencyInstance(locale).apply {
            runCatching { currency = Currency.getInstance(currencyCode) }
        }
}

/**
 * Phase-3 §5: the once-per-rolling-week cap on *Anky-initiated* paywall
 * pressure, shared across every paywall-adjacent surface. A writer tapping a
 * veil is asking — that is always answered; this ledger only restrains what
 * Anky starts on its own (ambient trial surfaces, future notifications).
 *
 * Ported from iOS `PaywallPressureLedger` in `PurchaseConstants.swift`.
 * Persistence key matches iOS; the value is epoch millis instead of an
 * archived Date.
 */
object PaywallPressureLedger {
    const val WINDOW_MILLIS: Long = 7L * 24L * 60L * 60L * 1000L
    const val LAST_SHOWN_KEY = "anky.paywallPressure.lastShownAt"

    fun recordPaywallShown(
        preferences: SharedPreferences,
        nowMillis: Long = System.currentTimeMillis(),
    ) {
        preferences.edit().putLong(LAST_SHOWN_KEY, nowMillis).apply()
    }

    /**
     * True while the writer saw a paywall within the rolling week — ambient
     * surfaces stay quiet until the window passes.
     */
    fun isWithinQuietWindow(
        preferences: SharedPreferences,
        nowMillis: Long = System.currentTimeMillis(),
    ): Boolean {
        if (!preferences.contains(LAST_SHOWN_KEY)) {
            return false
        }
        val last = preferences.getLong(LAST_SHOWN_KEY, 0L)
        return nowMillis - last < WINDOW_MILLIS
    }
}
