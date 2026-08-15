package inc.anky.android.continuity

import inc.anky.android.core.continuity.GeshtuContinuity
import inc.anky.android.core.continuity.GeshtuEvent
import inc.anky.android.core.continuity.GeshtuPhase
import inc.anky.android.core.continuity.GeshtuReducer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeshtuContinuityTest {
    @Test
    fun sealedWritingCanContinueAsTheSameSession() {
        val closed = GeshtuReducer.reduce(
            GeshtuContinuity(),
            GeshtuEvent.ChannelClosed("session-a"),
        )
        val resumed = GeshtuReducer.reduce(closed, GeshtuEvent.KeepWriting)

        assertEquals(GeshtuPhase.Writing, resumed.phase)
        assertEquals("session-a", resumed.sessionToResumeHash)
        assertEquals(null, resumed.pendingSessionHash)
    }

    @Test
    fun reflectionRequiresAnOfferingThatActuallyStands() {
        val empty = GeshtuReducer.reduce(GeshtuContinuity(), GeshtuEvent.SendOffering)
        assertEquals(GeshtuPhase.Writing, empty.phase)

        val closed = GeshtuReducer.reduce(
            GeshtuContinuity(),
            GeshtuEvent.ChannelClosed("session-a"),
        )
        assertTrue(closed.offeringStands)
        assertEquals(
            GeshtuPhase.Reflection,
            GeshtuReducer.reduce(closed, GeshtuEvent.SendOffering).phase,
        )
    }

    @Test
    fun unreflectedPastDayCanBecomeALateOffering() {
        val landing = GeshtuReducer.reduce(GeshtuContinuity(), GeshtuEvent.Settle)
        val opened = GeshtuReducer.reduce(landing, GeshtuEvent.OpenEntry("old-session"))
        val armed = GeshtuReducer.reduce(opened, GeshtuEvent.ArmLateOffering)

        assertEquals(GeshtuPhase.EntryOpen, armed.phase)
        assertEquals("old-session", armed.pendingSessionHash)
        assertTrue(armed.isLateOfferingArmed)
        assertTrue(armed.offeringStands)
    }

    @Test
    fun settlingClearsTransientSessionStateAndReturnsToTheWorld() {
        val closed = GeshtuReducer.reduce(
            GeshtuContinuity(),
            GeshtuEvent.ChannelClosed("session-a"),
        )
        val landing = GeshtuReducer.reduce(closed, GeshtuEvent.Settle)

        assertEquals(GeshtuPhase.Landing, landing.phase)
        assertEquals(null, landing.pendingSessionHash)
        assertEquals(null, landing.openedEntryHash)
        assertFalse(landing.isDeviceSpace)
        assertTrue(landing.anchorIsVisible)
    }
}
