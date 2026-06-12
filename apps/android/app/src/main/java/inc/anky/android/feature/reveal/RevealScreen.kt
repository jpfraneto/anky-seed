package inc.anky.android.feature.reveal

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.KeyboardReturn
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.Backspace
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.testTag
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.R
import inc.anky.android.core.credits.CreditPackage
import inc.anky.android.core.mirror.ReflectionCreditPromptState
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.ui.components.AnkyChatAction
import inc.anky.android.ui.components.AnkyConversationPrompt
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RevealScreen(
    viewModel: RevealViewModel,
    startsReflectionOnAppear: Boolean = false,
    onOpenTag: (String) -> Unit = {},
    onOpenCredits: () -> Unit = {},
    onBack: () -> Unit,
    onDeleted: () -> Unit = {},
    onTryAgain: (SavedAnky) -> Unit = {},
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val density = LocalDensity.current
    val view = LocalView.current
    val artifact = state.artifact
    val scrollState = rememberScrollState()
    val scope = rememberCoroutineScope()
    var confirmDelete by remember { mutableStateOf(false) }
    var copiedBurst by remember { mutableStateOf<RevealCopySection?>(null) }
    var inlineReflectionActive by remember { mutableStateOf(false) }
    var didAutoStartReflection by remember { mutableStateOf(false) }
    var didAnchorStreamingReflection by remember { mutableStateOf(false) }
    var showCreditPurchaseSheet by remember { mutableStateOf(false) }
    var reflectionPromptGuidanceVisible by remember { mutableStateOf(false) }
    var scrollViewportBounds by remember { mutableStateOf<Rect?>(null) }
    var reflectionBounds by remember { mutableStateOf<Rect?>(null) }
    val creditPurchaseSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
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
        state.streamingReflectionMarkdown.isBlank() &&
        !isReflectionVisible

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

    LaunchedEffect(Unit) {
        viewModel.refreshCredits(showError = false)
    }

    LaunchedEffect(
        startsReflectionOnAppear,
        state.reflection,
        state.canSubmitReflectionRequest,
        state.needsCreditsToReflect,
        state.creditsLoading,
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
                state.needsCreditsToReflect -> {
                    didAutoStartReflection = true
                    showCreditPurchaseSheet = true
                    viewModel.refreshCredits(showError = false)
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

    LaunchedEffect(
        state.streamingReflectionMarkdown.firstMarkdownHeadingText(),
        inlineReflectionActive,
    ) {
        val hasTitle = !state.streamingReflectionMarkdown.firstMarkdownHeadingText().isNullOrBlank()
        if (inlineReflectionActive && hasTitle && !didAnchorStreamingReflection) {
            didAnchorStreamingReflection = true
            scrollToReflection(allowBottomFallback = false)
        }
    }

    LaunchedEffect(state.isDeleted) {
        if (state.isDeleted) {
            onDeleted()
            onBack()
        }
    }

    LaunchedEffect(state.reflection?.hash, state.streamingReflectionMarkdown, inlineReflectionActive, state.error) {
        if (
            state.reflection == null &&
            state.streamingReflectionMarkdown.isBlank() &&
            !(inlineReflectionActive && state.error != null)
        ) {
            reflectionBounds = null
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AnkyColors.Ink)
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
        RevealTexture()
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
                    style = AnkyType.Body.copy(color = AnkyColors.PaperMuted),
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
                    backspaceCount = 0,
                    enterCount = artifact.reconstructedText.count { it == '\n' },
                    modifier = Modifier.padding(bottom = 14.dp),
                )
                SelectionContainer {
                    Text(
                        text = artifact.reconstructedText,
                        style = AnkyType.Body,
                        modifier = Modifier
                            .padding(vertical = 8.dp)
                            .testTag("reconstructed-text"),
                    )
                }
                PrivacyDivider(labels.privacyNote, labels.togglePrivacyMessage, Modifier.padding(top = 34.dp))

                when {
                    state.reflection != null -> {
                        SavedReflectionPanel(
                            reflection = state.reflection,
                            modifier = Modifier
                                .padding(top = 36.dp)
                                .onGloballyPositioned { reflectionBounds = it.boundsInRoot() },
                        )
                    }
                    state.streamingReflectionMarkdown.isNotBlank() -> {
                        StreamingReflectionPanel(
                            markdown = state.streamingReflectionMarkdown,
                            modifier = Modifier
                                .padding(top = 36.dp)
                                .onGloballyPositioned { reflectionBounds = it.boundsInRoot() },
                        )
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
                style = AnkyType.Mono.copy(color = AnkyColors.Paper, fontWeight = FontWeight.Bold),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 120.dp, end = 28.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color(0xFF120F0B).copy(alpha = 0.92f))
                    .border(1.dp, AnkyColors.Gold.copy(alpha = 0.72f), RoundedCornerShape(6.dp))
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
                subtitle = bottomActionSubtitle(state, labels),
                isLoading = state.isAsking,
                isEnabled = bottomActionIsEnabled(state),
                onClick = {
                    when {
                        state.reflection != null -> {
                            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                            scrollToReflection(allowBottomFallback = false)
                        }
                        state.needsCreditsToReflect -> {
                            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                            showCreditPurchaseSheet = true
                            viewModel.refreshCredits(showError = false)
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
                containerColor = AnkyColors.Ink,
                titleContentColor = AnkyColors.Paper,
                textContentColor = AnkyColors.PaperMuted,
            )
        }
        if (showCreditPurchaseSheet) {
            ModalBottomSheet(
                onDismissRequest = { showCreditPurchaseSheet = false },
                sheetState = creditPurchaseSheetState,
                shape = RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp),
                containerColor = CreditsPalette.AlmostBlack,
                contentColor = AnkyColors.Paper,
                dragHandle = null,
            ) {
                RevealCreditPurchaseSheet(
                    state = state,
                    onRefresh = { viewModel.refreshCredits() },
                    onPurchase = { packageId ->
                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        viewModel.purchaseCredits(packageId, context.findActivity())
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

private data class RevealLabels(
    val privacyNote: String,
    val writingCopied: String,
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
    val continueWritingLeft: (String) -> String,
    val copiedWriting: String,
    val reflectionLeft: (Int) -> String,
    val receivingReflection: String,
    val getMoreCredits: String,
    val writeMinutes: String,
    val loading: String,
    val mirrorDidNotOpen: String,
    val mirrorForming: String,
    val writingReflectionCharacters: (Int) -> String,
    val ankyDrawingThread: (Int) -> String,
    val ankyReading: String,
    val creditsSheetTitle: String,
    val creditsSheetSubtitle: String,
    val refreshReflectionCredits: String,
    val loadingCreditPacks: String,
    val noCreditPacksAvailable: String,
    val writingIsFreeOneCreditReflection: String,
    val creditsSheetPromptCopyFallback: String,
    val availableCredits: String,
    val bestValue: String,
    val chatStayingWithAnky: String,
    val chatReadingSlowly: String,
    val chatOpenMirror: String,
    val chatWriteAgain: String,
    val chatHasReflection: String,
    val chatReadReflection: String,
    val chatReflectThisAnky: String,
    val chatOpenCredits: String,
    val sheetMirror: String,
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
    val progressCheckingAccess: String,
    val progressPreparingReflection: String,
    val progressAnkyWriting: String,
    val progressBringingBack: String,
    val progressSettling: String,
    val progressCheckingPayment: String,
    val progressPaymentVerified: String,
    val progressNoCreditSpent: String,
    val progressOpeningScroll: String,
    val progressAnkyWorking: String,
    val progressComplete: String,
    val progressReceiving: String,
    val progressChars: (Int) -> String,
    val invitationCheckingMirror: String,
    val invitationAccessEmpty: String,
    val invitationMirrorMayBeOpen: String,
    val invitationReady: String,
    val readyToMirrorArtifact: String,
    val creditPromptFreeGift: (Int) -> String,
    val creditPromptNoReflectionsLeft: String,
    val creditPromptBalanceUpdates: String,
    val shortSessionMessages: List<String>,
)

@Composable
private fun revealLabels(): RevealLabels {
    val context = LocalContext.current
    return RevealLabels(
        privacyNote = stringResource(R.string.reveal_privacy_note),
        writingCopied = stringResource(R.string.writing_copied),
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
        continueWritingLeft = { remaining -> context.getString(R.string.continue_writing_left, remaining) },
        copiedWriting = stringResource(R.string.copied_writing),
        reflectionLeft = { count ->
            context.getString(
                if (count == 1) R.string.reflection_left else R.string.reflections_left,
                count,
            )
        },
        receivingReflection = stringResource(R.string.receiving_reflection),
        getMoreCredits = stringResource(R.string.get_more_credits),
        writeMinutes = stringResource(R.string.write_minutes_caps, AnkyDuration.CompleteRitualMinutes),
        loading = stringResource(R.string.loading),
        mirrorDidNotOpen = stringResource(R.string.mirror_did_not_open),
        mirrorForming = stringResource(R.string.reveal_mirror_forming),
        writingReflectionCharacters = { count -> context.getString(R.string.reveal_writing_reflection_characters, count) },
        ankyDrawingThread = { count -> context.getString(R.string.reveal_anky_drawing_thread, count) },
        ankyReading = stringResource(R.string.reveal_anky_reading),
        creditsSheetTitle = stringResource(R.string.credits_sheet_title),
        creditsSheetSubtitle = stringResource(R.string.credits_sheet_subtitle),
        refreshReflectionCredits = stringResource(R.string.refresh_reflection_credits),
        loadingCreditPacks = stringResource(R.string.loading_credit_packs),
        noCreditPacksAvailable = stringResource(R.string.no_credit_packs_available),
        writingIsFreeOneCreditReflection = stringResource(R.string.writing_is_free_one_credit_reflection),
        creditsSheetPromptCopyFallback = stringResource(R.string.credits_sheet_prompt_copy_fallback),
        availableCredits = stringResource(R.string.available_credits),
        bestValue = stringResource(R.string.best_value),
        chatStayingWithAnky = stringResource(R.string.reveal_chat_staying_with_anky),
        chatReadingSlowly = stringResource(R.string.reveal_chat_reading_slowly),
        chatOpenMirror = stringResource(R.string.reveal_chat_open_mirror),
        chatWriteAgain = stringResource(R.string.reveal_chat_write_again),
        chatHasReflection = stringResource(R.string.reveal_chat_has_reflection),
        chatReadReflection = stringResource(R.string.reveal_chat_read_reflection),
        chatReflectThisAnky = stringResource(R.string.reveal_chat_reflect_this_anky),
        chatOpenCredits = stringResource(R.string.reveal_chat_open_credits),
        sheetMirror = stringResource(R.string.reveal_sheet_mirror),
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
        progressCheckingAccess = stringResource(R.string.reveal_progress_checking_access),
        progressPreparingReflection = stringResource(R.string.reveal_progress_preparing_reflection),
        progressAnkyWriting = stringResource(R.string.reveal_progress_anky_writing),
        progressBringingBack = stringResource(R.string.reveal_progress_bringing_back),
        progressSettling = stringResource(R.string.reveal_progress_settling),
        progressCheckingPayment = stringResource(R.string.reveal_progress_checking_payment),
        progressPaymentVerified = stringResource(R.string.reveal_progress_payment_verified),
        progressNoCreditSpent = stringResource(R.string.reveal_progress_no_credit_spent),
        progressOpeningScroll = stringResource(R.string.reveal_progress_opening_scroll),
        progressAnkyWorking = stringResource(R.string.reveal_progress_anky_working),
        progressComplete = stringResource(R.string.reveal_progress_complete),
        progressReceiving = stringResource(R.string.reveal_progress_receiving),
        progressChars = { count -> context.getString(R.string.reveal_progress_chars, count) },
        invitationCheckingMirror = stringResource(R.string.reveal_invitation_checking_mirror),
        invitationAccessEmpty = stringResource(R.string.reveal_invitation_access_empty),
        invitationMirrorMayBeOpen = stringResource(R.string.reveal_invitation_mirror_may_be_open),
        invitationReady = stringResource(R.string.reveal_invitation_ready),
        readyToMirrorArtifact = stringResource(R.string.reveal_ready_to_mirror_artifact),
        creditPromptFreeGift = { count -> context.getString(R.string.credit_prompt_free_gift, count) },
        creditPromptNoReflectionsLeft = stringResource(R.string.credit_prompt_no_reflections_left),
        creditPromptBalanceUpdates = stringResource(R.string.credit_prompt_balance_updates),
        shortSessionMessages = listOf(
            stringResource(R.string.reveal_short_keep_going, AnkyDuration.CompleteRitualMinutes),
            stringResource(R.string.reveal_short_thread_opened, AnkyDuration.CompleteRitualMinutes),
            stringResource(R.string.reveal_short_spark, AnkyDuration.CompleteRitualMinutes),
            stringResource(R.string.reveal_short_whole_ritual, AnkyDuration.CompleteRitualMinutes),
            stringResource(R.string.reveal_short_cross_mark, AnkyDuration.CompleteRitualMinutes),
        ),
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
    Column(Modifier.fillMaxWidth().background(AnkyColors.Ink.copy(alpha = 0.96f))) {
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
                    tint = AnkyColors.Paper,
                    modifier = Modifier.size(24.dp),
                )
            }
            Text(
                title,
                style = AnkyType.Body.copy(
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AnkyColors.Paper,
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
            )
            Icon(
                imageVector = if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy,
                contentDescription = "$copyWritingContentDescription. $copyReflectionPromptHint",
                tint = if (copied) AnkyColors.Success else AnkyColors.Paper,
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
                            color = AnkyColors.Paper,
                            strokeWidth = 2.dp,
                            modifier = Modifier.size(18.dp),
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Filled.Delete,
                            contentDescription = deleteContentDescription,
                            tint = AnkyColors.Danger.copy(alpha = 0.88f),
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            } else {
                Spacer(Modifier.size(44.dp))
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.13f)))
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
            tint = AnkyColors.Paper.copy(alpha = 0.44f),
            modifier = Modifier.size(13.dp),
        )
        Text(
            value,
            style = AnkyType.Mono.copy(
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = AnkyColors.Paper.copy(alpha = 0.44f),
            ),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
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
            style = AnkyType.Heading.copy(fontSize = 23.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Gold),
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
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (!title.isNullOrBlank()) {
            Text(
                title,
                style = AnkyType.Heading.copy(fontSize = 23.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Gold),
            )
        }
        SelectionContainer {
            MarkdownishText(body)
        }
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
            style = AnkyType.Heading.copy(fontSize = 28.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Gold),
        )
        Text(
            message.orEmpty(),
            style = AnkyType.Mono.copy(fontSize = 13.sp, lineHeight = 18.sp, color = Color.Red.copy(alpha = 0.82f)),
        )
    }
}

@Composable
private fun RevealBottomActionButton(
    title: String,
    subtitle: String?,
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
    val sweepProgress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1650, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "reveal-cta-sweep",
    )
    val enabledOrLoading = isEnabled || isLoading
    val shape = RoundedCornerShape(percent = 50)
    val scale = if (enabledOrLoading) 1f + breath * 0.005f else 1f
    val glowAlpha = when {
        isLoading -> 0.38f
        breath > 0.5f -> 0.35f
        else -> 0.18f
    }
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(if (subtitle == null) 74.dp else 82.dp)
            .scale(scale)
            .alpha(if (enabledOrLoading) 1f else 0.52f)
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(
                        RevealCTAPalette.PurpleTop.copy(alpha = 0.95f),
                        RevealCTAPalette.PurpleBottom.copy(alpha = 0.98f),
                    ),
                ),
            )
            .border(
                BorderStroke(
                    width = if (isLoading) 2.2.dp else 1.8.dp,
                    brush = Brush.linearGradient(
                        listOf(
                            RevealCTAPalette.BorderGold,
                            RevealCTAPalette.BorderViolet,
                            RevealCTAPalette.BorderGoldDeep,
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
            drawCircle(
                color = RevealCTAPalette.VioletGlow.copy(alpha = if (isLoading) 0.36f else 0.25f),
                radius = size.width * 0.38f,
                center = Offset(size.width / 2f, -size.height * 0.18f),
            )
            drawRoundRect(
                color = RevealCTAPalette.GlowGold.copy(alpha = glowAlpha * 0.42f),
                size = size,
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2f, size.height / 2f),
                style = Stroke(width = if (isLoading) 5.5.dp.toPx() else 3.5.dp.toPx()),
            )
            drawRoundRect(
                color = Color.White.copy(alpha = 0.12f),
                size = size,
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2f, size.height / 2f),
                style = Stroke(width = 0.8.dp.toPx()),
            )
        }
        if (isLoading) {
            AnkyThreadSweep(
                progress = sweepProgress,
                modifier = Modifier.matchParentSize(),
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (isLoading) {
                CircularProgressIndicator(
                    color = RevealCTAPalette.PaperBright,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(18.dp),
                )
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    title,
                    style = AnkyType.Heading.copy(
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Medium,
                        color = RevealCTAPalette.PaperBright,
                        shadow = Shadow(
                            color = RevealCTAPalette.GlowGold.copy(alpha = if (isLoading) 0.65f else 0.45f),
                            blurRadius = if (isLoading) 12f else 8f,
                        ),
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
                subtitle?.let {
                    Text(
                        it,
                        style = AnkyType.Caption.copy(
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = RevealCTAPalette.PaperBright.copy(alpha = 0.72f),
                        ),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}

@Composable
private fun AnkyThreadSweep(
    progress: Float,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier) {
        val centerX = progress * (size.width + 180.dp.toPx()) - 90.dp.toPx()
        val midY = size.height * 0.52f
        val waveHeight = size.height * 0.09f
        val startX = maxOf(0f, centerX - 120.dp.toPx())
        val endX = minOf(size.width, centerX + 120.dp.toPx())
        if (endX <= startX) return@Canvas

        val path = Path().apply {
            moveTo(startX, midY)
            var x = startX
            while (x <= endX) {
                val local = (x - centerX) / 120.dp.toPx()
                val y = midY + sin(local * PI.toFloat() * 3.2f) * waveHeight
                lineTo(x, y)
                x += 4.dp.toPx()
            }
        }
        drawPath(
            path = path,
            brush = Brush.linearGradient(
                listOf(
                    Color.Transparent,
                    RevealCTAPalette.BorderGold.copy(alpha = 0.9f),
                    RevealCTAPalette.GlowGold,
                    Color.Transparent,
                ),
                start = Offset(startX, midY),
                end = Offset(endX, midY),
            ),
            style = Stroke(width = 3.2.dp.toPx(), cap = StrokeCap.Round),
        )
        drawCircle(
            color = RevealCTAPalette.PaperBright.copy(alpha = 0.95f),
            radius = 5.dp.toPx(),
            center = Offset(centerX, midY),
        )
    }
}

private object RevealCTAPalette {
    val PurpleTop = Color(0xFF4A176A)
    val PurpleBottom = Color(0xFF250834)
    val VioletGlow = Color(0xFF9C5CFF)
    val GlowGold = Color(0xFFFFB84D)
    val BorderGold = Color(0xFFFFE7A3)
    val BorderViolet = Color(0xFFB668FF)
    val BorderGoldDeep = Color(0xFFFFCA64)
    val PaperBright = Color(0xFFFFF6D5)
}

private fun bottomActionTitle(state: RevealState, labels: RevealLabels): String =
    when {
        state.isAsking -> labels.receivingReflection
        state.reflection != null -> labels.readReflection
        state.creditsLoading && state.artifact?.isComplete == true -> labels.progressCheckingAccess
        state.needsCreditsToReflect -> labels.getMoreCredits
        state.artifact?.isComplete == true -> labels.reflectThisAnky
        state.canContinueWriting -> labels.continueWritingLeft(state.remainingWritingTime)
        else -> labels.writeMinutes
    }

private fun bottomActionSubtitle(state: RevealState, labels: RevealLabels): String? =
    when {
        state.reflection != null -> null
        else -> when (val promptState = state.creditPromptState) {
            is ReflectionCreditPromptState.Available -> labels.reflectionLeft(promptState.count)
            is ReflectionCreditPromptState.FreeGift -> labels.creditPromptFreeGift(promptState.count)
            else -> null
        }
    }

private fun bottomActionIsEnabled(state: RevealState): Boolean =
    when {
        state.isAsking -> false
        state.reflection != null -> true
        state.needsCreditsToReflect -> true
        state.artifact?.isComplete == true -> state.canSubmitReflectionRequest
        else -> true
    }

private object CreditsPalette {
    val AlmostBlack = Color(0xFF05040B)
    val PurpleDeep = Color(0xFF250834)
    val Violet = Color(0xFF8F4DFF)
    val Gold = Color(0xFFF4D374)
    val Cream = Color(0xFFFFF2C6)
}

@Composable
private fun RevealCreditPurchaseSheet(
    state: RevealState,
    onRefresh: () -> Unit,
    onPurchase: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val labels = revealLabels()
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(CreditsPalette.AlmostBlack),
    ) {
        RevealCreditsSheetBackground(Modifier.matchParentSize())
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 34.dp),
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            Box(
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .padding(top = 10.dp, bottom = 14.dp)
                    .size(width = 42.dp, height = 5.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(Color.White.copy(alpha = 0.35f)),
            )

            Row(
                modifier = Modifier.padding(horizontal = 22.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.AutoAwesome,
                    contentDescription = null,
                    tint = CreditsPalette.Gold,
                    modifier = Modifier.size(28.dp),
                )
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        labels.creditsSheetTitle,
                        style = AnkyType.Heading.copy(fontSize = 29.sp, fontWeight = FontWeight.Medium, color = CreditsPalette.Cream),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        labels.creditsSheetSubtitle,
                        style = AnkyType.Body.copy(fontSize = 15.sp, color = CreditsPalette.Cream.copy(alpha = 0.68f)),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Box(
                    modifier = Modifier
                        .size(46.dp)
                        .clip(CircleShape)
                        .background(CreditsPalette.PurpleDeep.copy(alpha = 0.42f))
                        .border(1.2.dp, CreditsPalette.Gold.copy(alpha = 0.42f), CircleShape)
                        .clickable(
                            enabled = !state.creditsLoading,
                            onClickLabel = labels.refreshReflectionCredits,
                            onClick = onRefresh,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    if (state.creditsLoading) {
                        CircularProgressIndicator(
                            color = CreditsPalette.Gold,
                            strokeWidth = 2.dp,
                            modifier = Modifier.size(22.dp),
                        )
                    } else {
                        RefreshGlyph(Modifier.size(22.dp))
                    }
                }
            }

            RevealCreditBalancePanel(
                balance = state.creditBalance,
                labels = labels,
                modifier = Modifier.padding(horizontal = 22.dp).padding(top = 18.dp),
            )

            Column(
                modifier = Modifier.padding(horizontal = 22.dp).padding(top = 18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                when {
                    state.creditsLoading && state.creditPackages.isEmpty() -> RevealCreditDisabledRow(labels.loadingCreditPacks)
                    state.creditPackages.isEmpty() -> RevealCreditDisabledRow(labels.noCreditPacksAvailable)
                    else -> {
                        state.creditPackages.take(3).forEach { creditPackage ->
                            RevealCreditPackageRow(
                                creditPackage = creditPackage,
                                isRecommended = creditPackage.productId == "inc.anky.credits.11" ||
                                    creditPackage.packageId == "inc.anky.credits.11" ||
                                    creditPackage.packageId.endsWith(".credits.11"),
                                isPurchasing = state.purchasingCreditPackageId == creditPackage.packageId,
                                bestValue = labels.bestValue,
                                onPurchase = onPurchase,
                            )
                        }
                    }
                }
            }

            Column(
                modifier = Modifier.padding(horizontal = 22.dp).padding(top = 18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Filled.AutoAwesome,
                        contentDescription = null,
                        tint = CreditsPalette.Gold.copy(alpha = 0.78f),
                        modifier = Modifier.size(13.dp),
                    )
                    Text(
                        labels.writingIsFreeOneCreditReflection,
                        style = AnkyType.Body.copy(fontSize = 15.sp, fontWeight = FontWeight.Medium, color = CreditsPalette.Cream.copy(alpha = 0.68f)),
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = 10.dp),
                        textAlign = TextAlign.Center,
                    )
                    Icon(
                        imageVector = Icons.Filled.AutoAwesome,
                        contentDescription = null,
                        tint = CreditsPalette.Gold.copy(alpha = 0.78f),
                        modifier = Modifier.size(13.dp),
                    )
                }

                Text(
                    labels.creditsSheetPromptCopyFallback,
                    style = AnkyType.Body.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium, color = CreditsPalette.Cream.copy(alpha = 0.58f)),
                    textAlign = TextAlign.Center,
                    lineHeight = 19.sp,
                )
            }

            state.error?.let { error ->
                Text(
                    localizedRevealError(error),
                    style = AnkyType.Mono.copy(fontSize = 12.sp, color = AnkyColors.Danger.copy(alpha = 0.82f)),
                    modifier = Modifier.padding(horizontal = 22.dp).padding(top = 12.dp),
                )
            }
        }
    }
}

@Composable
private fun RevealCreditBalancePanel(balance: Int?, labels: RevealLabels, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(124.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(Color.Black.copy(alpha = 0.58f))
            .border(1.dp, CreditsPalette.Gold.copy(alpha = 0.34f), RoundedCornerShape(18.dp)),
        contentAlignment = Alignment.CenterStart,
    ) {
        Image(
            painter = painterResource(R.drawable.credits_thread_background),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.horizontalGradient(
                        listOf(
                            AnkyColors.Ink.copy(alpha = 0.90f),
                            AnkyColors.Ink.copy(alpha = 0.38f),
                            Color.Transparent,
                        ),
                    ),
                ),
        )
        Row(
            modifier = Modifier.padding(horizontal = 26.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Text(
                balance?.toString() ?: "...",
                style = AnkyType.Title.copy(
                    fontSize = 68.sp,
                    fontWeight = FontWeight.Bold,
                    color = CreditsPalette.Cream,
                    shadow = Shadow(color = CreditsPalette.Gold.copy(alpha = 0.35f), blurRadius = 14f),
                ),
            )
            Text(
                labels.availableCredits,
                style = AnkyType.Heading.copy(fontSize = 23.sp, fontWeight = FontWeight.Medium, color = CreditsPalette.Cream.copy(alpha = 0.78f)),
                lineHeight = 28.sp,
            )
        }
    }
}

@Composable
private fun RevealCreditPackageRow(
    creditPackage: CreditPackage,
    isRecommended: Boolean,
    isPurchasing: Boolean,
    bestValue: String,
    onPurchase: (String) -> Unit,
) {
    val title = localizedCreditPackageTitle(creditPackage)
    val subtitle = localizedCreditPackageSubtitle(creditPackage)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(94.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(
                Brush.linearGradient(
                    listOf(
                        Color(0xFF150B20).copy(alpha = 0.95f),
                        Color(0xFF07050D).copy(alpha = 0.98f),
                    ),
                ),
            )
            .border(
                if (isRecommended) 1.5.dp else 1.dp,
                CreditsPalette.Gold.copy(alpha = if (isRecommended) 0.95f else 0.32f),
                RoundedCornerShape(16.dp),
            )
            .clickable(enabled = !isPurchasing) { onPurchase(creditPackage.packageId) }
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(
                        listOf(
                            CreditsPalette.Gold.copy(alpha = 0.24f),
                            CreditsPalette.PurpleDeep.copy(alpha = 0.42f),
                            CreditsPalette.AlmostBlack.copy(alpha = 0.50f),
                        ),
                    ),
                )
                .border(1.dp, CreditsPalette.Gold.copy(alpha = 0.24f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = CreditsPalette.Gold, modifier = Modifier.size(17.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                title,
                style = AnkyType.Heading.copy(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = CreditsPalette.Cream),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                subtitle,
                style = AnkyType.Body.copy(fontSize = 13.sp, lineHeight = 17.sp, fontWeight = FontWeight.Medium, color = CreditsPalette.Cream.copy(alpha = 0.58f)),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (isRecommended && !isPurchasing) {
                Text(
                    bestValue,
                    style = AnkyType.Mono.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Ink),
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(CreditsPalette.Gold)
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                )
            }
            Text(
                if (isPurchasing) "..." else creditPackage.price,
                style = AnkyType.Heading.copy(fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = CreditsPalette.Gold),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun localizedCreditPackageTitle(creditPackage: CreditPackage): String =
    when (creditPackage.productId) {
        "inc.anky.credits.3" -> stringResource(R.string.credit_pack_3_title)
        "inc.anky.credits.11" -> stringResource(R.string.credit_pack_11_title)
        "inc.anky.credits.33" -> stringResource(R.string.credit_pack_33_title)
        else -> creditPackage.title
    }

@Composable
private fun localizedCreditPackageSubtitle(creditPackage: CreditPackage): String =
    when (creditPackage.productId) {
        "inc.anky.credits.3" -> stringResource(R.string.credit_pack_3_subtitle)
        "inc.anky.credits.11" -> stringResource(R.string.credit_pack_11_subtitle)
        "inc.anky.credits.33" -> stringResource(R.string.credit_pack_33_subtitle)
        else -> creditPackage.subtitle
    }

@Composable
private fun RefreshGlyph(modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val strokeWidth = 2.1.dp.toPx()
        drawArc(
            color = CreditsPalette.Gold,
            startAngle = 38f,
            sweepAngle = 286f,
            useCenter = false,
            topLeft = Offset(strokeWidth / 2f, strokeWidth / 2f),
            size = Size(size.width - strokeWidth, size.height - strokeWidth),
            style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
        )
        val tip = Offset(size.width * 0.82f, size.height * 0.25f)
        drawLine(
            color = CreditsPalette.Gold,
            start = tip,
            end = Offset(size.width * 0.96f, size.height * 0.24f),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round,
        )
        drawLine(
            color = CreditsPalette.Gold,
            start = tip,
            end = Offset(size.width * 0.78f, size.height * 0.09f),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round,
        )
    }
}

@Composable
private fun RevealCreditsSheetBackground(modifier: Modifier = Modifier) {
    Box(modifier.background(CreditsPalette.AlmostBlack)) {
        Box(
            Modifier
                .matchParentSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color(0xFF130A1F).copy(alpha = 0.98f),
                            Color(0xFF080610).copy(alpha = 0.99f),
                            CreditsPalette.AlmostBlack,
                        ),
                    ),
                ),
        )
        Canvas(Modifier.matchParentSize()) {
            drawCircle(
                color = CreditsPalette.Violet.copy(alpha = 0.28f),
                radius = 480.dp.toPx(),
                center = Offset(0f, 0f),
            )
            drawCircle(
                color = CreditsPalette.Gold.copy(alpha = 0.075f),
                radius = 400.dp.toPx(),
                center = Offset(size.width / 2f, size.height),
            )
        }
    }
}

@Composable
private fun RevealCreditDisabledRow(text: String) {
    Text(
        text,
        style = AnkyType.Body.copy(fontSize = 15.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.58f)),
        modifier = Modifier
            .fillMaxWidth()
            .height(68.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Color.Black.copy(alpha = 0.14f))
            .border(1.dp, AnkyColors.Gold.copy(alpha = 0.22f), RoundedCornerShape(16.dp))
            .padding(horizontal = 18.dp, vertical = 22.dp),
    )
}

private tailrec fun Context.findActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }

@Composable
private fun RevealTexture(modifier: Modifier = Modifier.fillMaxSize()) {
    Canvas(modifier) {
        val bloomHeight = 280.dp.toPx()
        val bloomCenterY = size.height * 0.4f
        listOf(
            Triple(1.34f, 360.dp.toPx(), 0.018f),
            Triple(1.20f, bloomHeight, 0.030f),
            Triple(1.06f, 220.dp.toPx(), 0.024f),
        ).forEach { (widthScale, height, alpha) ->
            val width = size.width * widthScale
            drawOval(
                color = AnkyColors.Violet.copy(alpha = alpha),
                topLeft = androidx.compose.ui.geometry.Offset(
                    x = (size.width - width) / 2f,
                    y = bloomCenterY - height / 2f,
                ),
                size = androidx.compose.ui.geometry.Size(width, height),
            )
        }
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
            Box(Modifier.weight(1f).height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.22f)))
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Lock,
                    contentDescription = toggleContentDescription,
                    tint = AnkyColors.GoldSoft,
                    modifier = Modifier.size(17.dp),
                )
            }
            Box(Modifier.weight(1f).height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.22f)))
        }
        if (expanded) {
            Text(
                note,
                style = AnkyType.Caption.copy(color = AnkyColors.Paper.copy(alpha = 0.62f), fontWeight = FontWeight.Normal),
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun RevealAnkyReflectionChat(
    state: RevealState,
    onAsk: () -> Unit,
    onRead: () -> Unit,
    onOpenCredits: () -> Unit,
    onTryAgain: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val labels = revealLabels()
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (state.isAsking) {
            val status = localizedReflectionStatus(state.reflectionStatusMessage, labels).ifBlank { labels.chatStayingWithAnky }
            AnkyConversationPrompt(
                message = "$status\n\n${labels.chatReadingSlowly}",
                actions = listOf(AnkyChatAction(labels.chatOpenMirror, isPrimary = true, action = onRead)),
                isThinking = true,
            )
        } else if (state.artifact?.isComplete == false) {
            AnkyConversationPrompt(
                message = shortSessionMessage(state, labels),
                actions = listOf(AnkyChatAction(labels.chatWriteAgain, isPrimary = true, action = onTryAgain)),
            )
        } else if (state.reflection != null) {
            AnkyConversationPrompt(
                message = labels.chatHasReflection,
                actions = listOf(AnkyChatAction(labels.chatReadReflection, isPrimary = true, action = onRead)),
            )
        } else {
            AnkyConversationPrompt(
                message = reflectionInvitationMessage(state, labels),
                actions = buildList {
                    if (state.canSubmitReflectionRequest) {
                        add(AnkyChatAction(labels.chatReflectThisAnky, isPrimary = true, action = onAsk))
                    }
                    if (state.shouldShowCreditsLink) {
                        add(AnkyChatAction(labels.chatOpenCredits, action = onOpenCredits))
                    }
                },
                isThinking = state.creditsLoading,
            )
        }

        state.error?.let { errorMessage ->
            Text(
                localizedRevealError(errorMessage),
                style = AnkyType.Mono.copy(fontSize = 12.sp, lineHeight = 16.sp, color = Color.Red.copy(alpha = 0.82f)),
                modifier = Modifier.fillMaxWidth(),
            )
        }

    }
}

@Composable
private fun ReflectionBottomSheetContent(
    state: RevealState,
    onOpenTag: (String) -> Unit,
    onAsk: () -> Unit,
) {
    var revealLiveText by remember { mutableStateOf(false) }
    val labels = revealLabels()
    val reflection = state.reflection
    val isStreamingSheet = state.isAsking || state.streamingReflectionMarkdown.isNotBlank()
    val sheetTopPadding = when {
        reflection != null -> 10.dp
        isStreamingSheet -> 24.dp
        else -> 28.dp
    }
    val sheetBottomPadding = if (reflection != null) 56.dp else 48.dp
    val sheetSpacing = if (isStreamingSheet) 22.dp else 18.dp
    val sheetScrollState = rememberScrollState()
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(AnkyColors.Ink),
    ) {
        RevealTexture(Modifier.matchParentSize())
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(sheetScrollState)
                .padding(horizontal = 22.dp)
                .padding(top = sheetTopPadding, bottom = sheetBottomPadding),
            verticalArrangement = Arrangement.spacedBy(sheetSpacing),
        ) {
            when {
                reflection != null -> {
                    ReflectionScrollGlyph(modifier = Modifier.padding(top = 8.dp))
                    ReflectionTags(tags = reflection.tags, onOpenTag = onOpenTag)
                    MarkdownishText(reflection.displayBody)
                }
                isStreamingSheet -> {
                    Text(
                        labels.mirrorForming,
                        style = AnkyType.Heading.copy(fontSize = 28.sp, color = AnkyColors.Gold),
                    )
                    MirrorProgress(
                        status = localizedReflectionStatus(state.reflectionStatusMessage, labels),
                        generatedCharacters = state.streamingReflectionCharacterCount,
                        labels = labels,
                    )
                    if (state.streamingReflectionMarkdown.isNotBlank()) {
                        if (!revealLiveText) {
                            TextButton(
                                onClick = { revealLiveText = true },
                                modifier = Modifier
                                    .clip(RoundedCornerShape(4.dp))
                                    .border(1.dp, AnkyColors.Gold.copy(alpha = 0.34f), RoundedCornerShape(4.dp)),
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.Visibility,
                                        contentDescription = null,
                                        tint = AnkyColors.GoldSoft,
                                        modifier = Modifier.size(14.dp),
                                    )
                                    Text(
                                        stringResource(R.string.reveal_live),
                                        style = AnkyType.Caption.copy(fontWeight = FontWeight.Bold, color = AnkyColors.GoldSoft),
                                    )
                                    Spacer(Modifier.weight(1f))
                                }
                            }
                        }
                        if (revealLiveText) {
                            Text(
                                labels.writingReflectionCharacters(state.streamingReflectionCharacterCount),
                                style = AnkyType.Caption.copy(
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = AnkyColors.Gold.copy(alpha = 0.72f),
                                ),
                            )
                            MarkdownishText(state.streamingReflectionMarkdown)
                        }
                    }
                }
                else -> {
                    Text(
                        labels.sheetMirror,
                        style = AnkyType.Heading.copy(fontSize = 24.sp, color = AnkyColors.Gold),
                    )
                    Text(
                        localizedCreditPromptMessage(state, labels),
                        style = AnkyType.Mono.copy(fontSize = 13.sp, lineHeight = 18.sp, color = AnkyColors.Paper.copy(alpha = 0.72f)),
                    )
                    TextButton(
                        onClick = onAsk,
                        enabled = state.canSubmitReflectionRequest,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(42.dp)
                            .clip(RoundedCornerShape(5.dp))
                            .background(
                                if (state.canSubmitReflectionRequest) AnkyColors.Gold else AnkyColors.Gold.copy(alpha = 0.34f),
                            )
                            .border(1.dp, Color.White.copy(alpha = 0.44f), RoundedCornerShape(5.dp)),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Filled.AutoAwesome,
                                contentDescription = null,
                                tint = if (state.canSubmitReflectionRequest) AnkyColors.Ink else AnkyColors.Ink.copy(alpha = 0.52f),
                                modifier = Modifier.size(14.dp),
                            )
                            Text(
                                labels.reflectThisAnky,
                                style = AnkyType.Caption.copy(
                                    fontWeight = FontWeight.Bold,
                                    color = if (state.canSubmitReflectionRequest) AnkyColors.Ink else AnkyColors.Ink.copy(alpha = 0.52f),
                                ),
                                textAlign = TextAlign.Start,
                            )
                            Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ReflectionScrollGlyph(modifier: Modifier = Modifier) {
    val pulse by rememberInfiniteTransition(label = "reflection-scroll-glyph").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1000),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "reflection-scroll-glyph-pulse",
    )
    Box(
        modifier = modifier.size(54.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size((42 + pulse * 4).dp)
                .clip(CircleShape)
                .background(AnkyColors.Gold.copy(alpha = 0.22f + pulse * 0.18f)),
        )
        Box(
            Modifier
                .size(width = 24.dp, height = 32.dp)
                .rotate(-8f + pulse * 3f)
                .clip(RoundedCornerShape(5.dp))
                .background(
                    Brush.linearGradient(
                        listOf(
                            AnkyColors.Paper,
                            AnkyColors.Gold,
                            AnkyColors.Paper,
                        ),
                    ),
                )
                .border(1.dp, Color.White.copy(alpha = 0.64f), RoundedCornerShape(5.dp)),
        )
        Icon(
            imageVector = Icons.Filled.AutoAwesome,
            contentDescription = null,
            tint = AnkyColors.Ink.copy(alpha = 0.78f),
            modifier = Modifier
                .size(12.dp)
                .offset(x = 1.dp, y = (-1).dp),
        )
    }
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
            style = AnkyType.Mono.copy(fontSize = 13.sp, color = AnkyColors.Paper.copy(alpha = 0.74f)),
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
                .background(Color.Black.copy(alpha = 0.28f))
                .border(1.dp, AnkyColors.Gold.copy(alpha = 0.22f), RoundedCornerShape(3.dp)),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(progress.coerceIn(0f, 1f))
                    .height(10.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(
                        Brush.horizontalGradient(
                            listOf(
                                AnkyColors.Gold.copy(alpha = 0.72f),
                                AnkyColors.Paper.copy(alpha = 0.66f),
                                AnkyColors.Gold.copy(alpha = 0.84f),
                            ),
                        ),
                    ),
            )
        }
        Row(Modifier.fillMaxWidth()) {
            Text(
                if (isComplete) labels.progressComplete else labels.progressReceiving,
                style = AnkyType.Caption.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = AnkyColors.Paper.copy(alpha = 0.52f)),
            )
            Spacer(Modifier.weight(1f))
            Text(
                labels.progressChars(generatedCharacters),
                style = AnkyType.Caption.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = AnkyColors.Paper.copy(alpha = 0.52f)),
            )
        }
    }
}

