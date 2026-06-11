package inc.anky.android.feature.write

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
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
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
import inc.anky.android.R
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyType
import kotlin.math.min
import kotlin.math.ceil
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun WriteScreen(
    viewModel: WriteViewModel,
    onImported: (String) -> Unit,
    onCompleted: (String) -> Unit,
    onCloseToMap: () -> Unit,
    onBackFromContinuation: () -> Unit = onCloseToMap,
    onImportAnkyText: (String) -> SavedAnky,
    onImportAnkyBytes: (ByteArray) -> SavedAnky,
    inputEnabled: Boolean = true,
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val importReadableError = stringResource(R.string.write_import_readable_error)
    val importOpenError = stringResource(R.string.write_import_open_error)
    val openMapLabel = stringResource(R.string.open_map)
    var importError by remember { mutableStateOf<String?>(null) }
    WriteSystemBarsHidden()
    WriteHaptics(state)

    fun importAndOfferReflection(importBlock: () -> SavedAnky) {
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching(importBlock)
            }
            result
                .onSuccess { saved ->
                    importError = null
                    onImported(saved.hash)
                }
                .onFailure {
                    importError = importReadableError
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
                    importAndOfferReflection { onImportAnkyBytes(bytes) }
                }
                .onFailure {
                    importError = importOpenError
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
                    onImported(saved.hash)
                }
                .onFailure {
                    importError = importReadableError
                    launchDocumentFallback()
                }
        }
    }

    LaunchedEffect(state.isClosing, state.latestGlyph) {
        while (state.isClosing) {
            viewModel.refreshLiveState()
            kotlinx.coroutines.delay(32)
        }
    }

    LaunchedEffect(state.completedHash) {
        state.completedHash?.let(onCompleted)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .testTag("write-screen"),
    ) {
        HiddenTextInput(
            onGlyph = viewModel::acceptGlyph,
            onGlyphs = viewModel::acceptGlyphs,
            onRejectedMutation = {
                view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                viewModel.ignoreBackspaceOrReplacement()
            },
            inputEnabled = inputEnabled,
            focusRequestId = state.keyboardFocusRequestId,
            modifier = Modifier.fillMaxSize().testTag("write-input"),
        )

        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .imePadding(),
        ) {
            val writingScrollState = rememberScrollState()
            LaunchedEffect(state.displayedGlyphs.size, state.keyboardFocusRequestId) {
                delay(16)
                writingScrollState.scrollTo(writingScrollState.maxValue)
            }
            if (state.displayedText.isNotEmpty()) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .fillMaxWidth()
                        .height(maxHeight)
                        .verticalScroll(writingScrollState),
                    contentAlignment = Alignment.BottomEnd,
                ) {
                    Text(
                        text = writingGlyphText(state.displayedGlyphs, state.silenceElapsedMs),
                        fontSize = 20.sp,
                        lineHeight = 28.sp,
                        fontFamily = FontFamily.Monospace,
                        textAlign = TextAlign.End,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 24.dp, end = 24.dp, bottom = 24.dp),
                    )
                }
            }

            WriteTopBar(
                hasActiveDotAnky = state.acceptedGlyphCount > 0 || state.isClosing,
                showContinuationBack = state.isFrozenForContinuation,
                onCloseToMap = {
                    viewModel.abandonIfEmpty()
                    onCloseToMap()
                },
                onBackFromContinuation = {
                    viewModel.abandonIfEmpty()
                    onBackFromContinuation()
                },
                openMapLabel = openMapLabel,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 8.dp, start = 10.dp, end = 10.dp),
            )

            if (state.hasReachedRitualMark) {
                val clockText = AnkyDuration.clock(state.elapsedMs)
                val writingTimeLabel = stringResource(R.string.writing_time_format, clockText)
                Text(
                    clockText,
                    color = Color.Black.copy(alpha = 0.56f),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 13.dp)
                        .background(Color.White.copy(alpha = 0.64f), RoundedCornerShape(percent = 50))
                        .border(1.dp, Color.Black.copy(alpha = 0.10f), RoundedCornerShape(percent = 50))
                        .semantics {
                            contentDescription = writingTimeLabel
                        }
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
                        .background(Color.Black.copy(alpha = 0.92f), RoundedCornerShape(14.dp))
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                )
            }

            RitualRings(
                elapsedMs = state.elapsedMs,
                silenceElapsedMs = state.silenceElapsedMs,
                latestGlyph = state.latestGlyph,
                rejectedInputPulseId = state.rejectedInputPulseId,
                isRitualComplete = state.hasReachedRitualMark,
                modifier = Modifier
                    .align(Alignment.Center)
                    .testTag("ritual-glyph"),
            )
        }
    }
}

