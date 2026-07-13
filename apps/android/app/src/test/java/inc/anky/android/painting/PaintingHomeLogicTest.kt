package inc.anky.android.painting

import inc.anky.android.feature.painting.PaintingFrameMath
import inc.anky.android.feature.painting.PaintingGatePhase
import inc.anky.android.feature.painting.PaintingHomeLogic
import inc.anky.android.feature.painting.PaintingPrimaryCta
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `PaintingHomeView.phase` / chrome rules, ported and pinned. */
class PaintingHomeLogicTest {

    // MARK: Gate phase → CTA

    @Test
    fun authorizationOutranksSelection() {
        assertEquals(
            PaintingGatePhase.NeedsAuthorization,
            PaintingHomeLogic.gatePhase(isAuthorized = false, isGateConfigured = false),
        )
        assertEquals(
            PaintingGatePhase.NeedsAuthorization,
            PaintingHomeLogic.gatePhase(isAuthorized = false, isGateConfigured = true),
        )
        assertEquals(
            PaintingGatePhase.NeedsSelection,
            PaintingHomeLogic.gatePhase(isAuthorized = true, isGateConfigured = false),
        )
        assertEquals(
            PaintingGatePhase.Ready,
            PaintingHomeLogic.gatePhase(isAuthorized = true, isGateConfigured = true),
        )
    }

    @Test
    fun primaryCtaSpeaksByPhase() {
        assertEquals(PaintingPrimaryCta.Write, PaintingHomeLogic.primaryCta(PaintingGatePhase.Ready))
        assertEquals(PaintingPrimaryCta.ChooseApps, PaintingHomeLogic.primaryCta(PaintingGatePhase.NeedsSelection))
        assertEquals(
            PaintingPrimaryCta.ContinueSetup,
            PaintingHomeLogic.primaryCta(PaintingGatePhase.NeedsAuthorization),
        )
    }

    // MARK: Quick pass line

    @Test
    fun quickPassLineNeedsReadinessAndPassesLeft() {
        assertTrue(PaintingHomeLogic.showsQuickPassLine(PaintingGatePhase.Ready, 3))
        assertTrue(PaintingHomeLogic.showsQuickPassLine(PaintingGatePhase.Ready, 1))
        assertFalse(PaintingHomeLogic.showsQuickPassLine(PaintingGatePhase.Ready, 0))
        assertFalse(PaintingHomeLogic.showsQuickPassLine(PaintingGatePhase.NeedsSelection, 3))
        assertFalse(PaintingHomeLogic.showsQuickPassLine(PaintingGatePhase.NeedsAuthorization, 3))
    }

    // MARK: Emergency door

    @Test
    fun emergencyLinkShowsOnlyWhileShieldedAndLocked() {
        assertTrue(
            PaintingHomeLogic.showsEmergencyLink(
                PaintingGatePhase.Ready,
                isShieldActive = true,
                isCurrentlyUnlocked = false,
            ),
        )
        assertFalse(
            PaintingHomeLogic.showsEmergencyLink(
                PaintingGatePhase.Ready,
                isShieldActive = true,
                isCurrentlyUnlocked = true,
            ),
        )
        assertFalse(
            PaintingHomeLogic.showsEmergencyLink(
                PaintingGatePhase.Ready,
                isShieldActive = false,
                isCurrentlyUnlocked = false,
            ),
        )
        assertFalse(
            PaintingHomeLogic.showsEmergencyLink(
                PaintingGatePhase.NeedsSelection,
                isShieldActive = true,
                isCurrentlyUnlocked = false,
            ),
        )
    }

    // MARK: Painting progress

    @Test
    fun olderPaintingsAreCompleteCurrentRevealsByPercent() {
        // No package installed yet: nothing to reveal.
        assertEquals(0.0, PaintingHomeLogic.paintingProgress(null, 3, 0.4), 0.0)
        // A painting behind the writer's level is complete.
        assertEquals(1.0, PaintingHomeLogic.paintingProgress(2, 3, 0.4), 0.0)
        // The current level's reveals by percent within the level.
        assertEquals(0.4, PaintingHomeLogic.paintingProgress(3, 3, 0.4), 0.0)
        // A prefetched future painting also shows the current percent
        // (matches iOS: only `package.level < levelProgress.level` completes).
        assertEquals(0.4, PaintingHomeLogic.paintingProgress(4, 3, 0.4), 0.0)
    }

    // MARK: Frame invariant

    @Test
    fun frameRectMatchesIosMetrics() {
        val frame = PaintingFrameMath.frameRect(390f, 844f)
        // side = width − 2×28, centered, top at 14% of the height.
        assertEquals(334f, frame.width, 0f)
        assertEquals(334f, frame.height, 0f)
        assertEquals(28f, frame.x, 0f)
        assertEquals(844f * 0.14f, frame.y, 1e-3f)
        assertEquals(844f * 0.14f + 334f, frame.maxY, 1e-3f)
    }

    @Test
    fun frameNeverOutgrowsTablets() {
        val frame = PaintingFrameMath.frameRect(900f, 1200f)
        assertEquals(420f, frame.width, 0f)
        assertEquals((900f - 420f) / 2f, frame.x, 0f)
    }
}
