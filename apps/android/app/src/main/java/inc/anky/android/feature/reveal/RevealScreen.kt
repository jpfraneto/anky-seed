package inc.anky.android.feature.reveal

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun RevealScreen(
    viewModel: RevealViewModel,
    onBack: () -> Unit,
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val artifact = state.artifact

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
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 28.dp)
                    .padding(top = 20.dp, bottom = 44.dp),
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
                val status = reflectionStatus(state)
                Text(
                    status,
                    style = AnkyType.Caption.copy(color = AnkyColors.Paper.copy(alpha = 0.52f)),
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .padding(top = 14.dp)
                        .fillMaxWidth(),
                )
                if (state.canAskAnky) {
                    Box(Modifier.padding(top = 14.dp)) {
                        ThreadedActionButton(
                            title = if (state.isAsking) "asking anky" else "ask anky",
                            badge = "reflection",
                            isLoading = state.isAsking,
                            enabled = !state.isAsking,
                            onClick = viewModel::askAnky,
                        )
                    }
                }
                Box(Modifier.padding(top = if (state.canAskAnky) 14.dp else 16.dp)) {
                    QuietCopyButton(
                        title = if (state.didCopyText) "copied all text" else "copy all text",
                        onClick = {
                            context.copyText("Anky text", artifact.reconstructedText)
                            viewModel.markTextCopied()
                        },
                    )
                }
                state.reflection?.let { reflection ->
                    Column(
                        modifier = Modifier.padding(top = 20.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(reflection.title.lowercase(), style = AnkyType.Heading.copy(fontSize = 23.sp))
                        MarkdownishText(reflection.reflection)
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
    }
}

@Composable
private fun RevealHeader(date: String, time: String, metadata: String, onBack: () -> Unit) {
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
            Spacer(Modifier.size(40.dp))
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
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.weight(1f).height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.22f)))
            Icon(
                imageVector = Icons.Filled.Lock,
                contentDescription = null,
                tint = AnkyColors.GoldSoft,
                modifier = Modifier.size(14.dp),
            )
            Box(Modifier.weight(1f).height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.22f)))
        }
        Text(
            "your writing is yours. it only leaves your device if you ask for a reflection. it is deleted after processing and not stored anywhere. anky does not have a database",
            style = AnkyType.Caption.copy(color = AnkyColors.Paper.copy(alpha = 0.62f), fontWeight = FontWeight.Normal),
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun ThreadedActionButton(title: String, badge: String, isLoading: Boolean, enabled: Boolean, onClick: () -> Unit) {
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
                Spacer(Modifier.weight(1f))
                Text(
                    badge.lowercase(),
                    style = AnkyType.Caption.copy(fontSize = 11.sp, color = AnkyColors.GoldSoft),
                    modifier = Modifier
                        .clip(RoundedCornerShape(percent = 50))
                        .background(Color.Black.copy(alpha = 0.2f))
                        .border(1.dp, AnkyColors.Gold.copy(alpha = 0.22f), RoundedCornerShape(percent = 50))
                        .padding(horizontal = 9.dp, vertical = 5.dp),
                )
            }
        }
    }
}

@Composable
private fun QuietCopyButton(title: String, onClick: () -> Unit) {
    androidx.compose.material3.TextButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().height(42.dp).clip(RoundedCornerShape(14.dp)).background(Color.Black.copy(alpha = 0.16f)).border(1.dp, AnkyColors.Gold.copy(alpha = 0.18f), RoundedCornerShape(14.dp)),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Outlined.ContentCopy,
                contentDescription = null,
                tint = AnkyColors.Paper.copy(alpha = 0.7f),
                modifier = Modifier.size(14.dp),
            )
            Text(title.lowercase(), style = AnkyType.Caption.copy(color = AnkyColors.Paper.copy(alpha = 0.7f)))
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