internal fun mirrorThreadProgress(generatedCharacters: Int, isComplete: Boolean = false): Float {
    if (isComplete) return 1f
    if (generatedCharacters <= 0) return 0.08f
    return (0.12f + generatedCharacters.toFloat() / 3200f).coerceAtMost(0.92f)
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
                color = AnkyColors.Paper.copy(alpha = 0.46f),
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
                    style = AnkyType.Mono.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Gold),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .clip(CircleShape)
                        .clickable { onOpenTag(tag) }
                        .background(Color.Black.copy(alpha = 0.2f))
                        .border(1.dp, AnkyColors.Gold.copy(alpha = 0.3f), CircleShape)
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                )
            }
        }
    }
}

private fun reflectionInvitationMessage(state: RevealState, labels: RevealLabels): String =
    when {
        state.creditsLoading -> labels.invitationCheckingMirror
        state.creditPromptState == inc.anky.android.core.mirror.ReflectionCreditPromptState.Unavailable ->
            labels.invitationAccessEmpty
        state.creditPromptState == inc.anky.android.core.mirror.ReflectionCreditPromptState.Unknown ->
            labels.invitationMirrorMayBeOpen
        else -> labels.invitationReady
    }

private fun localizedCreditPromptMessage(state: RevealState, labels: RevealLabels): String =
    when (val promptState = state.creditPromptState) {
        is ReflectionCreditPromptState.Available -> labels.reflectionLeft(promptState.count)
        is ReflectionCreditPromptState.FreeGift -> labels.creditPromptFreeGift(promptState.count)
        ReflectionCreditPromptState.Unavailable -> labels.creditPromptNoReflectionsLeft
        ReflectionCreditPromptState.Unknown -> labels.creditPromptBalanceUpdates
    }

