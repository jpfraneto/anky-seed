package inc.anky.android.feature.reveal

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Visibility
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
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
import inc.anky.android.ui.components.AnkyChatAction
import inc.anky.android.ui.components.AnkyConversationPrompt
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
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
    onTryAgain: () -> Unit = {},
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val view = LocalView.current
    val artifact = state.artifact
    val scrollState = rememberScrollState()
    val scope = rememberCoroutineScope()
    var confirmDelete by remember { mutableStateOf(false) }
    var copiedBurst by remember { mutableStateOf<RevealCopySection?>(null) }
    var inlineReflectionActive by remember { mutableStateOf(false) }
    var didAutoStartReflection by remember { mutableStateOf(false) }
    var showCreditPurchaseSheet by remember { mutableStateOf(false) }
    val creditPurchaseSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val labels = revealLabels()

    fun scrollToReflection() {
        scope.launch {
            delay(80)
            scrollState.animateScrollTo(scrollState.maxValue)
        }
    }

    fun copySection(section: RevealCopySection) {
        val text = viewModel.textForCopy(section) ?: return
        val label = when (section) {
            RevealCopySection.Writing -> "Anky writing"
            RevealCopySection.Reflection -> "Anky reflection"
        }
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        context.copyText(label, text)
        viewModel.markCopied(section)
        copiedBurst = section
    }

    LaunchedEffect(Unit) {
        viewModel.refreshCredits(showError = false)
    }

    LaunchedEffect(startsReflectionOnAppear, state.reflection) {
        if (
            startsReflectionOnAppear &&
            !didAutoStartReflection &&
            state.reflection == null
        ) {
            didAutoStartReflection = true
            inlineReflectionActive = true
            viewModel.askAnky()
            scrollToReflection()
        }
    }

    LaunchedEffect(copiedBurst) {
        val section = copiedBurst ?: return@LaunchedEffect
        delay(740)
        copiedBurst = null
        viewModel.clearCopied(section)
    }

    LaunchedEffect(state.reflection?.hash, state.streamingReflectionMarkdown, state.error) {
        if (
            state.reflection != null ||
            state.streamingReflectionMarkdown.isNotBlank() ||
            (inlineReflectionActive && state.error != null)
        ) {
            scrollToReflection()
        }
    }

    LaunchedEffect(state.isAsking, state.streamingReflectionMarkdown) {
        if (state.isAsking || state.streamingReflectionMarkdown.isNotBlank()) {
            inlineReflectionActive = true
        }
    }

    LaunchedEffect(state.isDeleted) {
        if (state.isDeleted) {
            onDeleted()
            onBack()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AnkyColors.Ink)
            .testTag("reveal-screen"),
    ) {
        RevealTexture()
        Column(Modifier.fillMaxSize()) {
            RevealHeader(
                date = artifact?.createdAt?.let {
                    DateTimeFormatter.ofPattern("EEEE, MMMM d, yyyy", Locale.getDefault()).withZone(ZoneId.systemDefault()).format(it)
                }.orEmpty(),
                time = artifact?.createdAt?.let { DateTimeFormatter.ofPattern("h:mm a").withZone(ZoneId.systemDefault()).format(it) }.orEmpty(),
                metadata = artifact?.let { "${AnkyDuration.formatted(it.durationMs)} / ${wordCountText(it.reconstructedText)}" }.orEmpty(),
                onBack = onBack,
                canDelete = artifact != null,
                isDeleting = state.isDeleting,
                deleteContentDescription = labels.deleteWritingSession,
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
                    .verticalScroll(scrollState)
                    .padding(horizontal = 28.dp)
                    .padding(top = 20.dp, bottom = 138.dp),
                verticalArrangement = Arrangement.spacedBy(0.dp),
            ) {
                SelectionContainer {
                    Text(
                        text = artifact.reconstructedText,
                        style = AnkyType.Body.copy(fontSize = 19.sp, lineHeight = 28.sp),
                        modifier = Modifier
                            .padding(vertical = 8.dp)
                            .testTag("reconstructed-text"),
                    )
                }
                RevealCopyButton(
                    label = labels.copyWriting.lowercase(),
                    copiedLabel = labels.writingCopied.lowercase(),
                    copied = state.copiedSection == RevealCopySection.Writing,
                    onClick = { copySection(RevealCopySection.Writing) },
                    modifier = Modifier.padding(top = 16.dp),
                )
                PrivacyDivider(labels.privacyNote, labels.togglePrivacyMessage, Modifier.padding(top = 34.dp))

                when {
                    state.reflection != null -> {
                        SavedReflectionPanel(
                            reflection = state.reflection,
                            copied = state.copiedSection == RevealCopySection.Reflection,
                            labels = labels,
                            onCopy = { copySection(RevealCopySection.Reflection) },
                            modifier = Modifier.padding(top = 36.dp),
                        )
                    }
                    state.streamingReflectionMarkdown.isNotBlank() || state.isAsking -> {
                        StreamingReflectionPanel(
                            markdown = state.streamingReflectionMarkdown,
                            status = state.reflectionStatusMessage,
                            generatedCharacters = state.streamingReflectionCharacterCount,
                            labels = labels,
                            modifier = Modifier.padding(top = 36.dp),
                        )
                    }
                    inlineReflectionActive && state.error != null -> {
                        ReflectionErrorPanel(
                            message = state.error,
                            title = labels.mirrorDidNotOpen,
                            modifier = Modifier.padding(top = 36.dp),
                        )
                    }
                }
            }
        }
        if (copiedBurst != null) {
            Text(
                when (copiedBurst) {
                    RevealCopySection.Reflection -> labels.copiedReflection
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
        RevealEdgeBackSwipe(onBack = onBack, modifier = Modifier.align(Alignment.CenterStart))
        if (artifact != null) {
            RevealBottomActionButton(
                title = bottomActionTitle(state, labels),
                isLoading = state.isAsking,
                isEnabled = bottomActionIsEnabled(state),
                onClick = {
                    when {
                        state.reflection != null -> {
                            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                            scrollToReflection()
                        }
                        state.needsCreditsToReflect -> {
                            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                            showCreditPurchaseSheet = true
                            viewModel.refreshCredits(showError = false)
                        }
                        artifact.isComplete -> {
                            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                            inlineReflectionActive = true
                            viewModel.askAnky()
                            scrollToReflection()
                        }
                        else -> onTryAgain()
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
                containerColor = AnkyColors.Ink,
                contentColor = AnkyColors.Paper,
            ) {
                RevealCreditPurchaseSheet(
                    state = state,
                    onRefresh = { viewModel.refreshCredits() },
                    onPurchase = { packageId ->
                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        viewModel.purchaseCredits(packageId, context.findActivity())
                    },
                    modifier = Modifier.padding(horizontal = 22.dp).padding(bottom = 34.dp),
                )
            }
        }
    }
}

private data class RevealLabels(
    val privacyNote: String,
    val writingCopied: String,
    val copyWriting: String,
    val deleteWritingSession: String,
    val deleteWritingSessionQuestion: String,
    val delete: String,
    val cancel: String,
    val deleteWritingSessionBody: String,
    val togglePrivacyMessage: String,
    val readReflection: String,
    val reflectThisAnky: String,
    val reflectThisAnkyLeft: (Int) -> String,
    val reflectThisAnkyDeviceGift: String,
    val copyReflection: String,
    val copiedReflection: String,
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
    val progressComplete: String,
    val progressReceiving: String,
    val progressChars: (Int) -> String,
    val invitationCheckingMirror: String,
    val invitationAccessEmpty: String,
    val invitationMirrorMayBeOpen: String,
    val invitationReady: String,
    val readyToMirrorArtifact: String,
    val shortSessionMessages: List<String>,
)

@Composable
private fun revealLabels(): RevealLabels {
    val context = LocalContext.current
    return RevealLabels(
        privacyNote = stringResource(R.string.reveal_privacy_note),
        writingCopied = stringResource(R.string.writing_copied),
        copyWriting = stringResource(R.string.copy_writing),
        deleteWritingSession = stringResource(R.string.delete_writing_session),
        deleteWritingSessionQuestion = stringResource(R.string.delete_writing_session_question),
        delete = stringResource(R.string.delete),
        cancel = stringResource(R.string.cancel_title),
        deleteWritingSessionBody = stringResource(R.string.delete_writing_session_body),
        togglePrivacyMessage = stringResource(R.string.reveal_toggle_privacy_message),
        readReflection = stringResource(R.string.read_reflection),
        reflectThisAnky = stringResource(R.string.reflect_this_anky),
        reflectThisAnkyLeft = { count -> context.getString(R.string.reflect_this_anky_left, count) },
        reflectThisAnkyDeviceGift = stringResource(R.string.reflect_this_anky_device_gift),
        copyReflection = stringResource(R.string.copy_reflection),
        copiedReflection = stringResource(R.string.copied_reflection),
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
        progressComplete = stringResource(R.string.reveal_progress_complete),
        progressReceiving = stringResource(R.string.reveal_progress_receiving),
        progressChars = { count -> context.getString(R.string.reveal_progress_chars, count) },
        invitationCheckingMirror = stringResource(R.string.reveal_invitation_checking_mirror),
        invitationAccessEmpty = stringResource(R.string.reveal_invitation_access_empty),
        invitationMirrorMayBeOpen = stringResource(R.string.reveal_invitation_mirror_may_be_open),
        invitationReady = stringResource(R.string.reveal_invitation_ready),
        readyToMirrorArtifact = stringResource(R.string.reveal_ready_to_mirror_artifact),
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
private fun RevealHeader(
    date: String,
    time: String,
    metadata: String,
    onBack: () -> Unit,
    canDelete: Boolean,
    isDeleting: Boolean,
    deleteContentDescription: String,
    onDelete: () -> Unit,
) {
    val backLabel = stringResource(R.string.back)
    Column(Modifier.fillMaxWidth().background(AnkyColors.Ink.copy(alpha = 0.96f))) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier.size(40.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.24f)).border(1.dp, AnkyColors.Gold.copy(alpha = 0.24f), CircleShape),
            ) {
                Icon(
                    imageVector = Icons.Filled.ChevronLeft,
                    contentDescription = backLabel,
                    tint = AnkyColors.Paper,
                    modifier = Modifier.size(22.dp),
                )
            }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("$date / $time".lowercase(), style = AnkyType.Caption.copy(color = AnkyColors.Paper.copy(alpha = 0.78f)))
                Text(metadata.lowercase(), style = AnkyType.Mono.copy(color = AnkyColors.Paper.copy(alpha = 0.54f)), textAlign = TextAlign.Center)
            }
            if (canDelete) {
                IconButton(
                    onClick = onDelete,
                    enabled = !isDeleting,
                    modifier = Modifier.size(40.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.24f)).border(1.dp, AnkyColors.Danger.copy(alpha = 0.22f), CircleShape),
                ) {
                    Icon(
                        imageVector = Icons.Filled.Delete,
                        contentDescription = deleteContentDescription,
                        tint = AnkyColors.Danger.copy(alpha = 0.88f),
                        modifier = Modifier.size(19.dp),
                    )
                }
            } else {
                Spacer(Modifier.size(40.dp))
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.13f)))
    }
}

