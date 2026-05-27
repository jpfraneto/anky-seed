package inc.anky.android.feature.write

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material3.Icon
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyType
import kotlin.math.min
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun WriteScreen(
    viewModel: WriteViewModel,
    onReveal: (String) -> Unit,
    onCloseToMap: () -> Unit,
    onImportAnkyText: (String) -> SavedAnky,
    onImportAnkyBytes: (ByteArray) -> SavedAnky,
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    var importError by remember { mutableStateOf<String?>(null) }
    WriteSystemBarsHidden()
    WriteHaptics(state)

    fun importAndReveal(importBlock: () -> SavedAnky) {
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching(importBlock)
            }
            result
                .onSuccess { saved ->
                    importError = null
                    onReveal(saved.hash)
                }
                .onFailure {
                    importError = "I could not find a .anky rhythm in that."
                }
        }
    }

    val openDocument = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val bytesResult = withContext(Dispatchers.IO) {
                runCatching {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: error("Could not read .anky file.")
                }
            }
            bytesResult
                .onSuccess { bytes ->
                    importAndReveal { onImportAnkyBytes(bytes) }
                }
                .onFailure {
                    importError = "I could not open that artifact."
                }
        }
    }

    fun launchDocumentFallback() {
        openDocument.launch(arrayOf("text/plain", "application/octet-stream", "*/*"))
    }

    fun pasteOrOpenDocument() {
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        val clipboardText = context.primaryClipboardText()
        if (clipboardText.isNullOrBlank()) {
            launchDocumentFallback()
            return
        }
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { onImportAnkyText(clipboardText) }
            }
            result
                .onSuccess { saved ->
                    importError = null
                    onReveal(saved.hash)
                }
                .onFailure {
                    importError = "I could not find a .anky rhythm in that."
                    launchDocumentFallback()
                }
        }
    }

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
            onGlyphs = viewModel::acceptGlyphs,
            onRejectedMutation = {
                view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                viewModel.ignoreBackspaceOrReplacement()
            },
            modifier = Modifier.fillMaxSize().testTag("write-input"),
        )

        Box(
            modifier = Modifier
                .fillMaxSize()
                .imePadding(),
        ) {
            if (state.displayedText.isNotEmpty()) {
                Text(
                    text = writingGlyphText(state.displayedGlyphs, state.silenceElapsedMs),
                    fontSize = 20.sp,
                    lineHeight = 28.sp,
                    fontFamily = FontFamily.Monospace,
                    textAlign = TextAlign.End,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .fillMaxWidth()
                        .padding(start = 24.dp, end = 128.dp, bottom = 14.dp),
                )
            }

            WriteTopBar(
                hasActiveDotAnky = state.acceptedGlyphCount > 0 || state.isClosing,
                canPaste = state.acceptedGlyphCount == 0 && !state.isClosing,
                onCloseToMap = {
                    viewModel.abandonIfEmpty()
                    onCloseToMap()
                },
                onPaste = ::pasteOrOpenDocument,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 8.dp, start = 10.dp, end = 10.dp),
            )

            if (state.hasReachedRitualMark) {
                Text(
                    AnkyDuration.clock(state.elapsedMs),
                    color = Color.Black.copy(alpha = 0.56f),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 13.dp)
                        .background(Color.White.copy(alpha = 0.64f), RoundedCornerShape(percent = 50))
                        .border(1.dp, Color.Black.copy(alpha = 0.10f), RoundedCornerShape(percent = 50))
                        .padding(horizontal = 10.dp, vertical = 7.dp),
                )
            }

            importError?.let { message ->
                Text(
                    message,
                    color = AnkyColors.Danger,
                    style = AnkyType.Caption,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 58.dp)
                        .background(Color.White.copy(alpha = 0.92f), RoundedCornerShape(14.dp))
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                )
            }

            RitualRings(
                elapsedMs = state.elapsedMs,
                silenceElapsedMs = state.silenceElapsedMs,
                latestGlyph = state.latestGlyph,
                isRitualComplete = state.hasReachedRitualMark,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = 8.dp, bottom = 8.dp)
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
}

