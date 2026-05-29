package inc.anky.android.feature.reveal

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
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
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.ui.components.AnkyChatAction
import inc.anky.android.ui.components.AnkyConversationPrompt
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay

@Composable
fun RevealScreen(
    viewModel: RevealViewModel,
    onBack: () -> Unit,
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val view = LocalView.current
    val artifact = state.artifact
    val scrollState = rememberScrollState()
    var confirmDelete by remember { mutableStateOf(false) }
    var showCopyBurst by remember { mutableStateOf(false) }

    LaunchedEffect(showCopyBurst) {
        if (!showCopyBurst) return@LaunchedEffect
        delay(740)
        showCopyBurst = false
    }

    LaunchedEffect(state.isDeleted) {
        if (state.isDeleted) onBack()
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
                        .padding(top = 20.dp, bottom = if (state.reflection == null) 238.dp else 72.dp),
                verticalArrangement = Arrangement.spacedBy(0.dp),
            ) {
                Text(
                    text = artifact.reconstructedText,
                    style = AnkyType.Body.copy(fontSize = 19.sp, lineHeight = 28.sp),
                    modifier = Modifier
                        .padding(vertical = 8.dp)
                        .testTag("reconstructed-text")
                        .pointerInput(artifact.reconstructedText) {
                            detectTapGestures {
                                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                                context.copyText("Anky writing", artifact.reconstructedText)
                                showCopyBurst = true
                            }
                        },
                )
                PrivacyDivider(Modifier.padding(top = 28.dp))
                state.reflection?.let { reflection ->
                    Column(
                        modifier = Modifier
                            .padding(top = 36.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(reflection.title.lowercase(), style = AnkyType.Heading.copy(fontSize = 23.sp))
                        MarkdownishText(reflection.displayBody)
                        reflection.creditsRemaining?.let { creditsRemaining ->
                            Text(
                                "$creditsRemaining ${if (creditsRemaining == 1) "reflection" else "reflections"} left",
                                style = AnkyType.Caption.copy(
                                    fontSize = 12.sp,
                                    color = AnkyColors.GoldSoft.copy(alpha = 0.78f),
                                ),
                            )
                        }
                    }
                }
            }
        }
        if (showCopyBurst) {
            Text(
                "📋",
                fontSize = 26.sp,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 120.dp, end = 28.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF120F0B).copy(alpha = 0.92f))
                    .border(1.dp, CopyMagenta.copy(alpha = 0.72f), CircleShape)
                    .padding(8.dp),
            )
        }
        if (state.reflection == null) {
            RevealAnkyReflectionChat(
                state = state,
                onAsk = viewModel::askAnky,
                onTryAgain = onBack,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 16.dp, vertical = 16.dp),
            )
        }
        if (confirmDelete) {
            AlertDialog(
                onDismissRequest = { confirmDelete = false },
                title = { Text("delete forever?") },
                text = {
                    Text("This permanently deletes this writing session and its saved reflection from this device. This cannot be undone.")
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            confirmDelete = false
                            viewModel.deleteSession()
                        },
                    ) {
                        Text("delete forever")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { confirmDelete = false }) {
                        Text("cancel")
                    }
                },
                containerColor = AnkyColors.Ink,
                titleContentColor = AnkyColors.Paper,
                textContentColor = AnkyColors.PaperMuted,
            )
        }
    }
}

