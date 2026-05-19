package inc.anky.android.ui.components

import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import inc.anky.android.R
import inc.anky.android.ui.theme.AnkyColors
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

enum class AnkySequenceName {
    FindingThread,
    IdleFront,
    IdleBlink,
    WaveFront,
    WalkRight,
    Celebrate,
    Seated,
    Sleeping,
    SoftConcern,
    ShyListening,
}

private val nextSequenceOrder = listOf(
    AnkySequenceName.IdleFront,
    AnkySequenceName.IdleBlink,
    AnkySequenceName.WaveFront,
    AnkySequenceName.WalkRight,
    AnkySequenceName.Celebrate,
    AnkySequenceName.Seated,
    AnkySequenceName.Sleeping,
    AnkySequenceName.SoftConcern,
    AnkySequenceName.ShyListening,
)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AnkyPresenceOverlay(
    defaultSequence: AnkySequenceName,
    goldenGlow: Boolean = false,
    transformToSigil: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val preferences = remember(context) {
        context.getSharedPreferences("anky-presence", Context.MODE_PRIVATE)
    }
    val hasStoredPosition = remember(preferences) {
        preferences.contains("x") && preferences.contains("y")
    }
    var sequence by remember { mutableStateOf(defaultSequence) }
    var visible by remember { mutableStateOf(true) }
    var showMenu by remember { mutableStateOf(false) }
    var forceCompanion by remember { mutableStateOf(false) }
    var cursor by remember { mutableIntStateOf(0) }
    var breath by remember { mutableStateOf(false) }
    var offsetX by remember { mutableStateOf(preferences.getFloat("x", -1f).takeIf { it >= 0f }) }
    var offsetY by remember { mutableStateOf(preferences.getFloat("y", -1f).takeIf { it >= 0f }) }
    var followsHomePosition by remember { mutableStateOf(!hasStoredPosition) }
    val glowPulse by rememberInfiniteTransition(label = "anky-glow").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1000),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "anky-glow-pulse",
    )

    LaunchedEffect(defaultSequence) {
        sequence = defaultSequence
        cursor = 0
    }

    LaunchedEffect(transformToSigil) {
        if (!transformToSigil) forceCompanion = false
    }

    LaunchedEffect(sequence) {
        cursor = 0
        val interval = (1000 / sequence.fps()).toLong().coerceAtLeast(80)
        while (true) {
            delay(interval)
            val frames = sequence.frames()
            if (frames.size > 1) cursor = (cursor + 1) % frames.size
            breath = !breath
        }
    }

    BoxWithConstraints(modifier) {
        val sizeDp = maxOf(76.dp, minOf(96.dp, maxWidth * 0.22f))
        val sizePx = with(density) { sizeDp.toPx() }
        val maxWidthPx = with(density) { maxWidth.toPx() }
        val maxHeightPx = with(density) { maxHeight.toPx() }
        val keyboardHeightPx = WindowInsets.ime.getBottom(density).toFloat()
        val bottomLimit = (maxHeightPx - keyboardHeightPx - sizePx - 12f).coerceAtLeast(8f)
        val homeX = defaultOffsetX(maxWidthPx, sizePx, density)
        val homeY = defaultOffsetY(maxHeightPx, keyboardHeightPx, sizePx, density)
        if (offsetX == null || offsetY == null) {
            offsetX = homeX
            offsetY = homeY
        } else if (followsHomePosition) {
            offsetX = homeX
            offsetY = homeY
        } else if ((offsetY ?: 0f) > bottomLimit) {
            offsetY = bottomLimit
        }

        val showsCompanion = visible && (!transformToSigil || forceCompanion)
        val frameId = if (showsCompanion) {
            sequence.frames().getOrElse(cursor) { R.drawable.anky001 }
        } else {
            R.drawable.anky_sigil_smal
        }

        Box(
            modifier = Modifier
                .offset {
                    IntOffset(
                        (offsetX ?: 0f).roundToInt(),
                        (offsetY ?: 0f).roundToInt(),
                    )
                }
                .size(sizeDp)
                .scale(if (showsCompanion && breath) 1.025f else if (showsCompanion) 0.985f else 1f)
                .alpha(1f)
                .combinedClickable(
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        if (transformToSigil && visible && !forceCompanion) {
                            forceCompanion = true
                        } else {
                            visible = !visible
                        }
                    },
                    onLongClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        showMenu = true
                    },
                )
                .pointerInput(maxWidthPx, maxHeightPx, keyboardHeightPx, sizePx) {
                    detectDragGestures(
                        onDragEnd = {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            followsHomePosition = false
                            preferences.edit()
                                .putFloat("x", offsetX ?: 0f)
                                .putFloat("y", offsetY ?: 0f)
                                .apply()
                        },
                    ) { change, dragAmount ->
                        change.consume()
                        offsetX = ((offsetX ?: 0f) + dragAmount.x).coerceIn(8f, maxWidthPx - sizePx - 8f)
                        offsetY = ((offsetY ?: 0f) + dragAmount.y).coerceIn(8f, bottomLimit)
                    }
                },
        ) {
            if (showsCompanion && goldenGlow) {
                Canvas(Modifier.size(sizeDp)) {
                    drawCircle(
                        color = AnkyColors.Gold.copy(alpha = 0.12f + glowPulse * 0.08f),
                        radius = size.minDimension * (0.54f + glowPulse * 0.07f),
                    )
                }
            }
            Image(
                painter = painterResource(frameId),
                contentDescription = "Anky",
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(sizeDp),
            )
            DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                DropdownMenuItem(
                    text = { Text(if (visible) "drag anky anywhere" else "tap the sigil to bring anky back") },
                    enabled = false,
                    onClick = {},
                )
                if (visible) {
                    DropdownMenuItem(
                        text = { Text("Keep Anky here") },
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            followsHomePosition = false
                            preferences.edit()
                                .putFloat("x", offsetX ?: homeX)
                                .putFloat("y", offsetY ?: homeY)
                                .apply()
                            showMenu = false
                        },
                    )
                }
                DropdownMenuItem(
                    text = { Text(if (visible) "Hide Anky" else "Show Anky") },
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        visible = !visible
                        showMenu = false
                    },
                )
                DropdownMenuItem(
                    text = { Text("Move Anky home") },
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        offsetX = homeX
                        offsetY = homeY
                        followsHomePosition = true
                        preferences.edit()
                            .putFloat("x", offsetX ?: 0f)
                            .putFloat("y", offsetY ?: 0f)
                            .apply()
                        showMenu = false
                    },
                )
                DropdownMenuItem(
                    text = { Text("Change motion") },
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        sequence = sequence.next()
                        showMenu = false
                    },
                )
            }
        }
    }
}

