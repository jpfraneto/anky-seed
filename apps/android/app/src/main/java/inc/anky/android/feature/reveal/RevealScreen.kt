package inc.anky.android.feature.reveal

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.KeyboardReturn
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Backspace
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.R
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.ui.components.AnkyConversationPrompt
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.lazure.ReflectionGhost
import inc.anky.android.ui.lazure.VeiledFeature
import inc.anky.android.ui.lazure.WatercolorVeil
import inc.anky.android.ui.lazure.WatercolorVeilRegister
import inc.anky.android.ui.theme.AnkyType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The reading room, subscription era: paper, ink, and — for free writers —
 * the veil standing where the reflection would bloom. Mirrors the current
 * iOS RevealView; the credits purchase surface is gone.
 */
@Suppress("UNUSED_PARAMETER")
@Composable
fun RevealScreen(
    viewModel: RevealViewModel,
    startsReflectionOnAppear: Boolean = false,
    onOpenTag: (String) -> Unit = {},
    onOpenPaywall: (String) -> Unit = {},
    onRequestReview: () -> Unit = {},
    onBack: () -> Unit,
    onDeleted: () -> Unit = {},
    onTryAgain: (SavedAnky) -> Unit = {},
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val density = LocalDensity.current
    val view = LocalView.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val artifact = state.artifact
    val scrollState = rememberScrollState()
    val scope = rememberCoroutineScope()
    var confirmDelete by remember { mutableStateOf(false) }
    var copiedBurst by remember { mutableStateOf<RevealCopySection?>(null) }
    var inlineReflectionActive by remember { mutableStateOf(false) }
    var didAutoStartReflection by remember { mutableStateOf(false) }
    var didAnchorStreamingReflection by remember { mutableStateOf(false) }
    var didRequestFirstReflectionReview by remember { mutableStateOf(false) }
    var reflectionPromptGuidanceVisible by remember { mutableStateOf(false) }
    var scrollViewportBounds by remember { mutableStateOf<Rect?>(null) }
    var reflectionBounds by remember { mutableStateOf<Rect?>(null) }
    val labels = revealLabels()
    val writingClipboardLabel = stringResource(R.string.reveal_copy_writing_clipboard_label)
    val reflectionClipboardLabel = stringResource(R.string.reveal_copy_reflection_clipboard_label)
    val reflectionPromptClipboardLabel = stringResource(R.string.reveal_copy_reflection_prompt_clipboard_label)
    val bottomActionProtectedHeightPx = with(density) { 130.dp.toPx() }
    val isReflectionVisible by remember(state.reflection?.hash, reflectionBounds, scrollViewportBounds, scrollState.value, bottomActionProtectedHeightPx) {
        derivedStateOf {
            val viewport = scrollViewportBounds
            val reflection = reflectionBounds
            val visibleViewportBottom = viewport?.bottom?.minus(bottomActionProtectedHeightPx)
            state.reflection != null &&
                viewport != null &&
                reflection != null &&
                reflection.bottom > viewport.top &&
                visibleViewportBottom != null &&
                reflection.top < visibleViewportBottom
        }
    }
    val shouldShowBottomAction = artifact != null &&
        (state.reflection == null || !isReflectionVisible)

    fun scrollToReflection(allowBottomFallback: Boolean = true) {
        scope.launch {
            repeat(12) {
                if (scrollViewportBounds != null && reflectionBounds != null) return@repeat
                delay(16)
            }
            val viewportTop = scrollViewportBounds?.top
            val reflectionTop = reflectionBounds?.top
            if (viewportTop != null && reflectionTop != null) {
                val target = (scrollState.value + reflectionTop - viewportTop).toInt()
                    .coerceIn(0, scrollState.maxValue)
                scrollState.animateScrollTo(target)
            } else if (allowBottomFallback) {
                scrollState.animateScrollTo(scrollState.maxValue)
            }
        }
    }

    fun copySection(section: RevealCopySection) {
        val text = viewModel.textForCopy(section) ?: return
        val label = when (section) {
            RevealCopySection.Writing -> writingClipboardLabel
            RevealCopySection.Reflection -> reflectionClipboardLabel
            RevealCopySection.ReflectionPrompt -> reflectionPromptClipboardLabel
        }
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        context.copyText(label, text)
        viewModel.markCopied(section)
        if (section == RevealCopySection.ReflectionPrompt) {
            reflectionPromptGuidanceVisible = true
        } else {
            copiedBurst = section
        }
    }

    fun openReflectionVeilPaywall() {
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        onOpenPaywall("reflection_veil")
    }

    // Entitlement can change while this screen lives (a mid-session
    // purchase wins) — re-read on appear and on every foreground return.
    LaunchedEffect(Unit) {
        viewModel.refreshEntitlement()
    }
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.refreshEntitlement()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    LaunchedEffect(
        startsReflectionOnAppear,
        state.reflection,
        state.canSubmitReflectionRequest,
        state.reflectionVeiled,
    ) {
        if (
            startsReflectionOnAppear &&
            !didAutoStartReflection &&
            state.reflection == null
        ) {
            when {
                state.canSubmitReflectionRequest -> {
                    didAutoStartReflection = true
                    didAnchorStreamingReflection = false
                    inlineReflectionActive = true
                    viewModel.askAnky()
                    scrollToReflection(allowBottomFallback = false)
                }
                state.reflectionVeiled -> {
                    // Free sessions never ask the mirror — the veil card is
                    // already standing where the reflection would appear.
                    didAutoStartReflection = true
                    scrollToReflection(allowBottomFallback = false)
                }
            }
        }
    }

    LaunchedEffect(copiedBurst) {
        val section = copiedBurst ?: return@LaunchedEffect
        delay(1_500)
        copiedBurst = null
        viewModel.clearCopied(section)
    }

    LaunchedEffect(state.copiedSection) {
        val section = state.copiedSection ?: return@LaunchedEffect
        if (section != RevealCopySection.ReflectionPrompt) return@LaunchedEffect
        delay(1_500)
        viewModel.clearCopied(section)
    }

    LaunchedEffect(state.error) {
        if (inlineReflectionActive && state.error != null) {
            scrollToReflection()
        }
    }

    LaunchedEffect(state.isAsking, state.streamingReflectionMarkdown) {
        if (state.isAsking || state.streamingReflectionMarkdown.isNotBlank()) {
            inlineReflectionActive = true
        }
    }

    LaunchedEffect(state.isAsking, inlineReflectionActive) {
        if (inlineReflectionActive && state.isAsking && !didAnchorStreamingReflection) {
            didAnchorStreamingReflection = true
            scrollToReflection()
        }
    }

    LaunchedEffect(state.streamingReflectionMarkdown.isNotBlank(), inlineReflectionActive) {
        if (inlineReflectionActive && state.streamingReflectionMarkdown.isNotBlank() && !didAnchorStreamingReflection) {
            didAnchorStreamingReflection = true
            scrollToReflection()
        }
    }

    LaunchedEffect(state.reflection?.hash, inlineReflectionActive) {
        if (inlineReflectionActive && state.reflection != null && !didAnchorStreamingReflection) {
            didAnchorStreamingReflection = true
            scrollToReflection()
        }
    }

    LaunchedEffect(state.isDeleted) {
        if (state.isDeleted) {
            onDeleted()
            onBack()
        }
    }

    // First-reflection review moment (iOS asks via requestReview once the
    // reader has actually reached the reflection).
    LaunchedEffect(isReflectionVisible, state.shouldRequestReviewAfterReadingFirstReflection) {
        if (
            isReflectionVisible &&
            state.shouldRequestReviewAfterReadingFirstReflection &&
            !didRequestFirstReflectionReview
        ) {
            didRequestFirstReflectionReview = true
            viewModel.markFirstReflectionReviewRequested()
            onRequestReview()
        }
    }

    LaunchedEffect(state.reflection?.hash, state.streamingReflectionMarkdown, inlineReflectionActive, state.error, state.reflectionVeiled) {
        if (
            state.reflection == null &&
            state.streamingReflectionMarkdown.isBlank() &&
            !state.reflectionVeiled &&
            !(inlineReflectionActive && state.error != null)
        ) {
            reflectionBounds = null
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(onBack) {
                var totalDragX = 0f
                detectHorizontalDragGestures(
                    onDragStart = { totalDragX = 0f },
                    onHorizontalDrag = { _, dragAmount -> totalDragX += dragAmount },
                    onDragEnd = {
                        if (totalDragX < -88.dp.toPx()) {
                            onBack()
                        }
                    },
                    onDragCancel = { totalDragX = 0f },
                )
            }
            .testTag("reveal-screen"),
    ) {
        LazureWall(mood = LazureMood.Dawn)
        Column(Modifier.fillMaxSize()) {
            RevealTopBar(
                title = artifact?.createdAt?.let {
                    DateTimeFormatter.ofPattern("h:mm a", Locale.getDefault()).withZone(ZoneId.systemDefault()).format(it)
                }.orEmpty(),
                copied = state.copiedSection == RevealCopySection.Writing ||
                    state.copiedSection == RevealCopySection.ReflectionPrompt,
                canCopyReflectionPrompt = artifact?.isComplete == true,
                onBack = onBack,
                canDelete = artifact != null,
                isDeleting = state.isDeleting,
                copyWritingContentDescription = labels.copyWriting,
                copyReflectionPromptHint = labels.copyReflectionPromptHint,
                deleteContentDescription = labels.deleteWritingSession,
                onCopyWriting = { copySection(RevealCopySection.Writing) },
                onCopyReflectionPrompt = { copySection(RevealCopySection.ReflectionPrompt) },
                onDelete = {
                    view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                    confirmDelete = true
                },
            )
            if (artifact == null) {
                Text(
                    "this .anky could not be found.",
                    style = AnkyType.Body.copy(color = RevealLazure.inkSoft),
                    modifier = Modifier.fillMaxWidth().padding(28.dp),
                    textAlign = TextAlign.Center,
                )
                return@Column
            }
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .onGloballyPositioned { scrollViewportBounds = it.boundsInRoot() }
                    .verticalScroll(scrollState)
                    .padding(horizontal = 28.dp)
                    .padding(top = 20.dp, bottom = 138.dp),
                verticalArrangement = Arrangement.spacedBy(0.dp),
            ) {
                WritingSessionStatsHeader(
                    wordCount = wordCountNumber(artifact.reconstructedText),
                    duration = AnkyDuration.formatted(artifact.durationMs),
                    backspaceCount = artifact.inputStats.backspaceCount,
                    enterCount = artifact.inputStats.enterCount,
                    modifier = Modifier.padding(bottom = 14.dp),
                )
                SelectionContainer {
                    Text(
                        text = artifact.reconstructedText,
                        style = AnkyType.Writing.copy(
                            fontFamily = FontFamily.Serif,
                            color = RevealLazure.ink,
                        ),
                        modifier = Modifier
                            .padding(vertical = 8.dp)
                            .testTag("reconstructed-text"),
                    )
                }
                PrivacyDivider(labels.privacyNote, labels.togglePrivacyMessage, Modifier.padding(top = 34.dp))

                when {
                    state.reflection != null -> {
                        Column(
                            modifier = Modifier
                                .padding(top = 36.dp)
                                .onGloballyPositioned { reflectionBounds = it.boundsInRoot() },
                            verticalArrangement = Arrangement.spacedBy(18.dp),
                        ) {
                            SavedReflectionPanel(reflection = state.reflection)
                            ReflectionTags(tags = state.reflection.tags, onOpenTag = onOpenTag)
                        }
                    }
                    state.streamingReflectionMarkdown.isNotBlank() -> {
                        StreamingReflectionPanel(
                            markdown = state.streamingReflectionMarkdown,
                            modifier = Modifier
                                .padding(top = 36.dp)
                                .onGloballyPositioned { reflectionBounds = it.boundsInRoot() },
                        )
                    }
                    state.isAsking -> {
                        ReflectionProgressPanel(
                            state = state,
                            labels = labels,
                            modifier = Modifier
                                .padding(top = 36.dp)
                                .onGloballyPositioned { reflectionBounds = it.boundsInRoot() },
                        )
                    }
                    state.reflectionVeiled -> {
                        // Where the reflection would bloom, the veil — the
                        // same card, misted, one tap from the paywall.
                        VeiledFeature(
                            surface = "reflection",
                            message = AnkyCopyRegistry.veilReflection,
                            onTap = { openReflectionVeilPaywall() },
                            modifier = Modifier
                                .padding(top = 36.dp)
                                .fillMaxWidth()
                                .height(240.dp)
                                .onGloballyPositioned { reflectionBounds = it.boundsInRoot() }
                                .testTag("reflection-veil"),
                        ) {
                            ReflectionGhost()
                        }
                    }
                    inlineReflectionActive && state.error != null -> {
                        ReflectionErrorPanel(
                            message = localizedRevealError(state.error),
                            title = labels.mirrorDidNotOpen,
                            modifier = Modifier
                                .padding(top = 36.dp)
                                .onGloballyPositioned { reflectionBounds = it.boundsInRoot() },
                        )
                    }
                }
            }
        }
        if (copiedBurst != null) {
            Text(
                when (copiedBurst) {
                    RevealCopySection.Reflection -> stringResource(R.string.copied_reflection)
                    RevealCopySection.ReflectionPrompt -> labels.reflectionPromptCopied
                    else -> labels.copiedWriting
                },
                style = AnkyType.Mono.copy(color = RevealLazure.ink, fontWeight = FontWeight.Bold),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 120.dp, end = 28.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(RevealLazure.paperDeep.copy(alpha = 0.94f))
                    .border(1.dp, RevealLazure.gold.copy(alpha = 0.72f), RoundedCornerShape(6.dp))
                    .padding(horizontal = 10.dp, vertical = 8.dp),
            )
        }
        if (reflectionPromptGuidanceVisible) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
                AnkyConversationPrompt(
                    message = labels.reflectionPromptClipboardGuidance,
                    onClose = { reflectionPromptGuidanceVisible = false },
                    modifier = Modifier.padding(start = 28.dp, end = 28.dp, bottom = 104.dp),
                )
            }
        }
        RevealEdgeBackSwipe(onBack = onBack, modifier = Modifier.align(Alignment.CenterStart))
        if (shouldShowBottomAction) {
            RevealBottomActionButton(
                title = bottomActionTitle(state, labels),
                isLoading = state.isAsking,
                isEnabled = bottomActionIsEnabled(state),
                onClick = {
                    when {
                        state.reflection != null -> {
                            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                            scrollToReflection(allowBottomFallback = false)
                        }
                        state.reflectionVeiled -> {
                            openReflectionVeilPaywall()
                        }
                        artifact.isComplete -> {
                            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                            didAnchorStreamingReflection = false
                            inlineReflectionActive = true
                            viewModel.askAnky()
                            scrollToReflection(allowBottomFallback = false)
                        }
                        else -> onTryAgain(artifact)
                    }
                },
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 24.dp, vertical = 22.dp),
            )
        }
        if (confirmDelete) {
            AlertDialog(
                onDismissRequest = { confirmDelete = false },
                title = { Text(labels.deleteWritingSessionQuestion) },
                text = {
                    Text(labels.deleteWritingSessionBody)
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            confirmDelete = false
                            viewModel.deleteSession()
                        },
                    ) {
                        Text(labels.delete)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { confirmDelete = false }) {
                        Text(labels.cancel)
                    }
                },
                containerColor = RevealLazure.paper,
                titleContentColor = RevealLazure.ink,
                textContentColor = RevealLazure.inkSoft,
            )
        }
    }
}

