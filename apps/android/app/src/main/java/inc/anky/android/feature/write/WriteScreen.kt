package inc.anky.android.feature.write

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.core.protocol.AnkyDuration
import kotlin.math.min

@Composable
fun WriteScreen(
    viewModel: WriteViewModel,
    onReveal: (String) -> Unit,
    onCloseToMap: () -> Unit,
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    WriteSystemBarsHidden()
    WriteHaptics(state)

    LaunchedEffect(state.completedHash) {
        state.completedHash?.let { hash ->
            onReveal(hash)
            viewModel.consumeCompletedHash()
        }
    }

    LaunchedEffect(state.isClosing, state.latestGlyph) {
        while (state.isClosing) {
            viewModel.refreshLiveState()
            kotlinx.coroutines.delay(32)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .testTag("write-screen"),
    ) {
        HiddenTextInput(
            onGlyph = viewModel::acceptGlyph,
            onRejectedMutation = viewModel::ignoreBackspaceOrReplacement,
            modifier = Modifier.fillMaxSize().testTag("write-input"),
        )
        if (!state.isClosing) {
            IconButton(
                onClick = {
                    viewModel.abandonIfEmpty()
                    onCloseToMap()
                },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 10.dp, end = 12.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.Map,
                    contentDescription = "Open Map",
                    tint = Color.Black.copy(alpha = 0.46f),
                    modifier = Modifier.size(22.dp),
                )
            }
        }
        RitualRings(
            elapsedMs = state.elapsedMs,
            silenceElapsedMs = state.silenceElapsedMs,
            silenceRemainingMs = state.silenceRemainingMs,
            latestGlyph = state.latestGlyph,
            modifier = Modifier
                .align(Alignment.Center)
                .testTag("ritual-glyph"),
        )
        state.errorMessage?.let { errorMessage ->
            Text(
                errorMessage,
                color = Color.Red,
                fontSize = 13.sp,
                modifier = Modifier
                    .align(Alignment.Center)
                    .background(Color.White)
                    .padding(16.dp),
            )
        }
    }
}

@Composable
private fun WriteHaptics(state: WriteState) {
    val view = LocalView.current
    var lastGlyphCount by remember { mutableIntStateOf(state.acceptedGlyphCount) }
    var lastMinuteHaptic by remember { mutableIntStateOf((state.elapsedMs / 60_000L).toInt().coerceIn(0, 8)) }
    var lastAlarmSecond by remember { mutableIntStateOf(0) }

    LaunchedEffect(state.acceptedGlyphCount) {
        if (state.acceptedGlyphCount > lastGlyphCount) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
            lastGlyphCount = state.acceptedGlyphCount
        }
    }

    val minute = (state.elapsedMs / 60_000L).toInt().coerceIn(0, 8)
    LaunchedEffect(minute) {
        if (minute > lastMinuteHaptic) {
            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            lastMinuteHaptic = minute
        }
    }

    val alarmSecond = (state.silenceElapsedMs / 1000L).toInt()
    LaunchedEffect(alarmSecond, state.silenceElapsedMs) {
        if (state.silenceElapsedMs < 1000L) {
            lastAlarmSecond = 0
        } else if (alarmSecond >= 5 && alarmSecond > lastAlarmSecond) {
            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            lastAlarmSecond = alarmSecond
        }
    }
}

@Composable
private fun RitualRings(
    elapsedMs: Long,
    silenceElapsedMs: Long,
    silenceRemainingMs: Long,
    latestGlyph: String,
    modifier: Modifier = Modifier,
) {
    val ritualProgress by animateFloatAsState(
        targetValue = (elapsedMs.toFloat() / AnkyDuration.CompleteRitualMs).coerceIn(0f, 1f),
        animationSpec = tween(durationMillis = 80, easing = LinearEasing),
        label = "ritual-progress",
    )
    val silenceProgress = min(1f, ((silenceElapsedMs - 3000).toFloat() / 5000f).coerceAtLeast(0f))
    val keyOpacity = (silenceRemainingMs.toFloat() / AnkyDuration.TerminalSilenceMs).coerceIn(0f, 1f)
    val colors = listOf(
        Color.Red,
        Color(0xFFFF9800),
        Color.Yellow,
        Color.Green,
        Color.Blue,
        Color(0xFF4F46E5),
        Color(0xFFA855F7),
        Color.White,
    )

    Box(modifier = modifier.size(190.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(186.dp)) {
            val stroke = Stroke(width = 10.dp.toPx(), cap = StrokeCap.Butt)
            val arcSize = Size(size.width, size.height)
            colors.forEachIndexed { index, color ->
                val start = -90f + index * 45f
                drawArc(
                    color = color.copy(alpha = 0.16f),
                    startAngle = start,
                    sweepAngle = 45f,
                    useCenter = false,
                    size = arcSize,
                    style = stroke,
                )
                val segmentProgress = ((ritualProgress * 8f) - index).coerceIn(0f, 1f)
                if (segmentProgress > 0f) {
                    drawArc(
                        color = color,
                        startAngle = start,
                        sweepAngle = 45f * segmentProgress,
                        useCenter = false,
                        size = arcSize,
                        style = stroke,
                    )
                }
            }
        }
        if (silenceElapsedMs >= 3000) {
            Canvas(Modifier.size(154.dp)) {
                drawArc(
                    color = Color.White.copy(alpha = 0.42f),
                    startAngle = -90f,
                    sweepAngle = -360f * silenceProgress,
                    useCenter = false,
                    size = Size(size.width, size.height),
                    style = Stroke(width = 5.dp.toPx(), cap = StrokeCap.Round),
                )
            }
        }
        if (latestGlyph.isBlank()) {
            Box(
                Modifier
                    .size(width = 3.dp, height = 54.dp)
                    .offset(y = 0.dp)
                    .background(Color.Black.copy(alpha = 0.58f), CircleShape),
            )
        } else {
            Text(
                latestGlyph,
                fontSize = 58.sp,
                fontWeight = FontWeight.Normal,
                fontFamily = FontFamily.SansSerif,
                color = Color.Black.copy(alpha = keyOpacity.coerceAtLeast(0.08f)),
            )
        }
    }
}

@Composable
private fun WriteSystemBarsHidden() {
    val activity = LocalContext.current.findActivity() ?: return
    DisposableEffect(activity) {
        val window = activity.window
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
        onDispose {
            controller.show(WindowInsetsCompat.Type.systemBars())
            WindowCompat.setDecorFitsSystemWindows(window, true)
        }
    }
}

private tailrec fun Context.findActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }
