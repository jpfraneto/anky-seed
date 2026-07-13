package inc.anky.android.feature.painting

/**
 * Pure decision logic of the painting home screen, extracted from the
 * composable so the iOS behavior (PaintingHomeView.swift) is testable on
 * the JVM: the gate-phase CTA, the quick-pass / emergency chrome, the
 * displayed painting progress, and the post-session stroke beat.
 */
enum class PaintingGatePhase {
    /** The gate's permission isn't granted yet → "Continue setup". */
    NeedsAuthorization,

    /** Authorized but no apps chosen yet → "Choose apps". */
    NeedsSelection,

    /** The practice stands → "Write". */
    Ready,
}

enum class PaintingPrimaryCta { Write, ChooseApps, ContinueSetup }

object PaintingHomeLogic {

    /** iOS `PaintingHomeView.phase`: authorization first, then selection. */
    fun gatePhase(isAuthorized: Boolean, isGateConfigured: Boolean): PaintingGatePhase = when {
        !isAuthorized -> PaintingGatePhase.NeedsAuthorization
        !isGateConfigured -> PaintingGatePhase.NeedsSelection
        else -> PaintingGatePhase.Ready
    }

    /** The one big gold button's meaning, by phase. */
    fun primaryCta(phase: PaintingGatePhase): PaintingPrimaryCta = when (phase) {
        PaintingGatePhase.Ready -> PaintingPrimaryCta.Write
        PaintingGatePhase.NeedsSelection -> PaintingPrimaryCta.ChooseApps
        PaintingGatePhase.NeedsAuthorization -> PaintingPrimaryCta.ContinueSetup
    }

    /** The quiet quick-pass line shows only when ready with passes left. */
    fun showsQuickPassLine(phase: PaintingGatePhase, passesRemaining: Int): Boolean =
        phase == PaintingGatePhase.Ready && passesRemaining > 0

    /**
     * Phase-2 §2: the emergency door must be reachable from inside the app
     * whenever the shield stands — the notification hop is never the only
     * route.
     */
    fun showsEmergencyLink(
        phase: PaintingGatePhase,
        isShieldActive: Boolean,
        isCurrentlyUnlocked: Boolean,
    ): Boolean = phase == PaintingGatePhase.Ready && isShieldActive && !isCurrentlyUnlocked

    /**
     * The reveal progress of the displayed painting. A painting behind the
     * writer's current level is complete; the current level's reveals by
     * percent within the level. No package → nothing to reveal yet.
     */
    fun paintingProgress(packageLevel: Int?, currentLevel: Int, levelPercent: Double): Double =
        when {
            packageLevel == null -> 0.0
            packageLevel < currentLevel -> 1.0
            else -> levelPercent
        }
}

/**
 * Today's strokes arrive over ~2-3s, proportional to seconds written —
 * a 12-minute session visibly paints more than one sentence.
 * Port of iOS `PaintingHomeView.playStrokeBeatIfOwed()`.
 */
object StrokeBeat {

    /** Longer sessions get the full three seconds (1.2 + pending/240, cap 3). */
    fun durationSeconds(pendingSeconds: Long): Double =
        minOf(
            CeremonyTiming.StrokeBeatMaxSeconds,
            CeremonyTiming.StrokeBeatMinSeconds + pendingSeconds.toDouble() / 240.0,
        )

    /**
     * Where the bar rolls back to before the strokes land: the pending
     * seconds' share of the level, never below zero.
     */
    fun startProgress(targetProgress: Double, pendingSeconds: Long, secondsRequired: Long): Double {
        val delta = minOf(
            pendingSeconds.toDouble() / maxOf(1L, secondsRequired).toDouble(),
            targetProgress,
        )
        return maxOf(0.0, targetProgress - delta)
    }
}

/**
 * The frame-position invariant, in density-independent points (pure math —
 * the composables convert with the local density).
 *
 * The painting's frame occupies the IDENTICAL position and size on the
 * ceremony screen and the main screen — it never moves during the
 * ceremony → main transition; everything else changes around it. Both
 * surfaces must lay the frame out through this one object.
 * Port of iOS `PaintingFrameMetrics`.
 */
object PaintingFrameMath {
    /** Horizontal inset from the screen edge to the frame (dp). */
    const val HorizontalInsetDp: Float = 28f

    /** The frame's top edge, as a fraction of the container height. */
    const val TopFraction: Float = 0.14f

    /** Widest the painting ever renders (dp; tablets, landscape). */
    const val MaxSideDp: Float = 420f

    /** The whisper-thin gold border around the canvas (dp). */
    const val BorderWidthDp: Float = 1.5f

    /** Outer glow radius that "stains" the background around the frame (dp). */
    const val GlowRadiusDp: Float = 42f

    data class FrameRect(val x: Float, val y: Float, val width: Float, val height: Float) {
        val minY: Float get() = y
        val maxY: Float get() = y + height
        val midX: Float get() = x + width / 2f
        val midY: Float get() = y + height / 2f
    }

    /**
     * The square canvas rect for a given container size (both in dp).
     * Identical math on every surface that shows the framed painting.
     */
    fun frameRect(containerWidthDp: Float, containerHeightDp: Float): FrameRect {
        val side = minOf(containerWidthDp - HorizontalInsetDp * 2f, MaxSideDp)
        val x = (containerWidthDp - side) / 2f
        val y = containerHeightDp * TopFraction
        return FrameRect(x = x, y = y, width = side, height = side)
    }
}