private data class RevealLabels(
    val privacyNote: String,
    val copyWriting: String,
    val copyReflectionPromptHint: String,
    val reflectionPromptCopied: String,
    val reflectionPromptClipboardGuidance: String,
    val deleteWritingSession: String,
    val deleteWritingSessionQuestion: String,
    val delete: String,
    val cancel: String,
    val deleteWritingSessionBody: String,
    val togglePrivacyMessage: String,
    val readReflection: String,
    val reflectThisAnky: String,
    val seeWhatAnkySaw: String,
    val continueWritingLeft: (String) -> String,
    val copiedWriting: String,
    val receivingReflection: String,
    val writeMinutes: String,
    val mirrorDidNotOpen: String,
    val mirrorForming: String,
    val ankyDrawingThread: (Int) -> String,
    val ankyReading: String,
    val sheetTags: String,
    val statusOpeningQuietChannel: String,
    val statusPreparingReflection: String,
    val statusCarryingThread: String,
    val statusFoundWriterKey: String,
    val statusThreadingBack: String,
    val statusAlreadyHoldingThread: String,
    val statusWaitingWithMirror: String,
    val statusWritingReflection: (Int) -> String,
    val progressOpeningMirror: String,
    val progressReceivedWriting: String,
    val progressReadingAnky: String,
    val progressPreparingWriting: String,
    val progressOpeningWay: String,
    val progressValidatingRitual: String,
    val progressPreparingReflection: String,
    val progressAnkyWriting: String,
    val progressBringingBack: String,
    val progressOpeningScroll: String,
    val progressAnkyWorking: String,
    val progressComplete: String,
    val progressReceiving: String,
    val progressChars: (Int) -> String,
)

