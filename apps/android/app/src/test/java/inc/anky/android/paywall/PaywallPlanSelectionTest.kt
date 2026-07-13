package inc.anky.android.paywall

import inc.anky.android.feature.paywall.PaywallDefaults
import inc.anky.android.feature.paywall.PaywallFunnel
import inc.anky.android.feature.paywall.PaywallPlan
import inc.anky.android.feature.paywall.PaywallPlanSelection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The plan selector's whole behavior, plus the shipping-gate constants. */
class PaywallPlanSelectionTest {

    @Test
    fun yearlyIsPreselected() {
        assertEquals(PaywallPlan.YEARLY, PaywallPlanSelection().plan)
        assertEquals(PaywallPlan.YEARLY, PaywallPlan.DEFAULT)
    }

    @Test
    fun selectingTheOtherPlanChangesAndReportsIt() {
        val selection = PaywallPlanSelection()
        assertTrue(selection.select(PaywallPlan.MONTHLY))
        assertEquals(PaywallPlan.MONTHLY, selection.plan)
        assertTrue(selection.select(PaywallPlan.YEARLY))
        assertEquals(PaywallPlan.YEARLY, selection.plan)
    }

    @Test
    fun reselectingTheSamePlanIsANoOp() {
        // iOS guards before the selection haptic — no change, no feedback.
        val selection = PaywallPlanSelection()
        assertFalse(selection.select(PaywallPlan.YEARLY))
        assertEquals(PaywallPlan.YEARLY, selection.plan)
        selection.select(PaywallPlan.MONTHLY)
        assertFalse(selection.select(PaywallPlan.MONTHLY))
        assertEquals(PaywallPlan.MONTHLY, selection.plan)
    }

    @Test
    fun paywallMustNotBeSkippableInShippedBuilds() {
        // The QA / Play-review escape hatch, ported with its safety catch.
        assertFalse(PaywallDefaults.PAYWALL_IS_SKIPPABLE)
    }

    @Test
    fun funnelEventNamesMatchTheIosRegistry() {
        assertEquals("paywall_shown", PaywallFunnel.PAYWALL_SHOWN)
        assertEquals("trial_started", PaywallFunnel.TRIAL_STARTED)
        assertEquals("subscribed", PaywallFunnel.SUBSCRIBED)
    }
}
