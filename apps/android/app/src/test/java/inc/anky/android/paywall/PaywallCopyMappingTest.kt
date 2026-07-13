package inc.anky.android.paywall

import inc.anky.android.R
import inc.anky.android.core.subscription.EntitlementState
import inc.anky.android.core.subscription.SubscriptionPeriodKind
import inc.anky.android.core.subscription.SubscriptionStoreKind
import inc.anky.android.feature.paywall.PaywallContext
import inc.anky.android.feature.paywall.PaywallCopy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The context→copy mapping table, mirroring the computed copy properties of
 * iOS `PaywallView.swift`. Context changes COPY ONLY — these tests pin which
 * words each room speaks; styling has no seam to drift through.
 */
class PaywallCopyMappingTest {

    private val notEntitled = EntitlementState()
    private val entitled = EntitlementState(isEntitled = true)
    private val promotional = EntitlementState(
        isEntitled = true,
        isPromotionalEntitlement = true,
        activeStore = SubscriptionStoreKind.PROMOTIONAL,
    )
    private val inTrial = EntitlementState(
        isEntitled = true,
        activePeriodType = SubscriptionPeriodKind.TRIAL,
    )

    // region Titles

    @Test
    fun onboardingTitleFollowsTrialEligibility() {
        assertEquals(
            R.string.paywall_title_onboarding_trial,
            PaywallCopy.title(notEntitled, PaywallContext.Onboarding, isTrialEligible = true).res,
        )
        assertEquals(
            R.string.paywall_title_onboarding,
            PaywallCopy.title(notEntitled, PaywallContext.Onboarding, isTrialEligible = false).res,
        )
    }

    @Test
    fun lapsedAndVeilTitlesIgnoreTrialEligibility() {
        for (eligible in listOf(true, false)) {
            assertEquals(
                R.string.paywall_title_lapsed,
                PaywallCopy.title(notEntitled, PaywallContext.Lapsed, eligible).res,
            )
            assertEquals(
                R.string.paywall_title_veil,
                PaywallCopy.title(notEntitled, PaywallContext.Veil("reflection"), eligible).res,
            )
        }
    }

    @Test
    fun entitledTitleWinsOverEveryContext() {
        val contexts = listOf(PaywallContext.Onboarding, PaywallContext.Lapsed, PaywallContext.Veil("journey"))
        for (context in contexts) {
            assertEquals(R.string.paywall_title_entitled, PaywallCopy.title(entitled, context, true).res)
            assertEquals(R.string.paywall_title_entitled_gift, PaywallCopy.title(promotional, context, true).res)
            assertEquals(R.string.paywall_title_entitled_trial, PaywallCopy.title(inTrial, context, true).res)
        }
    }

    // endregion

    // region Voice lines

    @Test
    fun voiceLineSpeaksPerContext() {
        assertEquals(
            R.string.paywall_voice_onboarding,
            PaywallCopy.voiceLine(notEntitled, PaywallContext.Onboarding).res,
        )
        assertEquals(
            R.string.paywall_voice_lapsed,
            PaywallCopy.voiceLine(notEntitled, PaywallContext.Lapsed).res,
        )
        assertEquals(
            R.string.paywall_voice_veil,
            PaywallCopy.voiceLine(notEntitled, PaywallContext.Veil("ceremony")).res,
        )
    }

    @Test
    fun entitledVoiceLineWinsOverEveryContext() {
        for (context in listOf(PaywallContext.Onboarding, PaywallContext.Lapsed, PaywallContext.Veil("widget"))) {
            assertEquals(R.string.paywall_voice_entitled, PaywallCopy.voiceLine(entitled, context).res)
            assertEquals(R.string.paywall_voice_entitled_gift, PaywallCopy.voiceLine(promotional, context).res)
            assertEquals(R.string.paywall_voice_entitled_trial, PaywallCopy.voiceLine(inTrial, context).res)
        }
    }

    // endregion

    // region Funnel origin

    @Test
    fun funnelOriginMatchesIosTags() {
        assertEquals("onboarding", PaywallContext.Onboarding.funnelOrigin)
        assertEquals("lapsed", PaywallContext.Lapsed.funnelOrigin)
        assertEquals("free_target_moment", PaywallContext.Veil("free_target_moment").funnelOrigin)
        assertEquals("reflection", PaywallContext.Veil("reflection").funnelOrigin)
    }

    // endregion

    // region Trial timeline model

    @Test
    fun timelineHasThreeNodesAndOnlyTodayIsFilled() {
        val nodes = PaywallCopy.trialTimeline
        assertEquals(3, nodes.size)
        assertTrue(nodes[0].isFilled)
        assertFalse(nodes[1].isFilled)
        assertFalse(nodes[2].isFilled)
    }

    @Test
    fun timelineCopyIsTodayReminderTrialEnd() {
        val nodes = PaywallCopy.trialTimeline
        assertEquals(R.string.paywall_timeline_today_label, nodes[0].labelRes)
        assertEquals(R.string.paywall_timeline_today_line, nodes[0].lineRes)
        assertEquals(R.string.paywall_timeline_day2_label, nodes[1].labelRes)
        assertEquals(R.string.paywall_timeline_day2_line, nodes[1].lineRes)
        assertEquals(R.string.paywall_timeline_day3_label, nodes[2].labelRes)
        assertEquals(R.string.paywall_timeline_day3_line, nodes[2].lineRes)
    }

    // endregion
}