@Composable
private fun revealLabels(): RevealLabels {
    val context = LocalContext.current
    return RevealLabels(
        privacyNote = stringResource(R.string.reveal_privacy_note),
        copyWriting = stringResource(R.string.copy_writing),
        copyReflectionPromptHint = stringResource(R.string.copy_reflection_prompt_hint),
        reflectionPromptCopied = stringResource(R.string.reflection_prompt_copied),
        reflectionPromptClipboardGuidance = stringResource(R.string.reflection_prompt_clipboard_guidance),
        deleteWritingSession = stringResource(R.string.delete_writing_session),
        deleteWritingSessionQuestion = stringResource(R.string.delete_writing_session_question),
        delete = stringResource(R.string.delete),
        cancel = stringResource(R.string.cancel_title),
        deleteWritingSessionBody = stringResource(R.string.delete_writing_session_body),
        togglePrivacyMessage = stringResource(R.string.reveal_toggle_privacy_message),
        readReflection = stringResource(R.string.read_reflection),
        reflectThisAnky = stringResource(R.string.reflect_this_anky),
        seeWhatAnkySaw = stringResource(R.string.reveal_see_what_anky_saw),
        continueWritingLeft = { remaining -> context.getString(R.string.continue_writing_left, remaining) },
        copiedWriting = stringResource(R.string.copied_writing),
        receivingReflection = stringResource(R.string.receiving_reflection),
        writeMinutes = stringResource(R.string.write_minutes_caps, AnkyDuration.CompleteRitualMinutes),
        mirrorDidNotOpen = stringResource(R.string.mirror_did_not_open),
        mirrorForming = stringResource(R.string.reveal_mirror_forming),
        ankyDrawingThread = { count -> context.getString(R.string.reveal_anky_drawing_thread, count) },
        ankyReading = stringResource(R.string.reveal_anky_reading),
        sheetTags = stringResource(R.string.reveal_sheet_tags),
        statusOpeningQuietChannel = stringResource(R.string.reveal_status_opening_quiet_channel),
        statusPreparingReflection = stringResource(R.string.reveal_status_preparing_reflection),
        statusCarryingThread = stringResource(R.string.reveal_status_carrying_thread),
        statusFoundWriterKey = stringResource(R.string.reveal_status_found_writer_key),
        statusThreadingBack = stringResource(R.string.reveal_status_threading_back),
        statusAlreadyHoldingThread = stringResource(R.string.reveal_status_already_holding_thread),
        statusWaitingWithMirror = stringResource(R.string.reveal_status_waiting_with_mirror),
        statusWritingReflection = { count -> context.getString(R.string.reveal_status_writing_reflection, count) },
        progressOpeningMirror = stringResource(R.string.reveal_progress_opening_mirror),
        progressReceivedWriting = stringResource(R.string.reveal_progress_received_writing),
        progressReadingAnky = stringResource(R.string.reveal_progress_reading_anky),
        progressPreparingWriting = stringResource(R.string.reveal_progress_preparing_writing),
        progressOpeningWay = stringResource(R.string.reveal_progress_opening_way),
        progressValidatingRitual = stringResource(R.string.reveal_progress_validating_ritual),
        progressPreparingReflection = stringResource(R.string.reveal_progress_preparing_reflection),
        progressAnkyWriting = stringResource(R.string.reveal_progress_anky_writing),
        progressBringingBack = stringResource(R.string.reveal_progress_bringing_back),
        progressOpeningScroll = stringResource(R.string.reveal_progress_opening_scroll),
        progressAnkyWorking = stringResource(R.string.reveal_progress_anky_working),
        progressComplete = stringResource(R.string.reveal_progress_complete),
        progressReceiving = stringResource(R.string.reveal_progress_receiving),
        progressChars = { count -> context.getString(R.string.reveal_progress_chars, count) },
    )
}

