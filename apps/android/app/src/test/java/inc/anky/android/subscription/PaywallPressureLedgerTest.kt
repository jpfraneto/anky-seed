package inc.anky.android.subscription

import inc.anky.android.core.subscription.PaywallPressureLedger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaywallPressureLedgerTest {
    private val prefs = FakeSharedPreferences()
    private val now = 1_750_000_000_000L

    @Test
    fun quietWindowIsFalseBeforeAnyPaywallWasShown() {
        assertFalse(PaywallPressureLedger.isWithinQuietWindow(prefs, now))
    }

    @Test
    fun recordingAPaywallOpensTheRollingWeekQuietWindow() {
        PaywallPressureLedger.recordPaywallShown(prefs, now)

        assertTrue(PaywallPressureLedger.isWithinQuietWindow(prefs, now))
        assertTrue(
            PaywallPressureLedger.isWithinQuietWindow(
                prefs,
                now + PaywallPressureLedger.WINDOW_MILLIS - 1L,
            ),
        )
    }

    @Test
    fun quietWindowClosesExactlyAtTheRollingWeek() {
        PaywallPressureLedger.recordPaywallShown(prefs, now)

        assertFalse(
            PaywallPressureLedger.isWithinQuietWindow(prefs, now + PaywallPressureLedger.WINDOW_MILLIS),
        )
    }

    @Test
    fun aNewerPaywallShownRestartsTheWindow() {
        PaywallPressureLedger.recordPaywallShown(prefs, now)
        val later = now + PaywallPressureLedger.WINDOW_MILLIS
        PaywallPressureLedger.recordPaywallShown(prefs, later)

        assertTrue(PaywallPressureLedger.isWithinQuietWindow(prefs, later + 1L))
    }

    @Test
    fun keyAndWindowMatchTheIosLedger() {
        assertEquals("anky.paywallPressure.lastShownAt", PaywallPressureLedger.LAST_SHOWN_KEY)
        assertEquals(7L * 24L * 60L * 60L * 1000L, PaywallPressureLedger.WINDOW_MILLIS)
    }
}
