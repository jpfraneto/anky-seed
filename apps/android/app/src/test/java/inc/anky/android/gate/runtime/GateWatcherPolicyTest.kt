package inc.anky.android.gate.runtime

import inc.anky.android.core.gate.GateState
import inc.anky.android.core.gate.runtime.GateWatcherPolicy
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GateWatcherPolicyTest {

    private val now: Instant = Instant.parse("2026-07-07T12:00:00Z")
    private val ownPackage = "app.anky.mobile"
    private val blocked = setOf("com.instagram.android", "com.twitter.android")

    private fun lockedState() = GateState(
        selectedApplicationCount = 2,
        shieldActive = true,
    )

    private fun unlockedState(until: Instant) = GateState(
        selectedApplicationCount = 2,
        shieldActive = false,
        unlockTierRawValue = "quick_pass",
        unlockedUntil = until,
    )

    @Test
    fun `blocked app foregrounded while locked launches the shield`() {
        val verdict = GateWatcherPolicy.verdict(
            foregroundPackage = "com.instagram.android",
            blockedPackages = blocked,
            ownPackage = ownPackage,
            gateOff = false,
            state = lockedState(),
            now = now,
        )
        assertEquals(
            GateWatcherPolicy.Verdict.LaunchShield("com.instagram.android"),
            verdict,
        )
    }

    @Test
    fun `unblocked app never shields`() {
        val verdict = GateWatcherPolicy.verdict(
            foregroundPackage = "com.example.calculator",
            blockedPackages = blocked,
            ownPackage = ownPackage,
            gateOff = false,
            state = lockedState(),
            now = now,
        )
        assertEquals(GateWatcherPolicy.Verdict.None, verdict)
    }

    @Test
    fun `anky itself never shields`() {
        val verdict = GateWatcherPolicy.verdict(
            foregroundPackage = ownPackage,
            blockedPackages = blocked + ownPackage, // even if misconfigured
            ownPackage = ownPackage,
            gateOff = false,
            state = lockedState(),
            now = now,
        )
        assertEquals(GateWatcherPolicy.Verdict.None, verdict)
    }

    @Test
    fun `active unlock window opens the door`() {
        val verdict = GateWatcherPolicy.verdict(
            foregroundPackage = "com.instagram.android",
            blockedPackages = blocked,
            ownPackage = ownPackage,
            gateOff = false,
            state = unlockedState(until = now.plusSeconds(600)),
            now = now,
        )
        assertEquals(GateWatcherPolicy.Verdict.None, verdict)
    }

    @Test
    fun `expired unlock window shields again`() {
        val verdict = GateWatcherPolicy.verdict(
            foregroundPackage = "com.instagram.android",
            blockedPackages = blocked,
            ownPackage = ownPackage,
            gateOff = false,
            state = unlockedState(until = now.minusSeconds(1)),
            now = now,
        )
        assertEquals(
            GateWatcherPolicy.Verdict.LaunchShield("com.instagram.android"),
            verdict,
        )
    }

    @Test
    fun `the off-switch outranks everything`() {
        val verdict = GateWatcherPolicy.verdict(
            foregroundPackage = "com.instagram.android",
            blockedPackages = blocked,
            ownPackage = ownPackage,
            gateOff = true,
            state = lockedState(),
            now = now,
        )
        assertEquals(GateWatcherPolicy.Verdict.None, verdict)
    }

    @Test
    fun `no foreground package is silence`() {
        val verdict = GateWatcherPolicy.verdict(
            foregroundPackage = null,
            blockedPackages = blocked,
            ownPackage = ownPackage,
            gateOff = false,
            state = lockedState(),
            now = now,
        )
        assertEquals(GateWatcherPolicy.Verdict.None, verdict)
    }

    // Belt-and-braces reconcile

    @Test
    fun `expired unlock still marked open needs a state reconcile`() {
        assertTrue(
            GateWatcherPolicy.needsStateReconcile(
                gateOff = false,
                state = unlockedState(until = now.minusSeconds(1)),
                now = now,
            ),
        )
    }

    @Test
    fun `agreeing state stays untouched on tick`() {
        assertFalse(
            GateWatcherPolicy.needsStateReconcile(
                gateOff = false,
                state = lockedState(),
                now = now,
            ),
        )
        assertFalse(
            GateWatcherPolicy.needsStateReconcile(
                gateOff = false,
                state = unlockedState(until = now.plusSeconds(600)),
                now = now,
            ),
        )
    }

    @Test
    fun `gate off with shield still marked up needs clearing`() {
        assertTrue(
            GateWatcherPolicy.needsStateReconcile(
                gateOff = true,
                state = lockedState(),
                now = now,
            ),
        )
    }

    // Launch debounce

    @Test
    fun `same package within debounce window does not relaunch`() {
        assertFalse(
            GateWatcherPolicy.shouldLaunchAgain(
                lastLaunchedPackage = "com.instagram.android",
                lastLaunchAtMillis = 1_000L,
                packageName = "com.instagram.android",
                nowMillis = 1_000L + GateWatcherPolicy.ShieldLaunchDebounceMillis - 1,
            ),
        )
    }

    @Test
    fun `different package or elapsed debounce relaunches`() {
        assertTrue(
            GateWatcherPolicy.shouldLaunchAgain(
                lastLaunchedPackage = "com.instagram.android",
                lastLaunchAtMillis = 1_000L,
                packageName = "com.twitter.android",
                nowMillis = 1_100L,
            ),
        )
        assertTrue(
            GateWatcherPolicy.shouldLaunchAgain(
                lastLaunchedPackage = "com.instagram.android",
                lastLaunchAtMillis = 1_000L,
                packageName = "com.instagram.android",
                nowMillis = 1_000L + GateWatcherPolicy.ShieldLaunchDebounceMillis,
            ),
        )
    }
}