@Composable
private fun RevealEdgeBackSwipe(onBack: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxHeight()
            .width(32.dp)
            .pointerInput(onBack) {
                var totalDrag = Offset.Zero
                detectDragGestures(
                    onDragStart = {
                        totalDrag = Offset.Zero
                    },
                    onDrag = { _, dragAmount ->
                        totalDrag += dragAmount
                    },
                    onDragEnd = {
                        val isHorizontalBackSwipe = totalDrag.x > 80.dp.toPx() && abs(totalDrag.y) < 60.dp.toPx()
                        if (isHorizontalBackSwipe) {
                            onBack()
                        }
                    },
                    onDragCancel = {
                        totalDrag = Offset.Zero
                    },
                )
            },
    )
}

@Composable
private fun RevealTopBar(
    title: String,
    copied: Boolean,
    canCopyReflectionPrompt: Boolean,
    onBack: () -> Unit,
    canDelete: Boolean,
    isDeleting: Boolean,
    copyWritingContentDescription: String,
    copyReflectionPromptHint: String,
    deleteContentDescription: String,
    onCopyWriting: () -> Unit,
    onCopyReflectionPrompt: () -> Unit,
    onDelete: () -> Unit,
) {
    val backLabel = stringResource(R.string.back)
    Column(Modifier.fillMaxWidth().background(RevealLazure.paper.copy(alpha = 0.94f))) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(58.dp)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier.size(44.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.ChevronLeft,
                    contentDescription = backLabel,
                    tint = RevealLazure.ink,
                    modifier = Modifier.size(24.dp),
                )
            }
            Text(
                title,
                style = AnkyType.Body.copy(
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = RevealLazure.ink,
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
            )
            Icon(
                imageVector = if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy,
                contentDescription = "$copyWritingContentDescription. $copyReflectionPromptHint",
                tint = if (copied) RevealLazure.success else RevealLazure.ink,
                modifier = Modifier
                    .size(44.dp)
                    .padding(9.dp)
                    .pointerInput(canCopyReflectionPrompt) {
                        detectTapGestures(
                            onTap = { onCopyWriting() },
                            onLongPress = {
                                if (canCopyReflectionPrompt) onCopyReflectionPrompt()
                            },
                        )
                    },
            )
            if (canDelete) {
                IconButton(
                    onClick = onDelete,
                    enabled = !isDeleting,
                    modifier = Modifier.size(44.dp),
                ) {
                    if (isDeleting) {
                        CircularProgressIndicator(
                            color = RevealLazure.ink,
                            strokeWidth = 2.dp,
                            modifier = Modifier.size(18.dp),
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Filled.Delete,
                            contentDescription = deleteContentDescription,
                            tint = LazurePigments.ankyMadder.copy(alpha = 0.88f),
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            } else {
                Spacer(Modifier.size(44.dp))
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(LazurePigments.hairline))
    }
}

@Composable
private fun WritingSessionStatsHeader(
    wordCount: Int,
    duration: String,
    backspaceCount: Int,
    enterCount: Int,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        WritingSessionStat(Icons.Filled.TextFields, wordCount.toString())
        WritingSessionStat(Icons.Filled.Timer, duration)
        WritingSessionStat(Icons.Filled.Backspace, backspaceCount.toString())
        WritingSessionStat(Icons.Filled.KeyboardReturn, enterCount.toString())
    }
}

@Composable
private fun WritingSessionStat(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    value: String,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = RevealLazure.ink.copy(alpha = 0.44f),
            modifier = Modifier.size(13.dp),
        )
        Text(
            value,
            style = AnkyType.Mono.copy(
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = RevealLazure.ink.copy(alpha = 0.44f),
            ),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun PrivacyDivider(note: String, toggleContentDescription: String, modifier: Modifier = Modifier) {
    var expanded by remember { mutableStateOf(false) }
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            modifier = Modifier.clickable { expanded = !expanded },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.weight(1f).height(1.dp).background(RevealLazure.gold.copy(alpha = 0.22f)))
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(RevealLazure.paperDeep.copy(alpha = 0.55f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Lock,
                    contentDescription = toggleContentDescription,
                    tint = RevealLazure.goldSoft,
                    modifier = Modifier.size(17.dp),
                )
            }
            Box(Modifier.weight(1f).height(1.dp).background(RevealLazure.gold.copy(alpha = 0.22f)))
        }
        if (expanded) {
            Text(
                note,
                style = AnkyType.Caption.copy(color = RevealLazure.ink.copy(alpha = 0.62f), fontWeight = FontWeight.Normal),
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun SavedReflectionPanel(
    reflection: LocalReflection,
    modifier: Modifier = Modifier,
) {
    val title = if (reflection.title == "Imported reflection") {
        stringResource(R.string.imported_reflection_title)
    } else {
        reflection.title
    }
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            title,
            style = AnkyType.Heading.copy(
                fontFamily = FontFamily.Serif,
                fontSize = 23.sp,
                fontWeight = FontWeight.Bold,
                color = RevealLazure.heading,
            ),
            modifier = Modifier.testTag("saved-reflection-title"),
        )
        SelectionContainer {
            MarkdownishText(reflection.displayBody)
        }
    }
}

@Composable
private fun StreamingReflectionPanel(
    markdown: String,
    modifier: Modifier = Modifier,
) {
    val title = markdown.firstMarkdownHeadingText()
    val body = title?.let(markdown::removingLeadingMarkdownHeading) ?: markdown
    Column(modifier = modifier.alpha(0.92f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (!title.isNullOrBlank()) {
            Text(
                title,
                style = AnkyType.Heading.copy(
                    fontFamily = FontFamily.Serif,
                    fontSize = 23.sp,
                    fontWeight = FontWeight.Bold,
                    color = RevealLazure.heading,
                ),
            )
        }
        SelectionContainer {
            MarkdownishText(body)
        }
    }
}

@Composable
private fun ReflectionProgressPanel(
    state: RevealState,
    labels: RevealLabels,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // The watercolor veil breathes while anky reads — same wait as the
        // ceremony, never a spinner.
        WatercolorVeil(
            message = AnkyCopyRegistry.reflectionWait,
            register = WatercolorVeilRegister.Pale,
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(RevealLazure.paperDeep.copy(alpha = 0.30f)),
        )
        MirrorProgress(
            status = localizedReflectionStatus(state.reflectionStatusMessage, labels),
            generatedCharacters = state.streamingReflectionCharacterCount,
            labels = labels,
        )
    }
}

@Composable
private fun ReflectionErrorPanel(
    message: String?,
    title: String,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            title,
            style = AnkyType.Heading.copy(
                fontFamily = FontFamily.Serif,
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = RevealLazure.heading,
            ),
        )
        Text(
            message.orEmpty(),
            style = AnkyType.Mono.copy(fontSize = 13.sp, lineHeight = 18.sp, color = RevealLazure.danger.copy(alpha = 0.82f)),
        )
    }
}