@Composable
private fun RevealCopyButton(
    label: String,
    copiedLabel: String = "copied",
    copied: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    TextButton(
        onClick = onClick,
        modifier = modifier
            .clip(RoundedCornerShape(5.dp))
            .border(1.dp, AnkyColors.Gold.copy(alpha = if (copied) 0.62f else 0.26f), RoundedCornerShape(5.dp)),
    ) {
        Text(
            if (copied) copiedLabel else label,
            style = AnkyType.Mono.copy(
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = AnkyColors.GoldSoft,
            ),
        )
    }
}

@Composable
private fun SavedReflectionPanel(
    reflection: LocalReflection,
    copied: Boolean,
    labels: RevealLabels,
    onCopy: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            reflection.title.lowercase(),
            style = AnkyType.Heading.copy(fontSize = 23.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Gold),
            modifier = Modifier.testTag("saved-reflection-title"),
        )
        MarkdownishText(reflection.displayBody)
        reflection.creditsRemaining?.let { remaining ->
            Text(
                labels.reflectionLeft(remaining),
                style = AnkyType.Mono.copy(fontSize = 12.sp, color = AnkyColors.Paper.copy(alpha = 0.58f)),
                modifier = Modifier.padding(top = 4.dp),
            )
        }
        RevealCopyButton(
            label = labels.copyReflection.lowercase(),
            copiedLabel = labels.copiedReflection.lowercase(),
            copied = copied,
            onClick = onCopy,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}

