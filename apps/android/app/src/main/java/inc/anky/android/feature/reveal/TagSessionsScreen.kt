package inc.anky.android.feature.reveal

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import inc.anky.android.R
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

@Composable
fun TagSessionsScreen(
    tag: String,
    sessionIndexStore: SessionIndexStore,
    archive: LocalAnkyArchive,
    onBack: () -> Unit,
    onOpenReveal: (String) -> Unit,
) {
    val sessions = remember { mutableStateOf<List<SessionSummary>>(emptyList()) }
    val lifecycleOwner = LocalLifecycleOwner.current
    val backLabel = stringResource(R.string.back)
    val emptyTagSessionsLabel = stringResource(R.string.tag_no_saved_sessions)

    fun refreshSessions() {
        sessions.value = sessionIndexStore.sessionsWithTag(tag)
    }

    LaunchedEffect(tag) {
        refreshSessions()
    }

    DisposableEffect(lifecycleOwner, tag) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                refreshSessions()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AnkyColors.Ink),
    ) {
        RevealTagTexture()
        Column(Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(AnkyColors.Ink.copy(alpha = 0.96f))
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onBack) {
                    Icon(
                        imageVector = Icons.Filled.ChevronLeft,
                        contentDescription = backLabel,
                        tint = AnkyColors.Gold,
                        modifier = Modifier.size(30.dp),
                    )
                }
                Spacer(Modifier.weight(1f))
            }

            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 22.dp)
                    .padding(bottom = 48.dp),
                verticalArrangement = Arrangement.spacedBy(0.dp),
            ) {
                item {
                    Text(
                        tag,
                        style = AnkyType.Heading.copy(fontSize = 30.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Gold),
                        modifier = Modifier.padding(top = 18.dp),
                    )
                }
                if (sessions.value.isEmpty()) {
                    item {
                        Text(
                            emptyTagSessionsLabel,
                            style = AnkyType.Mono.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.68f)),
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                } else {
                    items(sessions.value, key = { it.hash }) { summary ->
                        if (runCatching { archive.load(summary.hash) }.isSuccess) {
                            TagSessionRow(summary = summary, onOpenReveal = onOpenReveal)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TagSessionRow(summary: SessionSummary, onOpenReveal: (String) -> Unit) {
    val wordLabel = stringResource(if (summary.wordCount == 1) R.string.word else R.string.words)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOpenReveal(summary.hash) }
            .padding(vertical = 15.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                summary.title,
                style = AnkyType.Mono.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Gold.copy(alpha = 0.9f)),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                summary.createdAt.formattedForTagSession(),
                style = AnkyType.Mono.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.58f)),
            )
            Text(
                "${summary.wordCount} $wordLabel",
                style = AnkyType.Mono.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.48f)),
            )
        }
        Icon(
            imageVector = Icons.Filled.ChevronRight,
            contentDescription = null,
            tint = AnkyColors.Gold.copy(alpha = 0.7f),
            modifier = Modifier.size(13.dp),
        )
    }
    Box(
        Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(AnkyColors.Gold.copy(alpha = 0.13f)),
    )
}

internal fun java.time.Instant.formattedForTagSession(): String =
    DateTimeFormatter
        .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .withZone(ZoneId.systemDefault())
        .format(this)

@Composable
private fun RevealTagTexture() {
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
                topLeft = Offset(
                    x = (size.width - width) / 2f,
                    y = bloomCenterY - height / 2f,
                ),
                size = Size(width, height),
            )
        }
    }
}