@Composable
private fun localizedRevealError(message: String?): String =
    when (message?.trim().orEmpty()) {
        "" -> ""
        "Could not load reflections." -> stringResource(R.string.reveal_error_load_reflections)
        "Anky could not return a reflection right now." -> stringResource(R.string.reveal_error_return_reflection)
        "Could not complete that credit purchase." -> stringResource(R.string.reveal_error_credit_purchase)
        "This writing session could not be deleted." -> stringResource(R.string.reveal_delete_session_failed)
        "The mirror URL is not valid." -> stringResource(R.string.reveal_error_invalid_mirror_url)
        "The mirror returned an invalid response." -> stringResource(R.string.reveal_error_invalid_mirror_response)
        "The mirror response did not match this .anky." -> stringResource(R.string.reveal_error_hash_mismatch)
        "This device already used its first two reflections. Add credits to ask Anky again. Writing is still free." ->
            stringResource(R.string.reveal_error_trial_already_claimed)
        "You need one reflection credit to ask Anky. Writing is still free." ->
            stringResource(R.string.reveal_error_credit_required)
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
        "checking reflection access..." -> labels.progressCheckingAccess
        "preparing the reflection..." -> labels.progressPreparingReflection
        "anky is writing..." -> labels.progressAnkyWriting
        "bringing it back..." -> labels.progressBringingBack
        "settling..." -> labels.progressSettling
        "checking payment options..." -> labels.progressCheckingPayment
        "payment verified..." -> labels.progressPaymentVerified
        "no credit spent..." -> labels.progressNoCreditSpent
        "opening the scroll..." -> labels.progressOpeningScroll
        "anky is working..." -> labels.progressAnkyWorking
        else -> trimmed
    }
}