@Composable
private fun StreamingReflectionPanel(
    markdown: String,
    status: String,
    generatedCharacters: Int,
    labels: RevealLabels,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(
            labels.mirrorForming,
            style = AnkyType.Heading.copy(fontSize = 28.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Gold),
        )
        MirrorProgress(status = status, generatedCharacters = generatedCharacters, labels = labels)
        if (markdown.isNotBlank()) {
            Text(
                labels.writingReflectionCharacters(generatedCharacters),
                style = AnkyType.Caption.copy(
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AnkyColors.Gold.copy(alpha = 0.72f),
                ),
            )
            MarkdownishText(markdown)
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
            message.orEmpty().lowercase(),
            style = AnkyType.Mono.copy(fontSize = 13.sp, lineHeight = 18.sp, color = Color.Red.copy(alpha = 0.82f)),
        )
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
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(62.dp)
            .clip(RoundedCornerShape(7.dp))
            .background(AnkyColors.Gold)
            .border(1.dp, Color.White.copy(alpha = 0.48f), RoundedCornerShape(7.dp))
            .clickable(enabled = isEnabled, onClick = onClick)
            .padding(horizontal = 18.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    color = AnkyColors.Ink,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(18.dp),
                )
            }
            Text(
                title,
                style = AnkyType.Mono.copy(
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = AnkyColors.Ink.copy(alpha = if (isEnabled || isLoading) 1f else 0.52f),
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
        state.needsCreditsToReflect -> labels.getMoreCredits
        state.artifact?.isComplete == true -> reflectButtonTitle(state, labels)
        else -> labels.writeMinutes
    }

private fun reflectButtonTitle(state: RevealState, labels: RevealLabels): String =
    when (val promptState = state.creditPromptState) {
        is ReflectionCreditPromptState.Available -> labels.reflectThisAnkyLeft(promptState.count)
        is ReflectionCreditPromptState.FreeGift -> labels.reflectThisAnkyDeviceGift
        ReflectionCreditPromptState.Unavailable -> labels.getMoreCredits
        ReflectionCreditPromptState.Unknown -> labels.reflectThisAnky
    }

private fun bottomActionIsEnabled(state: RevealState): Boolean =
    when {
        state.isAsking -> false
        state.reflection != null -> true
        state.needsCreditsToReflect -> true
        state.artifact?.isComplete == true -> state.canSubmitReflectionRequest
        else -> true
    }

@Composable
private fun RevealCreditPurchaseSheet(
    state: RevealState,
    onRefresh: () -> Unit,
    onPurchase: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val labels = revealLabels()
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(
                imageVector = Icons.Filled.AutoAwesome,
                contentDescription = null,
                tint = AnkyColors.Gold,
                modifier = Modifier.size(28.dp),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    labels.creditsSheetTitle,
                    style = AnkyType.Heading.copy(fontSize = 29.sp, fontWeight = FontWeight.Medium),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    labels.creditsSheetSubtitle,
                    style = AnkyType.Body.copy(fontSize = 15.sp, color = AnkyColors.Paper.copy(alpha = 0.68f)),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            IconButton(onClick = onRefresh, enabled = !state.creditsLoading) {
                if (state.creditsLoading) {
                    CircularProgressIndicator(
                        color = AnkyColors.Gold,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(22.dp),
                    )
                } else {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = labels.refreshReflectionCredits,
                        tint = AnkyColors.Gold,
                        modifier = Modifier.size(22.dp),
                    )
                }
            }
        }

        RevealCreditBalancePanel(state.creditBalance, labels)

        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when {
                state.creditsLoading && state.creditPackages.isEmpty() -> RevealCreditDisabledRow(labels.loadingCreditPacks)
                state.creditPackages.isEmpty() -> RevealCreditDisabledRow(labels.noCreditPacksAvailable)
                else -> {
                    state.creditPackages.take(3).forEach { creditPackage ->
                        RevealCreditPackageRow(
                            creditPackage = creditPackage,
                            isRecommended = creditPackage.title == "11 reflections" ||
                                creditPackage.packageId.endsWith(".credits.11"),
                            isPurchasing = state.purchasingCreditPackageId == creditPackage.packageId,
                            bestValue = labels.bestValue,
                            onPurchase = onPurchase,
                        )
                    }
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Filled.AutoAwesome,
                contentDescription = null,
                tint = AnkyColors.Gold.copy(alpha = 0.78f),
                modifier = Modifier.size(13.dp),
            )
            Text(
                labels.writingIsFreeOneCreditReflection,
                style = AnkyType.Body.copy(fontSize = 15.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.68f)),
                modifier = Modifier.padding(horizontal = 10.dp),
                textAlign = TextAlign.Center,
            )
            Icon(
                imageVector = Icons.Filled.AutoAwesome,
                contentDescription = null,
                tint = AnkyColors.Gold.copy(alpha = 0.78f),
                modifier = Modifier.size(13.dp),
            )
        }

        state.error?.let { error ->
            Text(
                error.lowercase(),
                style = AnkyType.Mono.copy(fontSize = 12.sp, color = AnkyColors.Danger.copy(alpha = 0.82f)),
            )
        }
    }
}

