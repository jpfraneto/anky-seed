package inc.anky.android.feature.gate

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import inc.anky.android.R
import inc.anky.android.core.gate.runtime.GateRuntime
import inc.anky.android.ui.lazure.AnkySunGlyph
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.lazure.WatercolorVeil
import inc.anky.android.ui.lazure.WatercolorVeilRegister
import inc.anky.android.ui.lazure.rememberBreathPhase
import kotlin.math.PI
import kotlin.math.sin
import kotlinx.coroutines.delay

/**
 * Phase-2 §2: the emergency door — port of iOS `EmergencyBreathView`.
 * Thirty seconds of pastel breath: the veil swelling on Anky's 8s cycle, a
 * thin gold hairline filling around the center. No numerals, no guilt.
 * Completing it opens the rest of the day; leaving cancels with nothing
 * owed and nothing said (backgrounding the app cancels — no partial
 * credit, exactly like the iOS scenePhase guard).
 *
 * Deviation: the iOS center is the seated Anky sprite; the sprite sheets
 * are not ported yet, so the drawn sun glyph holds the center.
 */
@Composable
fun EmergencyBreathScreen(
    onComplete: () -> Unit,
    onCancel: () -> Unit,
) {
    val phase by rememberBreathPhase()
    var progress by remember { mutableFloatStateOf(0f) }
    val currentOnComplete by rememberUpdatedState(onComplete)
    val currentOnCancel by rememberUpdatedState(onCancel)

    // Date-anchored so a dropped frame never stretches the breath.
    LaunchedEffect(Unit) {
        val startedAtMillis = System.currentTimeMillis()
        while (true) {
            val elapsedMillis = System.currentTimeMillis() - startedAtMillis
            progress = (elapsedMillis / (BreathSeconds * 1000f)).coerceAtMost(1f)
            if (elapsedMillis >= BreathSeconds * 1000L) {
                currentOnComplete()
                return@LaunchedEffect
            }
            delay(100)
        }
    }

    // Interruption cancels — no partial credit.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                currentOnCancel()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Box(Modifier.fillMaxSize()) {
        LazureWall(mood = LazureMood.Dawn)

        // The veil is the breath guide: it swells and settles on the cycle.
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    val swell = 1f + 0.05f * sin(phase * 2f * PI.toFloat())
                    scaleX = swell
                    scaleY = swell
                },
        ) {
            WatercolorVeil(register = WatercolorVeilRegister.Pale)
        }

        Box(Modifier.align(Alignment.Center)) {
            Canvas(Modifier.size(236.dp)) {
                val ringSize = Size(size.width, size.height)
                drawArc(
                    color = LazurePigments.ankyGold.copy(alpha = 0.16f),
                    startAngle = 0f,
                    sweepAngle = 360f,
                    useCenter = false,
                    style = Stroke(width = 1.dp.toPx()),
                    size = ringSize,
                )
                drawArc(
                    color = LazurePigments.ankyGold.copy(alpha = 0.42f),
                    startAngle = -90f,
                    sweepAngle = 360f * progress,
                    useCenter = false,
                    style = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round),
                    size = ringSize,
                )
            }
            Box(
                Modifier
                    .align(Alignment.Center)
                    .graphicsLayer {
                        val pulse = 1f + 0.02f * sin(phase * 2f * PI.toFloat())
                        scaleX = pulse
                        scaleY = pulse
                    },
            ) {
                AnkySunGlyph(size = 96.dp)
            }
        }

        IconButton(
            onClick = onCancel,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(top = 8.dp, start = 12.dp),
        ) {
            Icon(
                imageVector = Icons.Outlined.KeyboardArrowDown,
                contentDescription = stringResource(R.string.gate_cancel),
                tint = LazurePigments.ankyInkSoft.copy(alpha = 0.35f),
            )
        }
    }
}

/**
 * The routable form: completing the breath applies the emergency grant
 * (daily-until-midnight, no Quick Pass consumed, source `emergency`,
 * relock alarm at midnight) and hands the analytics ping to the caller —
 * the `LevelSyncClient.reportEmergencyUnlock` call stays a callback so this
 * feature never grows a network dependency.
 */
@Composable
fun EmergencyBreathRoute(
    onFinished: () -> Unit,
    onReportEmergencyUnlock: () -> Unit = {},
) {
    val context = LocalContext.current
    EmergencyBreathScreen(
        onComplete = {
            GateRuntime(context).unlockApplier.applyEmergencyUnlock()
            onReportEmergencyUnlock()
            onFinished()
        },
        onCancel = onFinished,
    )
}

/** iOS `EmergencyBreathView.breathSeconds`. */
private const val BreathSeconds = 30