@Composable
private fun WriteTopBar(
    hasActiveDotAnky: Boolean,
    showContinuationBack: Boolean,
    onCloseToMap: () -> Unit,
    onBackFromContinuation: () -> Unit,
    openMapLabel: String,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        AnimatedVisibility(
            visible = !hasActiveDotAnky || showContinuationBack,
            enter = fadeIn(animationSpec = tween(160)),
            exit = fadeOut(animationSpec = tween(180)),
        ) {
            WriteChromeButton(
                onClick = if (showContinuationBack) onBackFromContinuation else onCloseToMap,
                enabled = true,
            ) {
                Icon(
                    imageVector = Icons.Filled.ChevronLeft,
                    contentDescription = openMapLabel,
                    tint = Color.Black.copy(alpha = 0.74f),
                    modifier = Modifier.size(17.dp),
                )
            }
        }
        Box(Modifier.weight(1f))
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
    rejectedInputPulseId: Int,
    isRitualComplete: Boolean,
    modifier: Modifier = Modifier,
) {
    val ritualProgress by animateFloatAsState(
        targetValue = (elapsedMs.toFloat() / AnkyDuration.CompleteRitualMs).coerceIn(0f, 1f),
        animationSpec = tween(durationMillis = 80, easing = LinearEasing),
        label = "ritual-progress",
    )
    val silenceProgress = min(1f, ((silenceElapsedMs - 3000).toFloat() / 5000f).coerceAtLeast(0f))
    val remainingSilenceSeconds = maxOf(
        0,
        ceil((AnkyDuration.TerminalSilenceMs - silenceElapsedMs).toDouble() / 1000.0).toInt(),
    )
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
    var rejectedInputFlash by remember { mutableStateOf(0f) }
    val rejectedFlashAlpha by animateFloatAsState(
        targetValue = rejectedInputFlash,
        animationSpec = tween(durationMillis = if (rejectedInputFlash > 0f) 80 else 420),
        label = "rejected-input-flash",
    )

    LaunchedEffect(rejectedInputPulseId) {
        if (rejectedInputPulseId <= 0) return@LaunchedEffect
        rejectedInputFlash = 1f
        delay(520)
        rejectedInputFlash = 0f
    }

    Box(modifier = modifier.size(190.dp), contentAlignment = Alignment.Center) {
        if (isRitualComplete) {
            Canvas(Modifier.size(190.dp)) {
                drawCircle(
                    color = AnkyColors.Gold.copy(alpha = 0.24f + pulse * 0.36f),
                    radius = size.minDimension / 2f,
                    style = Stroke(width = 7.dp.toPx(), cap = StrokeCap.Round),
                )
            }
        }
        Canvas(Modifier.size(190.dp)) {
            drawCircle(Color(0xFF090604).copy(alpha = 0.88f), radius = 91.dp.toPx())
            drawCircle(AnkyColors.Gold.copy(alpha = 0.20f), radius = 88.dp.toPx(), style = Stroke(width = 1.dp.toPx()))
            drawCircle(Color(0xFF100C09).copy(alpha = 0.90f), radius = 65.dp.toPx())

            val diameter = 164.dp.toPx()
            val arcTopLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
            val arcSize = Size(diameter, diameter)
            colors.forEachIndexed { index, color ->
                val segmentProgress = ((ritualProgress * 8f) - index).coerceIn(0f, 1f)
                val isPassed = segmentProgress >= 1f
                val isActive = segmentProgress > 0f && segmentProgress < 1f
                val passiveStroke = Stroke(width = 9.dp.toPx(), cap = StrokeCap.Butt)
                val activeStroke = Stroke(
                    width = ((if (isPassed) 18f else 15f) + if (isActive) pulse * 1.8f else 0f).dp.toPx(),
                    cap = StrokeCap.Butt,
                )
                val start = -90f + index * 45f + 2.2f
                val sweep = 40.6f
                drawArc(
                    color = color.copy(alpha = 0.22f),
                    startAngle = start,
                    sweepAngle = sweep,
                    useCenter = false,
                    topLeft = arcTopLeft,
                    size = arcSize,
                    style = passiveStroke,
                )
                if (segmentProgress > 0f) {
                    drawArc(
                        color = color.copy(alpha = if (isActive) 0.76f + pulse * 0.08f else 0.92f),
                        startAngle = start,
                        sweepAngle = sweep * segmentProgress,
                        useCenter = false,
                        topLeft = arcTopLeft,
                        size = arcSize,
                        style = activeStroke,
                    )
                }
            }
            repeat(8) { index ->
                rotate(degrees = index * 45f + 22.5f, pivot = center) {
                    drawRoundRect(
                        color = Color.Black.copy(alpha = 0.56f),
                        topLeft = Offset(size.width / 2f - 1.5.dp.toPx(), size.height / 2f - 82.dp.toPx()),
                        size = Size(3.dp.toPx(), 27.dp.toPx()),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(1.5.dp.toPx(), 1.5.dp.toPx()),
                    )
                }
            }
            drawCircle(AnkyColors.Gold.copy(alpha = 0.24f), radius = 59.dp.toPx(), style = Stroke(width = 1.5.dp.toPx()))
            drawCircle(Color(0xFF050506).copy(alpha = 0.88f + 0.11f * rejectedFlashAlpha), radius = 54.dp.toPx())
            drawCircle(
                Color(0xFFF20A08).copy(alpha = 0.06f + 0.22f * rejectedFlashAlpha),
                radius = 59.dp.toPx(),
                style = Stroke(width = (1.1f + rejectedFlashAlpha * 1.1f).dp.toPx(), cap = StrokeCap.Round),
            )
        }
        if (silenceElapsedMs >= 3000 && remainingSilenceSeconds > 0) {
            Text(
                remainingSilenceSeconds.toString(),
                fontSize = 42.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.Monospace,
                color = AnkyColors.Gold.copy(alpha = 0.88f),
            )
            Canvas(Modifier.size(108.dp)) {
                drawArc(
                    color = Color.White.copy(alpha = 0.34f + pulse * 0.16f),
                    startAngle = -90f,
                    sweepAngle = -360f * silenceProgress,
                    useCenter = false,
                    topLeft = Offset.Zero,
                    size = Size(size.width, size.height),
                    style = Stroke(width = 3.2.dp.toPx(), cap = StrokeCap.Round),
                )
            }
        } else if (latestGlyph.isBlank()) {
            Box(
                Modifier
                    .size(width = 3.dp, height = 48.dp)
                    .offset(y = 0.dp)
                    .background(AnkyColors.Paper.copy(alpha = if (pulse > 0.5f) 0.58f else 0.20f), CircleShape),
            )
        } else {
            Text(
                latestGlyph,
                fontSize = 48.sp,
                fontWeight = FontWeight.Medium,
                fontFamily = FontFamily.SansSerif,
                color = Color.White.copy(alpha = 0.94f),
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
        withStyle(SpanStyle(color = Color.White.copy(alpha = alpha))) {
            append(glyph.glyph)
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

private fun Context.primaryClipboardText(): String? {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = clipboard.primaryClip ?: return null
    if (clip.itemCount == 0) return null
    return clip.getItemAt(0).coerceToText(this)?.toString()
}
