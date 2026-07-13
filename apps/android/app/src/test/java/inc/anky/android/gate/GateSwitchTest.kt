package inc.anky.android.gate

import inc.anky.android.core.gate.GateState
import inc.anky.android.core.gate.WriteBeforeScrollGateSwitchStore
import inc.anky.android.core.gate.WriteBeforeScrollShieldReconciler
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The explicit gate off-switch (2026-07-06): while the gate is off, no
 * reconcile or relock path may re-arm the shield — a foreground after the
 * off-switch leaves the shield down.
 *
 * Port of iOS GateSwitchTests.swift.
 */
class GateSwitchTest {
    private val now = Instant.ofEpochSecond(1_780_000_000)

    @Test
    fun gateSwitchStorePersistsAcrossInstances() {
        val preferences = FakeSharedPreferences()
        assertFalse(
            "gate defaults to on",
            WriteBeforeScrollGateSwitchStore(preferences).isGateOff,
        )
        WriteBeforeScrollGateSwitchStore(preferences).setGateOff(true)
        assertTrue(
            "every instance reads the same flag",
            WriteBeforeScrollGateSwitchStore(preferences).isGateOff,
        )
        WriteBeforeScrollGateSwitchStore(preferences).setGateOff(false)
        assertFalse(WriteBeforeScrollGateSwitchStore(preferences).isGateOff)
    }

    @Test
    fun foregroundReconcileWhileGateOffClearsInsteadOfArming() {
        // The exact regression the audit named: reconcileShield re-armed on
        // every foreground. With the gate off, the only legal move is clear
        // — even for a locked state that would otherwise re-shield.
        val lockedState = GateState(
            selectedApplicationCount = 3,
            shieldActive = false,
            updatedAt = now,
        )
        assertEquals(
            WriteBeforeScrollShieldReconciler.Decision.ClearShield,
            WriteBeforeScrollShieldReconciler.decision(gateOff = true, state = lockedState, at = now),
        )
    }

    @Test
    fun reconcileWhileGateOnKeepsExistingBehavior() {
        val lockedState = GateState(
            selectedApplicationCount = 3,
            shieldActive = false,
            updatedAt = now,
        )
        assertEquals(
            WriteBeforeScrollShieldReconciler.Decision.ApplyShield,
            WriteBeforeScrollShieldReconciler.decision(gateOff = false, state = lockedState, at = now),
        )

        val unlockedState = lockedState.copy(unlockedUntil = now.plusSeconds(600))
        assertEquals(
            "an active unlock still clears, as before",
            WriteBeforeScrollShieldReconciler.Decision.ClearShield,
            WriteBeforeScrollShieldReconciler.decision(gateOff = false, state = unlockedState, at = now),
        )
    }

    @Test
    fun gateOffOutranksAnActiveUnlockWindow() {
        val state = GateState(selectedApplicationCount = 3, updatedAt = now)
            .copy(unlockedUntil = now.minusSeconds(60))
        assertEquals(
            "an expired unlock (the relock moment) must not re-arm while the gate is off",
            WriteBeforeScrollShieldReconciler.Decision.ClearShield,
            WriteBeforeScrollShieldReconciler.decision(gateOff = true, state = state, at = now),
        )
    }
}
