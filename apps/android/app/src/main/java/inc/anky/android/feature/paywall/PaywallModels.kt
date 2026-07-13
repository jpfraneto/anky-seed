package inc.anky.android.feature.paywall

import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import inc.anky.android.R
import inc.anky.android.core.subscription.AnkyPurchasesConfig
import inc.anky.android.core.subscription.EntitlementState
import inc.anky.android.core.subscription.SubscriptionPriceFormatter
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/**
 * One line of paywall copy: a string resource plus its format arguments.
 * Arguments may themselves be lines (e.g. "$11.99/month" nested inside the
 * active-subscription sentence), so the whole copy tree stays in
 * `strings_paywall.xml` while remaining a pure, JVM-testable value.
 */
data class PaywallLine(
    @StringRes val res: Int,
    val args: List<PaywallArg> = emptyList(),
)

sealed interface PaywallArg {
    data class Text(val value: String) : PaywallArg
    data class Nested(val line: PaywallLine) : PaywallArg
}

internal fun String.asArg(): PaywallArg = PaywallArg.Text(this)
internal fun PaywallLine.asArg(): PaywallArg = PaywallArg.Nested(this)

/** The two plans on the selector. Yearly is preselected, exactly as on iOS. */
enum class PaywallPlan {
    YEARLY,
    MONTHLY;

    companion object {
        val DEFAULT = YEARLY
    }
}

/**
 * One node of the trial timeline — the same visual grammar as the 8-day map,
 * telling the trial exactly as it will happen. Today's node is filled; the
 * days still to come are outlines.
 */
data class PaywallTimelineNode(
    @StringRes val labelRes: Int,
    @StringRes val lineRes: Int,
    val isFilled: Boolean,
)

/**
 * All copy decisions of the paywall as pure functions over
 * [EntitlementState] — the Kotlin port of the computed copy properties in
 * iOS `PaywallView.swift`. Context switches COPY ONLY; nothing here knows
 * about styling.
 */
object PaywallCopy {

    /** Fallbacks while the store hasn't answered, verbatim from iOS. */
    const val YEARLY_PRICE_FALLBACK = "$88"
    const val MONTHLY_PRICE_FALLBACK = "$11.99"
    const val WEEKLY_PRICE_FALLBACK = "$1.69"

    fun yearlyPriceText(state: EntitlementState, locale: Locale = Locale.getDefault()): String =
        SubscriptionPriceFormatter.price(state.yearlyPackage, YEARLY_PRICE_FALLBACK, locale)

    fun monthlyPriceText(state: EntitlementState, locale: Locale = Locale.getDefault()): String =
        SubscriptionPriceFormatter.price(state.monthlyPackage, MONTHLY_PRICE_FALLBACK, locale)

    /** "$1.69/wk" honesty on the yearly plan card. */
    fun yearlyWeeklyLine(state: EntitlementState, locale: Locale = Locale.getDefault()): PaywallLine =
        PaywallLine(
            R.string.paywall_weekly_breakdown,
            listOf(SubscriptionPriceFormatter.weekly(state.yearlyPackage, WEEKLY_PRICE_FALLBACK, locale).asArg()),
        )

    fun title(state: EntitlementState, context: PaywallContext, isTrialEligible: Boolean): PaywallLine {
        if (state.isEntitled) {
            return when {
                state.isPromotionalEntitlement -> PaywallLine(R.string.paywall_title_entitled_gift)
                state.isInIntroTrial -> PaywallLine(R.string.paywall_title_entitled_trial)
                else -> PaywallLine(R.string.paywall_title_entitled)
            }
        }
        return when (context) {
            PaywallContext.Onboarding ->
                if (isTrialEligible) {
                    PaywallLine(R.string.paywall_title_onboarding_trial)
                } else {
                    PaywallLine(R.string.paywall_title_onboarding)
                }
            PaywallContext.Lapsed -> PaywallLine(R.string.paywall_title_lapsed)
            is PaywallContext.Veil -> PaywallLine(R.string.paywall_title_veil)
        }
    }

    fun voiceLine(state: EntitlementState, context: PaywallContext): PaywallLine {
        if (state.isEntitled) {
            return when {
                state.isPromotionalEntitlement -> PaywallLine(R.string.paywall_voice_entitled_gift)
                state.isInIntroTrial -> PaywallLine(R.string.paywall_voice_entitled_trial)
                else -> PaywallLine(R.string.paywall_voice_entitled)
            }
        }
        return when (context) {
            PaywallContext.Onboarding -> PaywallLine(R.string.paywall_voice_onboarding)
            PaywallContext.Lapsed -> PaywallLine(R.string.paywall_voice_lapsed)
            is PaywallContext.Veil -> PaywallLine(R.string.paywall_voice_veil)
        }
    }