private fun AnkySequenceName.frames(): List<Int> =
    when (this) {
        AnkySequenceName.Celebrate -> numberedFrames(27..31)
        AnkySequenceName.FindingThread -> ankyThreadFrameResources
        AnkySequenceName.IdleBlink -> numberedFrames(40..45)
        AnkySequenceName.IdleFront -> numberedFrames(1..6)
        AnkySequenceName.Seated -> numberedFrames(46..51)
        AnkySequenceName.ShyListening -> numberedFrames(52..57)
        AnkySequenceName.Sleeping -> numberedFrames(36..39)
        AnkySequenceName.SoftConcern -> numberedFrames(32..35)
        AnkySequenceName.WalkRight -> numberedFrames(7..22)
        AnkySequenceName.WaveFront -> numberedFrames(23..26)
    }

private fun AnkySequenceName.fps(): Int =
    when (this) {
        AnkySequenceName.FindingThread,
        AnkySequenceName.Celebrate,
        AnkySequenceName.WaveFront,
            -> 5
        AnkySequenceName.WalkRight -> 8
        AnkySequenceName.Sleeping -> 2
        else -> 4
    }

private fun AnkySequenceName.next(): AnkySequenceName {
    val index = nextSequenceOrder.indexOf(this)
    return if (index < 0) AnkySequenceName.IdleFront else nextSequenceOrder[(index + 1) % nextSequenceOrder.size]
}

private fun numberedFrames(range: IntRange): List<Int> =
    range.map { ankyFrameResources[it - 1] }

private val ankyFrameResources = listOf(
    R.drawable.anky001,
    R.drawable.anky002,
    R.drawable.anky003,
    R.drawable.anky004,
    R.drawable.anky005,
    R.drawable.anky006,
    R.drawable.anky007,
    R.drawable.anky008,
    R.drawable.anky009,
    R.drawable.anky010,
    R.drawable.anky011,
    R.drawable.anky012,
    R.drawable.anky013,
    R.drawable.anky014,
    R.drawable.anky015,
    R.drawable.anky016,
    R.drawable.anky017,
    R.drawable.anky018,
    R.drawable.anky019,
    R.drawable.anky020,
    R.drawable.anky021,
    R.drawable.anky022,
    R.drawable.anky023,
    R.drawable.anky024,
    R.drawable.anky025,
    R.drawable.anky026,
    R.drawable.anky027,
    R.drawable.anky028,
    R.drawable.anky029,
    R.drawable.anky030,
    R.drawable.anky031,
    R.drawable.anky032,
    R.drawable.anky033,
    R.drawable.anky034,
    R.drawable.anky035,
    R.drawable.anky036,
    R.drawable.anky037,
    R.drawable.anky038,
    R.drawable.anky039,
    R.drawable.anky040,
    R.drawable.anky041,
    R.drawable.anky042,
    R.drawable.anky043,
    R.drawable.anky044,
    R.drawable.anky045,
    R.drawable.anky046,
    R.drawable.anky047,
    R.drawable.anky048,
    R.drawable.anky049,
    R.drawable.anky050,
    R.drawable.anky051,
    R.drawable.anky052,
    R.drawable.anky053,
    R.drawable.anky054,
    R.drawable.anky055,
    R.drawable.anky056,
    R.drawable.anky057,
)

private val ankyThreadFrameResources = listOf(
    R.drawable.ankythread_001,
    R.drawable.ankythread_002,
    R.drawable.ankythread_003,
    R.drawable.ankythread_004,
    R.drawable.ankythread_005,
    R.drawable.ankythread_006,
    R.drawable.ankythread_007,
    R.drawable.ankythread_008,
)

private fun defaultOffsetX(maxWidthPx: Float, sizePx: Float, density: Density): Float =
    (maxWidthPx - sizePx - 20.dp.toPx(density)).coerceAtLeast(8.dp.toPx(density))

private fun defaultOffsetY(maxHeightPx: Float, keyboardHeightPx: Float, sizePx: Float, density: Density): Float =
    (maxHeightPx - keyboardHeightPx - sizePx - 110.dp.toPx(density)).coerceAtLeast(8.dp.toPx(density))

private fun androidx.compose.ui.unit.Dp.toPx(density: androidx.compose.ui.unit.Density): Float =
    with(density) { toPx() }
