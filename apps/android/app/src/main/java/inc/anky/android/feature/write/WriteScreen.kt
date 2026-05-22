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
            .background(Color.Black)
            .testTag("write-screen"),
    ) {
        HiddenTextInput(
            onGlyph = viewModel::acceptGlyph,
            onGlyphs = viewModel::acceptGlyphs,
            onRejectedMutation = viewModel::ignoreBackspaceOrReplacement,
            modifier = Modifier.fillMaxSize().testTag("write-input"),
        )

        Box(
            modifier = Modifier
                .fillMaxSize()
                .imePadding(),
        ) {
            if (state.displayedText.isNotEmpty()) {
                Text(
                    text = state.displayedText,
                    color = AnkyColors.Paper.copy(alpha = 0.82f),
                    fontSize = 20.sp,
                    lineHeight = 28.sp,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp)
                        .verticalScroll(rememberScrollState()),
                )
            }

            WriteTopBar(
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
                    color = AnkyColors.PaperMuted.copy(alpha = 0.72f),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 13.dp)
                        .background(AnkyColors.Panel.copy(alpha = 0.64f), RoundedCornerShape(percent = 50))
                        .border(1.dp, AnkyColors.PaperMuted.copy(alpha = 0.10f), RoundedCornerShape(percent = 50))
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
                        .background(AnkyColors.Background.copy(alpha = 0.92f), RoundedCornerShape(14.dp))
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                )
            }

            RitualRings(
                elapsedMs = state.elapsedMs,
                silenceElapsedMs = state.silenceElapsedMs,
                silenceRemainingMs = state.silenceRemainingMs,
                latestGlyph = state.latestGlyph,
                isRitualComplete = state.hasReachedRitualMark,
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
                        .background(AnkyColors.Background)
                        .padding(16.dp),
                )
            }
        }
    }
}

@Composable
private fun WriteTopBar(
    canPaste: Boolean,
    onCloseToMap: () -> Unit,
    onPaste: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        TextButton(
            onClick = onCloseToMap,
            modifier = Modifier
                .padding(end = 8.dp)
                .background(AnkyColors.Panel.copy(alpha = 0.62f), RoundedCornerShape(percent = 50))
                .border(BorderStroke(1.dp, AnkyColors.PaperMuted.copy(alpha = 0.10f)), RoundedCornerShape(percent = 50)),
        ) {
            Icon(
                imageVector = Icons.Filled.ChevronLeft,
                contentDescription = null,
                tint = AnkyColors.PaperMuted.copy(alpha = 0.78f),
                modifier = Modifier.size(17.dp),
            )
            Icon(
                imageVector = Icons.Filled.Map,
                contentDescription = null,
                tint = AnkyColors.PaperMuted.copy(alpha = 0.78f),
                modifier = Modifier.size(17.dp),
            )
            Text(
                "Map",
                color = AnkyColors.PaperMuted.copy(alpha = 0.78f),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Box(Modifier.weight(1f))
        TextButton(
            onClick = onPaste,
            enabled = canPaste,
            modifier = Modifier
                .background(AnkyColors.Panel.copy(alpha = 0.62f), RoundedCornerShape(percent = 50))
                .border(BorderStroke(1.dp, AnkyColors.Gold.copy(alpha = 0.18f)), RoundedCornerShape(percent = 50)),
        ) {
            Icon(
                imageVector = Icons.Filled.ContentPaste,
                contentDescription = null,
                tint = AnkyColors.GoldSoft.copy(alpha = if (canPaste) 0.86f else 0.34f),
                modifier = Modifier.size(16.dp),
            )
            Text(
                "PASTE",
                color = AnkyColors.GoldSoft.copy(alpha = if (canPaste) 0.86f else 0.34f),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
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
    silenceRemainingMs: Long,
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
    val keyOpacity = (silenceRemainingMs.toFloat() / AnkyDuration.TerminalSilenceMs).coerceIn(0f, 1f)
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
        if (isRitualComplete) {
            Canvas(Modifier.size(186.dp)) {
                drawCircle(
                    color = AnkyColors.Gold.copy(alpha = 0.30f + pulse * 0.34f),
                    style = Stroke(width = 15.dp.toPx(), cap = StrokeCap.Round),
                )
            }
        }
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
                    .background(AnkyColors.Paper.copy(alpha = if (pulse > 0.5f) 0.72f else 0.24f), CircleShape),
            )
        } else {
            Text(
                latestGlyph,
                fontSize = 58.sp,
                fontWeight = FontWeight.Normal,
                fontFamily = FontFamily.SansSerif,
                color = AnkyColors.Paper.copy(alpha = keyOpacity.coerceAtLeast(0.08f)),
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

private fun Context.primaryClipboardText(): String? {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = clipboard.primaryClip ?: return null
    if (clip.itemCount == 0) return null
    return clip.getItemAt(0).coerceToText(this)?.toString()
}