@Composable
private fun WriteTopBar(
    hasActiveDotAnky: Boolean,
    canPaste: Boolean,
    onCloseToMap: () -> Unit,
    onPaste: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        if (!hasActiveDotAnky) {
            WriteChromeButton(onClick = onCloseToMap, enabled = true) {
                Icon(
                    imageVector = Icons.Filled.ChevronLeft,
                    contentDescription = "Open Map",
                    tint = Color.Black.copy(alpha = 0.74f),
                    modifier = Modifier.size(17.dp),
                )
            }
        }
        Box(Modifier.weight(1f))
        if (!hasActiveDotAnky) {
            WriteChromeButton(onClick = onPaste, enabled = canPaste, isGold = true) {
                Icon(
                    imageVector = Icons.Filled.ContentPaste,
                    contentDescription = "Paste .anky artifact",
                    tint = if (canPaste) AnkyColors.Gold.copy(alpha = 0.86f) else Color.Black.copy(alpha = 0.34f),
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

@Composable
private fun WriteChromeButton(
    onClick: () -> Unit,
    enabled: Boolean,
    isGold: Boolean = false,
    content: @Composable () -> Unit,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .size(42.dp)
            .background(Color.White.copy(alpha = 0.62f), CircleShape)
            .border(
                BorderStroke(1.dp, if (isGold) AnkyColors.Gold.copy(alpha = 0.18f) else Color.Black.copy(alpha = 0.10f)),
                CircleShape,
            ),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
    ) {
        content()
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
            if (state.acceptedGlyphCount <= 2 || state.acceptedGlyphCount % 4 == 0) {
                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            }
            lastGlyphCount = state.acceptedGlyphCount
        }
    }

    val minute = (state.elapsedMs / 60_000L).toInt().coerceIn(0, 8)
    LaunchedEffect(minute) {
        if (minute > lastMinuteHaptic) {
            view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
            lastMinuteHaptic = minute
        }
    }

    val alarmSecond = (state.silenceElapsedMs / 1000L).toInt()
    LaunchedEffect(alarmSecond, state.silenceElapsedMs) {
        if (state.silenceElapsedMs < 1000L) {
            lastAlarmSecond = 0
        } else if (alarmSecond >= 7 && lastAlarmSecond == 0) {
            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            lastAlarmSecond = alarmSecond
        }
    }
}

@Composable
private fun RitualRings(
    elapsedMs: Long,
    silenceElapsedMs: Long,
    latestGlyph: String,
    isRitualComplete: Boolean,
    modifier: Modifier = Modifier,
) {
    val ritualProgress by animateFloatAsState(
        targetValue = (elapsedMs.toFloat() / AnkyDuration.CompleteRitualMs).coerceIn(0f, 1f),
        animationSpec = tween(durationMillis = 80, easing = LinearEasing),
        label = "ritual-progress",
    )
    val silenceProgress = min(1f, ((silenceElapsedMs - 3000).toFloat() / 5000f).coerceAtLeast(0f))
    val glyphColor = rhythmColor((silenceElapsedMs.toFloat() / AnkyDuration.TerminalSilenceMs).coerceIn(0f, 1f))
    val pulse by rememberInfiniteTransition(label = "ritual-pulse").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1000),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "ritual-pulse-value",
    )
    val colors = listOf(
        Color(0xFFE83324),
        Color(0xFFF2791A),
        Color(0xFFF5CE38),
        Color(0xFF38B842),
        Color(0xFF1A63F2),
        Color(0xFF4D40CC),
        Color(0xFF943DE6),
        Color(0xFFF5F2DE),
    )

    Box(modifier = modifier.size(106.dp), contentAlignment = Alignment.Center) {
        if (isRitualComplete) {
            Canvas(Modifier.size(106.dp)) {
                drawCircle(
                    color = AnkyColors.Gold.copy(alpha = 0.24f + pulse * 0.36f),
                    radius = size.minDimension / 2f,
                    style = Stroke(width = 7.dp.toPx(), cap = StrokeCap.Round),
                )
            }
        }
        Canvas(Modifier.size(106.dp)) {
            drawCircle(Color(0xFF090604).copy(alpha = 0.94f), radius = 51.dp.toPx())
            drawCircle(Color(0xFFB6873A), radius = 48.dp.toPx())
            drawCircle(Color(0xFF140E09), radius = 42.dp.toPx())

            val diameter = 80.dp.toPx()
            val arcTopLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
            val arcSize = Size(diameter, diameter)
            val stroke = Stroke(width = 15.dp.toPx(), cap = StrokeCap.Butt)
            colors.forEachIndexed { index, color ->
                val shimmer = 0.13f + pulse * 0.05f
                val start = -90f + index * 45f + 1.1f
                drawArc(
                    color = color.copy(alpha = shimmer),
                    startAngle = start,
                    sweepAngle = 42.8f,
                    useCenter = false,
                    topLeft = arcTopLeft,
                    size = arcSize,
                    style = stroke,
                )
                val segmentProgress = ((ritualProgress * 8f) - index).coerceIn(0f, 1f)
                if (segmentProgress > 0f) {
                    drawArc(
                        color = color.copy(alpha = if (segmentProgress < 1f) 0.78f + pulse * 0.10f else 0.90f),
                        startAngle = start,
                        sweepAngle = 42.8f * segmentProgress,
                        useCenter = false,
                        topLeft = arcTopLeft,
                        size = arcSize,
                        style = stroke,
                    )
                }
            }
            repeat(8) { index ->
                val angle = Math.toRadians((index * 45f + 22.5f - 90f).toDouble())
                val center = Offset(
                    x = size.width / 2f + kotlin.math.cos(angle).toFloat() * 37.dp.toPx(),
                    y = size.height / 2f + kotlin.math.sin(angle).toFloat() * 37.dp.toPx(),
                )
                drawCircle(Color(0xFF29170A).copy(alpha = 0.92f), radius = 2.2.dp.toPx(), center = center)
            }
            drawCircle(Color(0xFFD6A64F), radius = 32.5.dp.toPx(), style = Stroke(width = 5.dp.toPx()))
            drawCircle(Color(0xFF050506).copy(alpha = 0.88f), radius = 28.dp.toPx())
            drawCircle(Color.White.copy(alpha = 0.12f + pulse * 0.06f), radius = 18.dp.toPx())
            val cursorProgress = ritualProgress.coerceIn(0f, 1f)
            if (cursorProgress > 0f || isRitualComplete) {
                val angle = Math.toRadians((-90f + cursorProgress * 360f).toDouble())
                val radius = 40.dp.toPx()
                val center = Offset(
                    x = size.width / 2f + kotlin.math.cos(angle).toFloat() * radius,
                    y = size.height / 2f + kotlin.math.sin(angle).toFloat() * radius,
                )
                drawCircle(Color.White.copy(alpha = 0.86f), radius = (3.2f + pulse) * density, center = center)
                drawCircle(AnkyColors.Gold.copy(alpha = 0.74f), radius = (6.5f + pulse * 2.5f) * density, center = center, style = Stroke(width = 1.dp.toPx()))
            }
        }
        if (silenceElapsedMs >= 3000) {
            Canvas(Modifier.size(65.dp)) {
                drawArc(
                    color = Color.White.copy(alpha = 0.34f + pulse * 0.16f),
                    startAngle = -90f,
                    sweepAngle = -360f * silenceProgress,
                    useCenter = false,
                    size = Size(size.width, size.height),
                    style = Stroke(width = 3.2.dp.toPx(), cap = StrokeCap.Round),
                )
            }
        }
        if (latestGlyph.isBlank()) {
            Box(
                Modifier
                    .size(width = 2.dp, height = 25.dp)
                    .offset(y = 0.dp)
                    .background(AnkyColors.Paper.copy(alpha = if (pulse > 0.5f) 0.58f else 0.20f), CircleShape),
            )
        } else {
            Text(
                latestGlyph,
                fontSize = 36.sp,
                fontWeight = FontWeight.Medium,
                fontFamily = FontFamily.SansSerif,
                color = glyphColor.copy(alpha = 0.94f),
            )
        }
    }
}

private fun writingGlyphText(glyphs: List<WritingGlyph>, silenceElapsedMs: Long) = buildAnnotatedString {
    val latestIndex = glyphs.lastIndex
    val pageOpacity = 0.22f + (((silenceElapsedMs - 3000).toFloat() / 5000f).coerceIn(0f, 1f) * 0.78f)
    glyphs.forEachIndexed { index, glyph ->
        val isLatest = index == latestIndex
        val alpha = if (isLatest) 0.96f else maxOf(0.28f, pageOpacity * 0.82f)
        withStyle(SpanStyle(color = rhythmColor(glyph.silenceProgress).copy(alpha = alpha))) {
            append(glyph.glyph)
        }
    }
}

private fun rhythmColor(progress: Float): Color {
    val clamped = progress.coerceIn(0f, 1f)
    val red = 0.94f + (1f - 0.94f) * clamped
    val green = 0.12f + (1f - 0.12f) * clamped
    val blue = 0.08f + (1f - 0.08f) * clamped
    return Color(red, green, blue)
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

private fun Context.primaryClipboardText(): String? {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = clipboard.primaryClip ?: return null
    if (clip.itemCount == 0) return null
    return clip.getItemAt(0).coerceToText(this)?.toString()
}
