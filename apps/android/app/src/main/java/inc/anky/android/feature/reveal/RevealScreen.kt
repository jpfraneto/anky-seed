package inc.anky.android.feature.reveal

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.view.HapticFeedbackConstants
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
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
import inc.anky.android.core.mirror.ReflectionCreditPromptState
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

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
    val scope = rememberCoroutineScope()
    var confirmDelete by remember { mutableStateOf(false) }
    var didTapReflectionPrompt by remember { mutableStateOf(false) }
    var copiedSection by remember { mutableStateOf<RevealCopySection?>(null) }
    val activeCopySection = if (
        state.reflection != null &&
        scrollState.maxValue > 0 &&
        scrollState.value > scrollState.maxValue * 0.55f
    ) {
        RevealCopySection.Reflection
    } else {
        RevealCopySection.Writing
    }

    LaunchedEffect(copiedSection) {
        val section = copiedSection ?: return@LaunchedEffect
        delay(480)
        if (copiedSection == section) copiedSection = null
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
                    .padding(top = 20.dp, bottom = 118.dp),
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
                PrivacyDivider(Modifier.padding(top = 28.dp))
                Box(
                    Modifier
                        .padding(top = 20.dp)
                        .fillMaxWidth()
                        .height(1.dp)
                        .background(AnkyColors.Gold.copy(alpha = 0.13f)),
                )
                if (state.isAsking) {
                    MirrorWitnessLoadingView(Modifier.padding(top = 14.dp))
                }
                val status = reflectionStatus(state)
                if (status.isNotEmpty()) {
                    Text(
                        status,
                        style = AnkyType.Caption.copy(color = AnkyColors.Paper.copy(alpha = 0.52f)),
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .padding(top = 14.dp)
                            .fillMaxWidth(),
                    )
                }
                if (state.canAskAnky) {
                    Text(
                        state.creditPromptMessage,
                        style = AnkyType.Caption.copy(
                            fontSize = 13.sp,
                            color = if (state.creditPromptState == ReflectionCreditPromptState.Unavailable) {
                                AnkyColors.Danger.copy(alpha = 0.82f)
                            } else {
                                AnkyColors.GoldSoft.copy(alpha = 0.82f)
                            },
                        ),
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .padding(top = 14.dp)
                            .fillMaxWidth(),
                    )
                    Box(Modifier.padding(top = 10.dp)) {
                        ThreadedActionButton(
                            title = if (state.isAsking) "anky is reflecting" else "ask anky",
                            isLoading = state.isAsking,
                            enabled = state.canSubmitReflectionRequest,
                            onClick = viewModel::askAnky,
                        )
                    }
                }
                if (state.shouldShowCreditsLink) {
                    Text(
                        "open credits",
                        style = AnkyType.Caption.copy(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = AnkyColors.GoldSoft),
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .padding(top = 10.dp)
                            .fillMaxWidth(),
                    )
                }
                state.reflection?.let { reflection ->
                    Column(
                        modifier = Modifier.padding(top = 20.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(reflection.title.lowercase(), style = AnkyType.Heading.copy(fontSize = 23.sp))
                        MarkdownishText(reflection.reflection)
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
                state.error?.let {
                    Text(
                        it,
                        color = AnkyColors.Danger,
                        style = AnkyType.Caption,
                        modifier = Modifier
                            .padding(top = 18.dp)
                            .fillMaxWidth(),
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
        artifact?.let { currentArtifact ->
            FloatingCopyButton(
                section = activeCopySection,
                isCopied = copiedSection == activeCopySection,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 88.dp, end = 16.dp),
                onClick = {
                    val section = activeCopySection
                    val textToCopy = when (section) {
                        RevealCopySection.Writing -> currentArtifact.reconstructedText
                        RevealCopySection.Reflection -> state.reflection
                            ?.let { "${it.title}\n\n${it.reflection}" }
                            ?: currentArtifact.reconstructedText
                    }
                    view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    context.copyText(
                        if (section == RevealCopySection.Writing) "Anky writing" else "Anky reflection",
                        textToCopy,
                    )
                    copiedSection = section
                },
            )
        }
        if (state.canSubmitReflectionRequest && !didTapReflectionPrompt) {
            AskReflectionFloatingButton(
                isAsking = state.isAsking,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 22.dp, vertical = 18.dp),
                onClick = {
                    view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    didTapReflectionPrompt = true
                    scope.launch { scrollState.animateScrollTo(scrollState.maxValue) }
                },
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
private fun ThreadedActionButton(title: String, isLoading: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(18.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = AnkyColors.ButtonFill,
            contentColor = AnkyColors.Paper,
            disabledContainerColor = AnkyColors.ButtonFill.copy(alpha = 0.72f),
            disabledContentColor = AnkyColors.Paper.copy(alpha = 0.7f),
        ),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
        modifier = Modifier
            .fillMaxWidth()
            .height(70.dp)
            .border(1.dp, AnkyColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(18.dp)),
    ) {
        Box(Modifier.fillMaxSize().clip(RoundedCornerShape(18.dp))) {
            Canvas(Modifier.fillMaxSize()) {
                drawRect(
                    brush = Brush.horizontalGradient(
                        colors = listOf(
                            Color.Transparent,
                            AnkyColors.Violet.copy(alpha = 0.10f),
                            Color.Transparent,
                        ),
                    ),
                )
                drawLine(
                    color = AnkyColors.Gold.copy(alpha = 0.22f),
                    start = androidx.compose.ui.geometry.Offset(0f, 10.dp.toPx()),
                    end = androidx.compose.ui.geometry.Offset(size.width, 10.dp.toPx()),
                    strokeWidth = 1.dp.toPx(),
                )
                drawLine(
                    color = AnkyColors.Gold.copy(alpha = 0.16f),
                    start = androidx.compose.ui.geometry.Offset(0f, size.height - 10.dp.toPx()),
                    end = androidx.compose.ui.geometry.Offset(size.width, size.height - 10.dp.toPx()),
                    strokeWidth = 1.dp.toPx(),
                )
            }
            Row(
                modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        color = AnkyColors.Paper,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(17.dp),
                    )
                } else {
                    Icon(
                        imageVector = Icons.Filled.AutoAwesome,
                        contentDescription = null,
                        tint = AnkyColors.Paper,
                        modifier = Modifier.size(17.dp),
                    )
                }
                Text(title.lowercase(), style = AnkyType.Body.copy(fontSize = 16.sp, fontWeight = FontWeight.SemiBold))
            }
        }
    }
}

@Composable
private fun MirrorWitnessLoadingView(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(width = 70.dp, height = 54.dp), contentAlignment = Alignment.CenterStart) {
            Image(
                painter = painterResource(R.drawable.anky040),
                contentDescription = null,
                modifier = Modifier.size(54.dp),
            )
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = 7.dp, bottom = 5.dp)
                    .size(width = 18.dp, height = 24.dp)
                    .clip(RoundedCornerShape(5.dp))
                    .background(AnkyColors.Paper.copy(alpha = 0.10f))
                    .border(1.4.dp, AnkyColors.GoldSoft.copy(alpha = 0.82f), RoundedCornerShape(5.dp)),
            )
        }
        Text(
            "Anky is reflecting...",
            style = AnkyType.Caption.copy(fontSize = 13.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.62f)),
        )
    }
}

