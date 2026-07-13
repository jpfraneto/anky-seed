package inc.anky.android.painting

import inc.anky.android.feature.painting.CeremonyBeat
import inc.anky.android.feature.painting.CeremonyTiming
import inc.anky.android.feature.painting.StrokeBeat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The ceremony's beat table is the product — these values are locked to
 * iOS `CeremonyTiming.swift`, second for second.
 */
class CeremonyTimingTest {

    @Test
    fun beatDurationsMatchIos() {
        assertEquals(2.2, CeremonyTiming.FinalStrokesSeconds, 0.0)
        assertEquals(1.8, CeremonyTiming.HeldBreathSeconds, 0.0)
        assertEquals(1.1, CeremonyTiming.DarkeningSeconds, 0.0)
        assertEquals(0.8, CeremonyTiming.TitleFadeSeconds, 0.0)
        assertEquals(8.0, CeremonyTiming.GlimpseBloomSeconds, 0.0)
        assertEquals(1.2, CeremonyTiming.GlimpseHoldSeconds, 0.0)
        assertEquals(1.8, CeremonyTiming.GlimpseRecedeSeconds, 0.0)
        assertEquals(0.9, CeremonyTiming.BeginFadeSeconds, 0.0)
        assertEquals(3.4, CeremonyTiming.DrainSeconds, 0.0)
    }

    @Test
    fun timelinePlaysInIosOrderWithMatchingDurations() {
        assertEquals(
            listOf(
                CeremonyBeat.FinalStrokes to 2.2,
                CeremonyBeat.HeldBreath to 1.8,
                CeremonyBeat.Darkening to 1.1,
                CeremonyBeat.Title to 0.8,
                CeremonyBeat.GlimpseBloom to 8.0,
                CeremonyBeat.GlimpseHold to 1.2,
                CeremonyBeat.GlimpseRecede to 1.8,
                CeremonyBeat.Begin to 0.9,
                CeremonyBeat.Drain to 3.4,
            ),
            CeremonyTiming.beatTimeline,
        )
    }

    @Test
    fun ceremonyResistsSkippingByBeingShort() {
        // ≤ ~15s to the Begin button (iOS header comment).
        assertEquals(15.1, CeremonyTiming.secondsUntilBegin, 1e-9)
        assertTrue(CeremonyTiming.secondsUntilBegin <= 15.5)
    }

    @Test
    fun millisRoundsWholeBeats() {
        assertEquals(2200L, CeremonyTiming.millis(CeremonyTiming.FinalStrokesSeconds))
        assertEquals(8000L, CeremonyTiming.millis(CeremonyTiming.GlimpseBloomSeconds))
        assertEquals(3400L, CeremonyTiming.millis(CeremonyTiming.DrainSeconds))
    }

    // MARK: Stroke beat (main screen, not the ceremony)

    @Test
    fun strokeBeatDurationIsProportionalAndClamped() {
        // One sentence (~10s written): barely above the minimum.
        assertEquals(1.2 + 10.0 / 240.0, StrokeBeat.durationSeconds(10), 1e-9)
        // A 12-minute session hits the 3-second cap (1.2 + 720/240 = 4.2 → 3).
        assertEquals(3.0, StrokeBeat.durationSeconds(720), 0.0)
        // Exactly at the knee: 1.2 + 432/240 = 3.0.
        assertEquals(3.0, StrokeBeat.durationSeconds(432), 1e-9)
        // Zero pending still respects the minimum window.
        assertEquals(1.2, StrokeBeat.durationSeconds(0), 0.0)
    }

    @Test
    fun strokeBeatRollsBackByThePendingShareOfTheLevel() {
        // 60 pending seconds of a 600-second level = 10% of the bar.
        assertEquals(0.4, StrokeBeat.startProgress(0.5, 60, 600), 1e-9)
        // Never below zero: the delta is capped at the target itself.
        assertEquals(0.0, StrokeBeat.startProgress(0.05, 600, 600), 1e-9)
        // Degenerate requirement guards against division by zero.
        assertEquals(0.0, StrokeBeat.startProgress(1.0, 10, 0), 1e-9)
    }
}