@Composable
private fun ReflectionTags(tags: List<String>, onOpenTag: (String) -> Unit) {
    if (tags.isEmpty()) return
    val tagScrollState = rememberScrollState()
    val labels = revealLabels()
    Column(modifier = Modifier.padding(top = 2.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            labels.sheetTags,
            style = AnkyType.Mono.copy(
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = RevealLazure.inkSoft.copy(alpha = 0.72f),
                letterSpacing = 1.sp,
            ),
        )
        Row(
            modifier = Modifier.horizontalScroll(tagScrollState),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            tags.forEach { tag ->
                Text(
                    tag,
                    style = AnkyType.Mono.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = RevealLazure.gold),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .clip(CircleShape)
                        .clickable { onOpenTag(tag) }
                        .background(RevealLazure.paperDeep.copy(alpha = 0.55f))
                        .border(1.dp, RevealLazure.gold.copy(alpha = 0.3f), CircleShape)
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                )
            }
        }
    }
}

@Composable
private fun RevealBottomActionButton(
    title: String,
    isLoading: Boolean,
    isEnabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val transition = rememberInfiniteTransition(label = "reveal-cta")
    val breath by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 2800, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "reveal-cta-breath",
    )
    val enabledOrLoading = isEnabled || isLoading
    val shape = RoundedCornerShape(percent = 50)
    val scale = if (enabledOrLoading) 1f + breath * 0.005f else 1f
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(64.dp)
            .scale(scale)
            .alpha(if (enabledOrLoading) 1f else 0.52f)
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(
                        LazurePigments.ankyViolet.copy(alpha = 0.96f),
                        LazurePigments.ankyInk.copy(alpha = 0.98f),
                    ),
                ),
            )
            .border(
                BorderStroke(
                    width = if (isLoading) 1.8.dp else 1.2.dp,
                    brush = Brush.linearGradient(
                        listOf(
                            LazurePigments.ankyGoldLight.copy(alpha = 0.8f),
                            LazurePigments.ankyViolet.copy(alpha = 0.6f),
                            LazurePigments.ankyGold.copy(alpha = 0.8f),
                        ),
                    ),
                ),
                shape,
            )
            .clickable(enabled = isEnabled, onClick = onClick)
            .padding(horizontal = 22.dp),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.matchParentSize()) {
            drawRoundRect(
                color = LazurePigments.ankyGoldLight.copy(alpha = if (isLoading) 0.22f else 0.08f + breath * 0.08f),
                size = size,
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2f, size.height / 2f),
                style = Stroke(width = 3.dp.toPx()),
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (isLoading) {
                CircularProgressIndicator(
                    color = LazurePigments.ankyPaper,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(18.dp),
                )
            }
            Text(
                title,
                style = AnkyType.Heading.copy(
                    fontFamily = FontFamily.Serif,
                    fontSize = 19.sp,
                    fontWeight = FontWeight.Medium,
                    color = LazurePigments.ankyPaper,
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
        }
    }
}