    /**
     * Full-body payment honesty under the selector — never fine print.
     * 3.1.2: the conversion is spelled out under the trial CTA, not only in
     * the plan card above.
     */
    fun paymentLine(
        state: EntitlementState,
        plan: PaywallPlan,
        isTrialEligible: Boolean,
        locale: Locale = Locale.getDefault(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): PaywallLine {
        if (state.isEntitled) {
            return activeSubscriptionLine(state, locale, zone)
        }
        if (plan == PaywallPlan.YEARLY && isTrialEligible) {
            return PaywallLine(
                R.string.paywall_payment_trial,
                listOf(yearlyPriceText(state, locale).asArg()),
            )
        }
        return PaywallLine(R.string.paywall_payment_immediate)
    }

    fun ctaTitle(
        state: EntitlementState,
        plan: PaywallPlan,
        isTrialEligible: Boolean,
        locale: Locale = Locale.getDefault(),
    ): PaywallLine {
        if (state.isEntitled) {
            return PaywallLine(R.string.paywall_cta_done)
        }
        return when (plan) {
            PaywallPlan.YEARLY ->
                if (isTrialEligible) {
                    PaywallLine(R.string.paywall_cta_trial)
                } else {
                    PaywallLine(R.string.paywall_cta_yearly, listOf(yearlyPriceText(state, locale).asArg()))
                }
            PaywallPlan.MONTHLY ->
                PaywallLine(R.string.paywall_cta_monthly, listOf(monthlyPriceText(state, locale).asArg()))
        }
    }

    fun yearlyPlanTitle(
        state: EntitlementState,
        isTrialEligible: Boolean,
        locale: Locale = Locale.getDefault(),
    ): PaywallLine =
        if (isTrialEligible) {
            PaywallLine(R.string.paywall_plan_yearly_trial, listOf(yearlyPriceText(state, locale).asArg()))
        } else {
            PaywallLine(R.string.paywall_plan_yearly, listOf(yearlyPriceText(state, locale).asArg()))
        }

    fun monthlyPlanTitle(state: EntitlementState, locale: Locale = Locale.getDefault()): PaywallLine =
        PaywallLine(R.string.paywall_plan_monthly, listOf(monthlyPriceText(state, locale).asArg()))

    /**
     * Three nodes on a hairline gold thread. Today's node is filled; the
     * days still to come are outlines. Shown only while `!isEntitled` and
     * trial-eligible.
     */
    val trialTimeline: List<PaywallTimelineNode> = listOf(
        PaywallTimelineNode(R.string.paywall_timeline_today_label, R.string.paywall_timeline_today_line, isFilled = true),
        PaywallTimelineNode(R.string.paywall_timeline_day2_label, R.string.paywall_timeline_day2_line, isFilled = false),
        PaywallTimelineNode(R.string.paywall_timeline_day3_label, R.string.paywall_timeline_day3_line, isFilled = false),
    )

    // region Active subscription honesty

    private fun activeSubscriptionLine(
        state: EntitlementState,
        locale: Locale,
        zone: ZoneId,
    ): PaywallLine {
        if (state.isPromotionalEntitlement) {
            val end = state.activeExpirationDateMillis
                ?: return PaywallLine(R.string.paywall_payment_promo_open_ended)
            return PaywallLine(
                R.string.paywall_payment_promo_through,
                listOf(formatDate(end, locale, zone).asArg()),
            )
        }
        val renewal = state.activeExpirationDateMillis
            ?: return PaywallLine(R.string.paywall_payment_active_unknown_renewal)
        val price = activeSubscriptionPriceLine(state, locale)
        val date = formatDate(renewal, locale, zone)
        val res = if (state.isInIntroTrial) {
            R.string.paywall_payment_active_trial
        } else {
            R.string.paywall_payment_active
        }
        return PaywallLine(res, listOf(price.asArg(), date.asArg()))
    }

    /** "$11.99/month" / "$88/year" for the active-subscription sentence. */
    internal fun activeSubscriptionPriceLine(
        state: EntitlementState,
        locale: Locale = Locale.getDefault(),
    ): PaywallLine {
        val pkg = state.activePackage ?: state.yearlyPackage
        if (state.activeProductId == AnkyPurchasesConfig.MONTHLY_PRODUCT_ID) {
            return PaywallLine(
                R.string.paywall_price_per_month,
                listOf(SubscriptionPriceFormatter.price(pkg, MONTHLY_PRICE_FALLBACK, locale).asArg()),
            )
        }
        return PaywallLine(
            R.string.paywall_price_per_year,
            listOf(SubscriptionPriceFormatter.price(pkg, YEARLY_PRICE_FALLBACK, locale).asArg()),
        )
    }

    /** Mirror of Swift's `.formatted(date: .abbreviated, time: .omitted)`. */
    internal fun formatDate(epochMillis: Long, locale: Locale, zone: ZoneId): String =
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
            .withLocale(locale)
            .format(Instant.ofEpochMilli(epochMillis).atZone(zone).toLocalDate())

    // endregion
}

/**
 * The plan selector's whole behavior, extracted so it is JVM-testable.
 * Yearly is preselected; re-tapping the selected plan is a no-op (iOS
 * guards before the selection haptic). Tapping updates only the selector,
 * the payment line, and the CTA label — never a sheet, never a discount,
 * never a countdown.
 */
class PaywallPlanSelection(initial: PaywallPlan = PaywallPlan.DEFAULT) {
    var plan: PaywallPlan by mutableStateOf(initial)
        private set

    /**
     * Returns true only when the selection actually changed — the caller
     * fires the selection haptic on true, nothing on false.
     */
    fun select(option: PaywallPlan): Boolean {
        if (plan == option) {
            return false
        }
        plan = option
        return true
    }
}