@Composable
private fun FloatingCopyButton(
    section: RevealCopySection,
    isCopied: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val label = when (section) {
        RevealCopySection.Writing -> if (isCopied) "copied writing" else "copy writing"
        RevealCopySection.Reflection -> if (isCopied) "copied reflection" else "copy reflection"
    }
    TextButton(
        onClick = onClick,
        modifier = modifier
            .height(38.dp)
            .clip(RoundedCornerShape(percent = 50))
            .background(Color(0xFF120F0B))
            .border(
                1.dp,
                if (isCopied) CopyMagenta.copy(alpha = 0.72f) else AnkyColors.Gold.copy(alpha = 0.32f),
                RoundedCornerShape(percent = 50),
            ),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = if (isCopied) Icons.Filled.Check else Icons.Outlined.ContentCopy,
                contentDescription = null,
                tint = if (isCopied) CopyMagenta else AnkyColors.Paper,
                modifier = Modifier.size(12.dp),
            )
            Text(
                label,
                style = AnkyType.Caption.copy(
                    fontSize = 11.sp,
                    color = if (isCopied) CopyMagenta else AnkyColors.Paper,
                    fontWeight = FontWeight.SemiBold,
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun AskReflectionFloatingButton(
    isAsking: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = !isAsking,
        shape = RoundedCornerShape(percent = 50),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.Transparent,
            contentColor = AnkyColors.Ink,
            disabledContainerColor = Color.Transparent,
            disabledContentColor = AnkyColors.Ink.copy(alpha = 0.65f),
        ),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
        modifier = modifier.height(46.dp),
    ) {
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(percent = 50))
                .background(
                    Brush.linearGradient(
                        listOf(
                            AnkyColors.Gold,
                            Color(0xFFFFF8DC),
                            AnkyColors.Gold,
                        ),
                    ),
                )
                .border(1.dp, Color.White.copy(alpha = 0.55f), RoundedCornerShape(percent = 50))
                .padding(horizontal = 16.dp)
                .fillMaxHeight(),
            contentAlignment = Alignment.Center,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                if (isAsking) {
                    CircularProgressIndicator(
                        color = AnkyColors.Ink,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(13.dp),
                    )
                } else {
                    Icon(
                        imageVector = Icons.Filled.AutoAwesome,
                        contentDescription = null,
                        tint = AnkyColors.Ink,
                        modifier = Modifier.size(13.dp),
                    )
                }
                Text(
                    if (isAsking) "anky is reflecting" else "ask anky",
                    style = AnkyType.Caption.copy(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = AnkyColors.Ink),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Icon(
                    imageVector = Icons.Filled.KeyboardArrowDown,
                    contentDescription = null,
                    tint = AnkyColors.Ink,
                    modifier = Modifier.size(15.dp),
                )
            }
        }
    }
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
            else -> {
                val nextStrong = text.indexOf("**", startIndex = index).takeIf { it >= 0 } ?: text.length
                val nextCode = text.indexOf('`', startIndex = index).takeIf { it >= 0 } ?: text.length
                val next = minOf(nextStrong, nextCode)
                append(text.substring(index, next))
                index = next
            }
        }
    }
}

private fun reflectionStatus(state: RevealState): String =
    when {
        state.reflection != null -> ""
        state.canAskAnky -> "ready to ask anky for reflection"
        state.artifact?.isComplete == false -> "write 8 minutes to ask anky for reflection"
        else -> ""
    }

private fun wordCountText(text: String): String {
    val count = text.splitToSequence(Regex("\\s+")).filter { it.isNotBlank() }.count()
    return "$count ${if (count == 1) "word" else "words"}"
}

private fun Context.copyText(label: String, text: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

private enum class RevealCopySection {
    Writing,
    Reflection,
}

private val CopyMagenta = Color(0xFFFF3BD4)