private fun bottomActionTitle(state: RevealState, labels: RevealLabels): String =
    when {
        state.isAsking -> labels.receivingReflection
        state.reflection != null -> labels.readReflection
        state.reflectionVeiled -> labels.seeWhatAnkySaw
        state.artifact?.isComplete == true -> labels.reflectThisAnky
        state.canContinueWriting -> labels.continueWritingLeft(state.remainingWritingTime)
        else -> labels.writeMinutes
    }

private fun bottomActionIsEnabled(state: RevealState): Boolean =
    when {
        state.isAsking -> false
        state.reflection != null -> true
        state.reflectionVeiled -> true
        state.artifact?.isComplete == true -> state.canSubmitReflectionRequest
        else -> true
    }

@Composable
private fun MirrorProgress(status: String, generatedCharacters: Int, labels: RevealLabels) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val statusLine = if (generatedCharacters > 0) {
            labels.ankyDrawingThread(generatedCharacters)
        } else {
            status.ifBlank { labels.ankyReading }
        }
        MirrorThreadProgress(
            progress = mirrorThreadProgress(generatedCharacters),
            generatedCharacters = generatedCharacters,
        )
        Text(
            statusLine,
            style = AnkyType.Mono.copy(fontSize = 13.sp, color = RevealLazure.ink.copy(alpha = 0.74f)),
        )
    }
}