@Composable
private fun RevealCreditBalancePanel(balance: Int?, labels: RevealLabels) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(124.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(Color.Black.copy(alpha = 0.58f))
            .border(1.dp, AnkyColors.Gold.copy(alpha = 0.34f), RoundedCornerShape(18.dp)),
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
                    shadow = Shadow(color = AnkyColors.Gold.copy(alpha = 0.35f), blurRadius = 14f),
                ),
            )
            Text(
                labels.availableCredits,
                style = AnkyType.Heading.copy(fontSize = 23.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.78f)),
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
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(86.dp)
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
                AnkyColors.Gold.copy(alpha = if (isRecommended) 0.52f else 0.28f),
                RoundedCornerShape(16.dp),
            )
            .clickable(enabled = !isPurchasing) { onPurchase(creditPackage.packageId) }
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(AnkyColors.Gold.copy(alpha = 0.16f))
                .border(1.dp, AnkyColors.Gold.copy(alpha = 0.24f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = AnkyColors.Gold, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                creditPackage.title,
                style = AnkyType.Heading.copy(fontSize = 25.sp, fontWeight = FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                creditPackage.subtitle,
                style = AnkyType.Body.copy(fontSize = 16.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.58f)),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (isRecommended && !isPurchasing) {
                Text(
                    bestValue,
                    style = AnkyType.Mono.copy(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Ink),
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(AnkyColors.Gold)
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                )
            }
            Text(
                if (isPurchasing) "..." else creditPackage.price,
                style = AnkyType.Heading.copy(fontSize = 23.sp, fontWeight = FontWeight.SemiBold, color = AnkyColors.Gold),
                maxLines = 1,
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
        listOf(0.19f, 0.47f, 0.78f).forEach { y ->
            drawLine(
                color = AnkyColors.Gold.copy(alpha = 0.075f),
                start = androidx.compose.ui.geometry.Offset(0f, size.height * y),
                end = androidx.compose.ui.geometry.Offset(size.width, size.height * y),
                strokeWidth = 1.dp.toPx(),
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
            val status = state.reflectionStatusMessage.ifBlank { labels.chatStayingWithAnky }
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
                errorMessage.lowercase(),
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
                        status = state.reflectionStatusMessage,
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
                        state.creditPromptMessage.lowercase(),
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
                                labels.reflectThisAnky.lowercase(),
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
                    fontSize = 16.sp,
                    fontStyle = FontStyle.Italic,
                ),
            )
        }
        trimmed.startsWith("- ") || trimmed.startsWith("* ") -> MarkdownListRow("•", trimmed.drop(2))
        numbered != null -> MarkdownListRow(numbered.first, numbered.second)
        else -> Text(
            inlineMarkdown(trimmed),
            style = AnkyType.Body.copy(fontSize = 16.sp),
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
        Text(marker, style = AnkyType.Body.copy(fontSize = 16.sp, color = AnkyColors.Gold.copy(alpha = 0.72f)))
        Text(inlineMarkdown(body), style = AnkyType.Body.copy(fontSize = 16.sp))
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

private fun wordCountText(text: String): String {
    val count = text.splitToSequence(Regex("\\s+")).filter { it.isNotBlank() }.count()
    return "$count ${if (count == 1) "word" else "words"}"
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

private val CopyMagenta = Color(0xFFFF3BD4)