@Composable
private fun RevealHeader(
    date: String,
    time: String,
    metadata: String,
    onBack: () -> Unit,
    canDelete: Boolean,
    isDeleting: Boolean,
    onDelete: () -> Unit,
) {
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
                    contentDescription = "Back",
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
                    modifier = Modifier.size(40.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.24f)).border(1.dp, AnkyColors.Gold.copy(alpha = 0.24f), CircleShape),
                ) {
                    Icon(
                        imageVector = Icons.Filled.Delete,
                        contentDescription = "delete forever",
                        tint = AnkyColors.Paper,
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
private fun RevealTexture() {
    Canvas(Modifier.fillMaxSize()) {
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
private fun PrivacyDivider(modifier: Modifier = Modifier) {
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
                    contentDescription = if (expanded) "Hide privacy note" else "Show privacy note",
                    tint = AnkyColors.GoldSoft,
                    modifier = Modifier.size(17.dp),
                )
            }
            Box(Modifier.weight(1f).height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.22f)))
        }
        if (expanded) {
            Text(
                "your writing only leaves this device if you ask for a reflection. the mirror processes it transiently and does not keep a writing archive.",
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
    onTryAgain: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (state.isAsking) {
            RevealThinkingPrompt(status = state.reflectionStatusMessage)
        } else if (state.artifact?.isComplete == false) {
            AnkyConversationPrompt(
                message = shortSessionMessage(state),
                actions = listOf(AnkyChatAction("write again", isPrimary = true, action = onTryAgain)),
                onClose = {},
            )
        } else {
            AnkyConversationPrompt(
                message = reflectionInvitationMessage(state),
                actions = if (state.canSubmitReflectionRequest) {
                    listOf(AnkyChatAction("reflect with anky", isPrimary = true, action = onAsk))
                } else {
                    emptyList()
                },
                onClose = {},
            )
        }

        state.error?.let { errorMessage ->
            Text(
                errorMessage.lowercase(),
                style = AnkyType.Mono.copy(fontSize = 12.sp, lineHeight = 16.sp, color = Color.Red.copy(alpha = 0.82f)),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        if (state.shouldShowCreditsLink) {
            Text(
                "open reflection credits",
                style = AnkyType.Caption.copy(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AnkyColors.GoldSoft),
            )
        }
    }
}

@Composable
private fun RevealThinkingPrompt(status: String) {
    val messages = listOf(
        "i am reading slowly. not looking for a summary.",
        "i am listening for the pressure under the words.",
        "i am keeping the thread intact while the mirror answers.",
        "still here. some reflections take a little longer.",
        "i am bringing it back without flattening it.",
        "stay close. the page is not gone.",
    )
    val pulse by rememberInfiniteTransition(label = "reveal-thinking").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = androidx.compose.animation.core.infiniteRepeatable(
            animation = androidx.compose.animation.core.tween(durationMillis = 3400),
        ),
        label = "reveal-thinking-value",
    )
    val index = ((pulse * messages.size).toInt()).coerceIn(0, messages.lastIndex)
    val firstLine = status.ifBlank { "i am staying with this .anky." }
    Box(Modifier.padding(top = 24.dp)) {
        AnkyConversationPrompt(
            message = "$firstLine\n\n${messages[index]}",
            onClose = {},
        )
        ReflectionSeekingSpinner(Modifier.align(Alignment.TopCenter).offset(y = (-24).dp))
    }
}

@Composable
private fun ReflectionSeekingSpinner(modifier: Modifier = Modifier) {
    val spin by rememberInfiniteTransition(label = "mirror-spinner").animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = androidx.compose.animation.core.infiniteRepeatable(
            animation = androidx.compose.animation.core.tween(durationMillis = 2400, easing = LinearEasing),
        ),
        label = "mirror-spinner-value",
    )
    Canvas(modifier.size(58.dp)) {
        drawCircle(AnkyColors.Gold.copy(alpha = 0.08f), style = Stroke(width = 8.dp.toPx()))
        drawArc(
            color = AnkyColors.GoldSoft.copy(alpha = 0.36f),
            startAngle = spin,
            sweepAngle = 100f,
            useCenter = false,
            size = Size(size.width, size.height),
            style = Stroke(width = 8.dp.toPx(), cap = StrokeCap.Round),
        )
        drawArc(
            color = AnkyColors.Paper.copy(alpha = 0.18f),
            startAngle = -spin * 0.63f,
            sweepAngle = 50f,
            useCenter = false,
            size = Size(size.width, size.height),
            style = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round),
        )
    }
}

private fun reflectionInvitationMessage(state: RevealState): String =
    when {
        state.creditsLoading -> "i am checking whether the mirror is open.\n\nyour writing stays here unless you ask me to reflect it."
        state.creditPromptState == inc.anky.android.core.mirror.ReflectionCreditPromptState.Unavailable ->
            "i want to reflect this with you, but reflection access is empty right now."
        state.creditPromptState == inc.anky.android.core.mirror.ReflectionCreditPromptState.Unknown ->
            "the mirror may be open.\n\nyour writing only leaves this device if you ask me now."
        else -> "i can sit with this and bring back a reflection.\n\nyour writing only leaves this device if you ask me now."
    }

private fun shortSessionMessage(state: RevealState): String =
    if (state.artifact?.isComplete == false) {
        stableShortSessionMessage(
            hash = state.artifact.hash,
            wordCount = state.artifact.reconstructedText
                .splitToSequence(Regex("\\s+"))
                .filter { it.isNotBlank() }
                .count(),
        )
    } else {
        "ready to mirror this artifact"
    }

private fun stableShortSessionMessage(hash: String, wordCount: Int): String {
    val messages = listOf(
        "keep going until you get to ${AnkyDuration.CompleteRitualMinutes} minutes.",
        "the thread opened, but it needs the full ${AnkyDuration.CompleteRitualMinutes} minutes.",
        "that was a spark. stay with it until ${AnkyDuration.CompleteRitualMinutes} minutes.",
        "anky needs the whole ritual. come back and write ${AnkyDuration.CompleteRitualMinutes} minutes.",
        "you stopped too soon. try again and cross the ${AnkyDuration.CompleteRitualMinutes}-minute mark.",
    )
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