@Composable
private fun MirrorThreadProgress(progress: Float, generatedCharacters: Int, isComplete: Boolean = false) {
    val labels = revealLabels()
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(RevealLazure.paperDeep.copy(alpha = 0.72f))
                .border(1.dp, RevealLazure.gold.copy(alpha = 0.22f), RoundedCornerShape(3.dp)),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(progress.coerceIn(0f, 1f))
                    .height(10.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(
                        Brush.horizontalGradient(
                            listOf(
                                RevealLazure.gold.copy(alpha = 0.72f),
                                LazurePigments.ankyGoldLight.copy(alpha = 0.66f),
                                RevealLazure.gold.copy(alpha = 0.84f),
                            ),
                        ),
                    ),
            )
        }
        Row(Modifier.fillMaxWidth()) {
            Text(
                if (isComplete) labels.progressComplete else labels.progressReceiving,
                style = AnkyType.Caption.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = RevealLazure.inkSoft.copy(alpha = 0.82f)),
            )
            Spacer(Modifier.weight(1f))
            Text(
                labels.progressChars(generatedCharacters),
                style = AnkyType.Caption.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = RevealLazure.inkSoft.copy(alpha = 0.82f)),
            )
        }
    }
}

internal fun mirrorThreadProgress(generatedCharacters: Int, isComplete: Boolean = false): Float {
    if (isComplete) return 1f
    if (generatedCharacters <= 0) return 0.08f
    return (0.12f + generatedCharacters.toFloat() / 3200f).coerceAtMost(0.92f)
}

/**
 * Lazure role remap for the reading room, mirroring the iOS RevealPalette:
 * the surface is paper, the words are ink, headings are violet, the one
 * warning pigment is madder.
 */
private object RevealLazure {
    val paper = LazurePigments.ankyPaper
    val paperDeep = LazurePigments.ankyPaperDeep
    val ink = LazurePigments.ankyInk
    val inkSoft = LazurePigments.ankyInkSoft
    val heading = LazurePigments.ankyViolet
    val gold = LazurePigments.ankyGold
    val goldSoft = LazurePigments.ankyGold.copy(alpha = 0.82f)
    val danger = LazurePigments.ankyMadder
    val success = LazurePigments.ankySage
}

@Composable
private fun localizedRevealError(message: String?): String =
    when (message?.trim().orEmpty()) {
        "" -> ""
        "Anky could not return a reflection right now." -> stringResource(R.string.reveal_error_return_reflection)
        "This writing session could not be deleted." -> stringResource(R.string.reveal_delete_session_failed)
        "The mirror URL is not valid." -> stringResource(R.string.reveal_error_invalid_mirror_url)
        "The mirror returned an invalid response." -> stringResource(R.string.reveal_error_invalid_mirror_response)
        "The mirror response did not match this .anky." -> stringResource(R.string.reveal_error_hash_mismatch)
        else -> stringResource(R.string.reveal_error_return_reflection)
    }

private fun localizedReflectionStatus(status: String, labels: RevealLabels): String {
    val trimmed = status.trim()
    val writingMatch = Regex("""writing the reflection\.\.\. (\d+) characters""").matchEntire(trimmed)
    if (writingMatch != null) {
        return labels.statusWritingReflection(writingMatch.groupValues[1].toIntOrNull() ?: 0)
    }
    return when (trimmed) {
        "" -> ""
        "i am waiting with the mirror.",
        "i am still waiting with the mirror." -> labels.statusWaitingWithMirror
        "i am opening a quiet channel." -> labels.statusOpeningQuietChannel
        "i am preparing your reflection." -> labels.statusPreparingReflection
        "i found your writer key. staying close." -> labels.statusFoundWriterKey
        "i am carrying the thread to the mirror." -> labels.statusCarryingThread
        "something answered. i am threading it back." -> labels.statusThreadingBack
        "the mirror is already holding this thread." -> labels.statusAlreadyHoldingThread
        "opening the mirror..." -> labels.progressOpeningMirror
        "received your writing..." -> labels.progressReceivedWriting
        "reading your .anky..." -> labels.progressReadingAnky
        "preparing your writing..." -> labels.progressPreparingWriting
        "opening the way..." -> labels.progressOpeningWay
        "validating the ritual..." -> labels.progressValidatingRitual
        "preparing the reflection..." -> labels.progressPreparingReflection
        "anky is writing..." -> labels.progressAnkyWriting
        "bringing it back..." -> labels.progressBringingBack
        "opening the scroll..." -> labels.progressOpeningScroll
        "anky is working..." -> labels.progressAnkyWorking
        else -> trimmed
    }
}

private fun wordCountNumber(text: String): Int =
    text.splitToSequence(Regex("\\s+")).filter { it.isNotBlank() }.count()

private fun Context.copyText(label: String, text: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

@Composable
private fun MarkdownishText(text: String) {
    SelectionContainer {
        Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
            text.replace("\r\n", "\n").lines().forEach { line ->
                MarkdownLine(line)
            }
        }
    }
}