private fun shortSessionMessage(state: RevealState, labels: RevealLabels): String =
    if (state.artifact?.isComplete == false) {
        stableShortSessionMessage(
            hash = state.artifact.hash,
            wordCount = state.artifact.reconstructedText
                .splitToSequence(Regex("\\s+"))
                .filter { it.isNotBlank() }
                .count(),
            messages = labels.shortSessionMessages,
        )
    } else {
        labels.readyToMirrorArtifact
    }

private fun stableShortSessionMessage(hash: String, wordCount: Int, messages: List<String>): String {
    if (messages.isEmpty()) return ""
    val stableValue = hash.take(8).toLongOrNull(radix = 16) ?: wordCount.toLong()
    return messages[(stableValue % messages.size.toLong()).toInt()]
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

    when {
        trimmed.isEmpty() -> Spacer(Modifier.height(12.dp))
        isMarkdownHorizontalRule(trimmed) -> Box(
            Modifier
                .fillMaxWidth()
                .padding(top = 12.dp, bottom = 12.dp)
                .height(1.dp)
                .background(AnkyColors.Gold.copy(alpha = 0.22f)),
        )
        headingText(trimmed) != null -> Text(
            inlineMarkdown(headingText(trimmed)!!),
            style = AnkyType.Heading.copy(fontSize = 20.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Gold),
            modifier = Modifier.padding(top = 4.dp, bottom = 5.dp),
        )
        trimmed.startsWith(">") -> Row(
            modifier = Modifier
                .height(IntrinsicSize.Min)
                .padding(top = 6.dp, bottom = 3.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Box(Modifier.width(2.dp).fillMaxHeight().background(AnkyColors.Gold.copy(alpha = 0.36f)))
            Text(
                inlineMarkdown(trimmed.drop(1).trim()),
                style = AnkyType.Body.copy(
                    color = Color(0xADF4F1EA),
                    fontStyle = FontStyle.Italic,
                ),
            )
        }
        trimmed.startsWith("- ") || trimmed.startsWith("* ") -> MarkdownListRow("•", trimmed.drop(2))
        numbered != null -> MarkdownListRow(numbered.first, numbered.second)
        else -> Text(
            inlineMarkdown(trimmed),
            style = AnkyType.Body,
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
        Text(marker, style = AnkyType.Body.copy(color = AnkyColors.Gold.copy(alpha = 0.72f)))
        Text(inlineMarkdown(body), style = AnkyType.Body)
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
                    withStyle(SpanStyle(color = AnkyColors.Gold, fontWeight = FontWeight.Bold)) {
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
                            color = AnkyColors.Paper.copy(alpha = 0.82f),
                            fontFamily = FontFamily.Default,
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

private fun wordCountText(text: String): String {
    val count = wordCountNumber(text)
    return "$count ${if (count == 1) "word" else "words"}"
}

private fun wordCountNumber(text: String): Int =
    text.splitToSequence(Regex("\\s+")).filter { it.isNotBlank() }.count()

private fun countdownClock(durationMs: Long): String {
    val totalSeconds = maxOf(0, durationMs / 1000)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}"
}

private fun Context.copyText(label: String, text: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

private val inc.anky.android.core.storage.LocalReflection.displayBody: String
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

private val CopyMagenta = Color(0xFFFF3BD4)
