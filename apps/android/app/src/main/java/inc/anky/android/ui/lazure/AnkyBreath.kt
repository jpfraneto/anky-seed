package inc.anky.android.ui.lazure

import android.provider.Settings
import androidx.compose.animation.core.withInfiniteAnimationFrameMillis
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import kotlin.math.PI
import kotlin.math.cos
import kotlinx.coroutines.isActive

/**
 * One breath = 8 seconds. All ambient motion in the app shares this
 * clock, so every surface inhales and exhales together.
 *
 * Port of the iOS `AnkyBreath` enum. Like the iOS version (which derives
 * the phase from `timeIntervalSinceReferenceDate`), the phase is a pure
 * function of wall-clock time — two components that never met still
 * breathe in unison.
 */
object AnkyBreath {
    /** Full inhale-exhale cycle, in milliseconds. */
    const val CYCLE_MILLIS: Long = 8_000L

    /**
     * A smooth 0 -> 1 -> 0 phase driven by the shared 8s clock.
     * Eased with a cosine so there is no jolt at the loop point.
     */
    fun phase(atMillis: Long): Float {
        val wrapped = ((atMillis % CYCLE_MILLIS) + CYCLE_MILLIS) % CYCLE_MILLIS
        val t = wrapped.toFloat() / CYCLE_MILLIS.toFloat()
        return 0.5f - 0.5f * cos(t * 2f * PI.toFloat())
    }
}

/**
 * A shared breath clock provided by [LazureTheme] so an entire screen
 * ticks off a single frame loop. `null` means "no shared clock in scope";
 * [rememberBreathPhase] then spins up its own.
 */
val LocalBreathClock = staticCompositionLocalOf<State<Float>?> { null }

/**
 * The breath phase (0 -> 1 -> 0 over 8 seconds) as observable state.
 *
 * Prefers the clock provided by [LazureTheme]; falls back to a private
 * clock so lazure components stay self-sufficient outside the theme.
 * Read the returned state *inside* a draw or layout block to get
 * draw-only invalidation instead of recomposition.
 */
@Composable
fun rememberBreathPhase(): State<Float> =
    LocalBreathClock.current ?: rememberStandaloneBreathClock()

/**
 * A breath clock of one's own. Updates at most ~20fps (matching the iOS
 * `TimelineView(.animation(minimumInterval: 1/20))` cadence) and holds
 * still at mid-breath (0.5, exactly like the iOS reduce-motion branch)
 * when the user has disabled animations system-wide.
 */
@Composable
internal fun rememberStandaloneBreathClock(): State<Float> {
    val context = LocalContext.current
    val reduceMotion = remember(context) {
        Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f
    }
    if (reduceMotion) {
        return remember { mutableFloatStateOf(0.5f) }
    }
    return produceState(initialValue = AnkyBreath.phase(System.currentTimeMillis())) {
        var lastFrameMillis = 0L
        while (isActive) {
            withInfiniteAnimationFrameMillis { frameMillis ->
                if (frameMillis - lastFrameMillis >= FRAME_BUDGET_MILLIS) {
                    lastFrameMillis = frameMillis
                    value = AnkyBreath.phase(System.currentTimeMillis())
                }
            }
        }
    }
}

/** ~20fps — ambient weather, not UI animation. */
private const val FRAME_BUDGET_MILLIS = 50L