@Composable
private fun MarkdownLine(line: String) {
    val trimmed = line.trim()
    val numbered = numberedText(trimmed)
    val bodyStyle = AnkyType.Body.copy(fontFamily = FontFamily.Serif, color = RevealLazure.inkSoft)

    when {
        trimmed.isEmpty() -> Spacer(Modifier.height(12.dp))
        isMarkdownHorizontalRule(trimmed) -> Box(
            Modifier
                .fillMaxWidth()
                .padding(top = 12.dp, bottom = 12.dp)
                .height(1.dp)
                .background(RevealLazure.gold.copy(alpha = 0.22f)),
        )
        headingText(trimmed) != null -> Text(
            inlineMarkdown(headingText(trimmed)!!),
            style = AnkyType.Heading.copy(
                fontFamily = FontFamily.Serif,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = RevealLazure.heading,
            ),
            modifier = Modifier.padding(top = 4.dp, bottom = 5.dp),
        )
        trimmed.startsWith(">") -> Row(
            modifier = Modifier
                .height(IntrinsicSize.Min)
                .padding(top = 6.dp, bottom = 3.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Box(Modifier.width(2.dp).fillMaxHeight().background(RevealLazure.gold.copy(alpha = 0.36f)))
            Text(
                inlineMarkdown(trimmed.drop(1).trim()),
                style = bodyStyle.copy(
                    color = RevealLazure.inkSoft.copy(alpha = 0.80f),
                    fontStyle = FontStyle.Italic,
                ),
            )
        }
        trimmed.startsWith("- ") || trimmed.startsWith("* ") -> MarkdownListRow("•", trimmed.drop(2))
        numbered != null -> MarkdownListRow(numbered.first, numbered.second)
        else -> Text(
            inlineMarkdown(trimmed),
            style = bodyStyle,
            modifier = Modifier.padding(vertical = 2.dp),
        )
    }
}

@Composable
private fun MarkdownListRow(marker: String, body: String) {
    Row(
        modifier = Modifier.padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(marker, style = AnkyType.Body.copy(fontFamily = FontFamily.Serif, color = RevealLazure.gold.copy(alpha = 0.72f)))
        Text(inlineMarkdown(body), style = AnkyType.Body.copy(fontFamily = FontFamily.Serif, color = RevealLazure.inkSoft))
    }
}

private fun headingText(line: String): String? =
    listOf("### ", "## ", "# ").firstOrNull { line.startsWith(it) }?.let { line.drop(it.length) }

internal fun isMarkdownHorizontalRule(line: String): Boolean {
    if (line == "---" || line == "***" || line == "___" || line == "—") return true
    if (line.length > 5 || line.isEmpty()) return false
    return line.all { it == '-' || it == '*' || it == '_' || it == '—' }
}

private fun numberedText(line: String): Pair<String, String>? {
    val dotIndex = line.indexOf('.')
    if (dotIndex <= 0 || dotIndex + 1 >= line.length || line[dotIndex + 1] != ' ') return null
    val marker = line.take(dotIndex)
    if (!marker.all(Char::isDigit)) return null
    return "${marker}." to line.drop(dotIndex + 2)
}

private fun inlineMarkdown(text: String) = buildAnnotatedString {
    var index = 0
    while (index < text.length) {
        when {
            text.startsWith("**", index) -> {
                val end = text.indexOf("**", startIndex = index + 2)
                if (end >= 0) {
                    withStyle(SpanStyle(color = LazurePigments.ankyInk, fontWeight = FontWeight.SemiBold)) {
                        append(text.substring(index + 2, end))
                    }
                    index = end + 2
                } else {
                    append(text[index])
                    index += 1
                }
            }
            text[index] == '`' -> {
                val end = text.indexOf('`', startIndex = index + 1)
                if (end >= 0) {
                    withStyle(
                        SpanStyle(
                            color = LazurePigments.ankyInk.copy(alpha = 0.82f),
                            fontFamily = FontFamily.Monospace,
                            fontSize = 15.sp,
                        ),
                    ) {
                        append(text.substring(index + 1, end))
                    }
                    index = end + 1
                } else {
                    append(text[index])
                    index += 1
                }
            }
            text[index] == '*' -> {
                val end = text.indexOf('*', startIndex = index + 1)
                if (end >= 0) {
                    withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                        append(text.substring(index + 1, end))
                    }
                    index = end + 1
                } else {
                    append(text[index])
                    index += 1
                }
            }
            else -> {
                val nextStrong = text.indexOf("**", startIndex = index).takeIf { it >= 0 } ?: text.length
                val nextCode = text.indexOf('`', startIndex = index).takeIf { it >= 0 } ?: text.length
                val nextEmphasis = text.indexOf('*', startIndex = index).takeIf { it >= 0 } ?: text.length
                val next = minOf(nextStrong, nextCode, nextEmphasis)
                append(text.substring(index, next))
                index = next
            }
        }
    }
}

private val LocalReflection.displayBody: String
    get() = reflection.removingLeadingMarkdownHeading(title)

private fun String.removingLeadingMarkdownHeading(title: String): String {
    val lines = replace("\r\n", "\n").lines()
    val headingIndex = lines.indexOfFirst { it.trim().isNotEmpty() }
    if (headingIndex < 0) return this
    val heading = markdownHeadingText(lines[headingIndex]) ?: return this
    if (heading.trim().lowercase() != title.trim().lowercase()) return this
    val bodyStart = lines.drop(headingIndex + 1).indexOfFirst { it.trim().isNotEmpty() }
    if (bodyStart < 0) return ""
    return lines.drop(headingIndex + 1 + bodyStart).joinToString("\n")
}

private fun markdownHeadingText(line: String): String? {
    val trimmed = line.trim()
    return listOf("### ", "## ", "# ").firstOrNull { trimmed.startsWith(it) }?.let { trimmed.drop(it.length) }
}

private fun String.firstMarkdownHeadingText(): String? {
    val line = replace("\r\n", "\n").lineSequence().firstOrNull { it.trim().isNotEmpty() } ?: return null
    return markdownHeadingText(line)
}
