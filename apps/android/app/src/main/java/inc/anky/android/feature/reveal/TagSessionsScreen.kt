package inc.anky.android.feature.reveal

import androidx.compose.foundation.background
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import inc.anky.android.R
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.theme.AnkyType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/**
 * Sessions that share a tag — lazure reading room, refreshed on every
 * return like the iOS list refreshes on appear.
 */
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
        modifier = Modifier.fillMaxSize(),
    ) {
        LazureWall(mood = LazureMood.Dawn)
        Column(Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(LazurePigments.ankyPaper.copy(alpha = 0.94f))
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onBack) {
                    Icon(
                        imageVector = Icons.Filled.ChevronLeft,
                        contentDescription = backLabel,
                        tint = LazurePigments.ankyInk,
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
                        style = AnkyType.Heading.copy(
                            fontFamily = FontFamily.Serif,
                            fontSize = 30.sp,
                            fontWeight = FontWeight.Bold,
                            color = LazurePigments.ankyViolet,
                        ),
                        modifier = Modifier.padding(top = 18.dp),
                    )
                }
                if (sessions.value.isEmpty()) {
                    item {
                        Text(
                            emptyTagSessionsLabel,
                            style = AnkyType.Mono.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium, color = LazurePigments.ankyInk.copy(alpha = 0.68f)),
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
    val importedReflection = stringResource(R.string.imported_reflection_title)
    val fragmentTitle = stringResource(R.string.session_fragment_title)
    val title = summary.localizedTagSessionTitle(importedReflection, fragmentTitle)
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
                title,
                style = AnkyType.Mono.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold, color = LazurePigments.ankyGold.copy(alpha = 0.9f)),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                summary.createdAt.formattedForTagSession(),
                style = AnkyType.Mono.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = LazurePigments.ankyInkSoft.copy(alpha = 0.88f)),
            )
            Text(
                "${summary.wordCount} $wordLabel",
                style = AnkyType.Mono.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = LazurePigments.ankyInkSoft.copy(alpha = 0.72f)),
            )
        }
        Icon(
            imageVector = Icons.Filled.ChevronRight,
            contentDescription = null,
            tint = LazurePigments.ankyGold.copy(alpha = 0.7f),
            modifier = Modifier.size(13.dp),
        )
    }
    Box(
        Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(LazurePigments.hairline),
    )
}

internal fun java.time.Instant.formattedForTagSession(): String =
    DateTimeFormatter
        .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .withZone(ZoneId.systemDefault())
        .format(this)

private fun SessionSummary.localizedTagSessionTitle(importedReflection: String, fragmentTitle: String): String =
    when (title) {
        "Imported reflection" -> importedReflection
        "Fragment" -> fragmentTitle
        else -> title
    }
