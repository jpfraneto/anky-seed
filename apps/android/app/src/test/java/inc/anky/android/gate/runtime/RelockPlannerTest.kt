package inc.anky.android.gate.runtime

import inc.anky.android.core.gate.runtime.RelockPlanner
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

class RelockPlannerTest {

    private val now = Instant.parse("2026-07-07T12:00:00Z")

    @Test
    fun `a real unlock window schedules exactly at unlockedUntil`() {
        val unlockedUntil = now.plusSeconds(15 * 60)
        assertEquals(
            RelockPlanner.Plan.At(unlockedUntil.toEpochMilli()),
            RelockPlanner.plan(now, unlockedUntil),
        )
    }

    @Test
    fun `windows of five seconds or less are refused, like the iOS scheduler`() {
        assertEquals(RelockPlanner.Plan.TooShort, RelockPlanner.plan(now, now.plusSeconds(5)))
        assertEquals(RelockPlanner.Plan.TooShort, RelockPlanner.plan(now, now))
        assertEquals(RelockPlanner.Plan.TooShort, RelockPlanner.plan(now, now.minusSeconds(60)))
    }

    @Test
    fun `just past the minimum lead is scheduled`() {
        val unlockedUntil = now.plusSeconds(6)
        assertEquals(
            RelockPlanner.Plan.At(unlockedUntil.toEpochMilli()),
            RelockPlanner.plan(now, unlockedUntil),
        )
    }
}
