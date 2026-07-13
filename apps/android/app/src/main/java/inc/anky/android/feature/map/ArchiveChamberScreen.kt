package inc.anky.android.feature.map

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.R
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.ui.lazure.AnkySunGlyph
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.theme.AnkyType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The archive chamber — the map feature's live surface, ported from the
 * iOS ArchiveChamberView: a plain searchable list of every writing,
 * bucketed by local day under "Today" / "Yesterday" / dated headers, with
 * the practice totals (ankys, minutes, streak) breathing above it. Rows
 * never speak protocol status words and never show counts — the words
 * themselves are the row (iOS canon).
 */
@Composable
fun ArchiveChamberScreen(
    viewModel: MapViewModel,
    onOpenReveal: (String) -> Unit,
) {
    LaunchedEffect(Unit) {
        viewModel.refresh()
        viewModel.refreshArchiveEntries()
    }
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val entries = viewModel.archiveEntries.collectAsStateWithLifecycle().value
    var searchQuery by rememberSaveable { mutableStateOf("") }
    var searchCache by remember { mutableStateOf<Map<String, String>>(emptyMap()) }

    // Reconstructing and lowercasing every writing is not free — build the
    // search cache once per load, off the main thread, never per keystroke.
    LaunchedEffect(entries) {
        searchCache = withContext(Dispatchers.Default) {
            ArchiveSearchIndex.build(entries)
        }
    }

    val visibleEntries = ArchiveSearchIndex.filter(entries, searchCache, searchQuery)
    val sections = archiveDaySections(visibleEntries)
    val hasQuery = searchQuery.trim().isNotEmpty()

    Box(Modifier.fillMaxSize().testTag("archive-chamber")) {
        LazureWall(mood = LazureMood.Dawn)
        Column(Modifier.fillMaxSize()) {
            ArchiveChamberHeader(
                ankys = state.completeAnkyCount,
                minutes = state.totalWritingMinutes,
                streak = state.currentStreak,
            )
            ArchiveSearchBar(
                query = searchQuery,
                onQueryChange = { searchQuery = it },
                modifier = Modifier
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 8.dp),
            )
            if (visibleEntries.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        if (hasQuery) {
                            stringResource(R.string.archive_empty_search)
                        } else {
                            stringResource(R.string.archive_empty)
                        },
                        style = AnkyType.Body.copy(
                            fontFamily = FontFamily.Serif,
                            fontSize = 17.sp,
                            color = LazurePigments.ankyInkSoft,
                        ),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 40.dp, vertical = 48.dp),
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(0.dp),
                ) {
                    sections.forEach { section ->
                        item(key = "day-${section.day}") {
                            ArchiveDayHeader(section)
                        }
                        section.entries.forEachIndexed { index, anky ->
                            item(key = anky.hash) {
                                ArchiveListRow(
                                    anky = anky,
                                    onOpen = { onOpenReveal(anky.hash) },
                                )
                                if (index < section.entries.size - 1) {
                                    Box(
                                        Modifier
                                            .fillMaxWidth()
                                            .padding(start = 68.dp)
                                            .height(1.dp)
                                            .background(LazurePigments.hairline),
                                    )
                                }
                            }
                        }
                    }
                    item {
                        Spacer(Modifier.height(120.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun ArchiveChamberHeader(
    ankys: Int,
    minutes: Int,
    streak: Int,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(top = 18.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(R.string.archive_your_writings),
            style = AnkyType.Title.copy(
                fontFamily = FontFamily.Serif,
                fontSize = 36.sp,
                fontWeight = FontWeight.Normal,
                color = LazurePigments.ankyInk,
            ),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(18.dp))
                .background(
                    Brush.linearGradient(
                        listOf(
                            LazurePigments.ankyPaper.copy(alpha = 0.78f),
                            LazurePigments.ankyPaperDeep.copy(alpha = 0.55f),
                        ),
                    ),
                )
                .border(0.5.dp, LazurePigments.hairline, RoundedCornerShape(18.dp))
                .padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ArchiveStatCell(ankys.toString(), stringResource(R.string.you_stat_ankys), Modifier.weight(1f))
            ArchiveStatsDivider()
            ArchiveStatCell(minutes.toString(), stringResource(R.string.you_stat_minutes), Modifier.weight(1f))
            ArchiveStatsDivider()
            ArchiveStatCell(streak.toString(), stringResource(R.string.you_stat_streak), Modifier.weight(1f))
        }
    }
}

@Composable
private fun ArchiveStatCell(value: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(
            value,
            style = AnkyType.Body.copy(
                fontFamily = FontFamily.Serif,
                fontSize = 22.sp,
                fontWeight = FontWeight.Normal,
                color = LazurePigments.ankyInk,
            ),
            maxLines = 1,
        )
        Text(
            label,
            style = AnkyType.Caption.copy(
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = LazurePigments.ankyInkSoft,
            ),
            maxLines = 1,
        )
    }
}

@Composable
private fun ArchiveStatsDivider() {
    Box(
        Modifier
            .size(width = 1.dp, height = 30.dp)
            .background(LazurePigments.ankyGold.copy(alpha = 0.18f)),
    )
}

@Composable
private fun ArchiveDayHeader(section: ArchiveDaySection) {
    val title = when {
        section.isToday -> stringResource(R.string.archive_today)
        section.isYesterday -> stringResource(R.string.archive_yesterday)
        else -> DateTimeFormatter
            .ofPattern("MMM d, yyyy", Locale.getDefault())
            .format(section.day)
    }
    Text(
        title,
        style = AnkyType.Heading.copy(
            fontFamily = FontFamily.Serif,
            fontSize = 21.sp,
            fontWeight = FontWeight.Normal,
            color = LazurePigments.ankyInkSoft,
        ),
        modifier = Modifier.padding(top = 22.dp, bottom = 4.dp),
    )
}

@Composable
private fun ArchiveSearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val searchLabel = stringResource(R.string.archive_search)
    val clearLabel = stringResource(R.string.archive_clear_search)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(44.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(
                Brush.linearGradient(
                    listOf(
                        LazurePigments.ankyPaper.copy(alpha = 0.78f),
                        LazurePigments.ankyPaperDeep.copy(alpha = 0.55f),
                    ),
                ),
            )
            .border(0.5.dp, LazurePigments.hairline, RoundedCornerShape(14.dp))
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            imageVector = Icons.Filled.Search,
            contentDescription = null,
            tint = LazurePigments.ankyInkSoft.copy(alpha = 0.8f),
            modifier = Modifier.size(16.dp),
        )
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (query.isEmpty()) {
                Text(
                    searchLabel,
                    style = AnkyType.Body.copy(fontSize = 16.sp, color = LazurePigments.ankyInkSoft.copy(alpha = 0.7f)),
                    maxLines = 1,
                )
            }
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = AnkyType.Body.copy(fontSize = 16.sp, color = LazurePigments.ankyInk),
                cursorBrush = SolidColor(LazurePigments.ankyGold),
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("archive-search-field"),
            )
        }
        if (query.isNotEmpty()) {
            IconButton(
                onClick = { onQueryChange("") },
                modifier = Modifier.size(28.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = clearLabel,
                    tint = LazurePigments.ankyInkSoft.copy(alpha = 0.6f),
                    modifier = Modifier.size(15.dp),
                )
            }
        }
    }
}

/**
 * One archived writing: the spiral sun in a soft gold circle, two lines
 * of the words themselves, the time underneath, the session length and a
 * chevron on the right. No status words, no counts — iOS canon.
 */
@Composable
private fun ArchiveListRow(
    anky: SavedAnky,
    onOpen: () -> Unit,
) {
    val preview = archiveRowPreview(anky.reconstructedText)
    val time = DateTimeFormatter
        .ofPattern("h:mm a", Locale.getDefault())
        .withZone(ZoneId.systemDefault())
        .format(anky.createdAt)
        .lowercase()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .padding(vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(54.dp)
                .clip(CircleShape)
                .background(LazurePigments.ankyGold.copy(alpha = 0.14f)),
            contentAlignment = Alignment.Center,
        ) {
            AnkySunGlyph(size = 30.dp, color = LazurePigments.ankyGold)
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                preview,
                style = AnkyType.Body.copy(
                    fontFamily = FontFamily.Serif,
                    fontSize = 17.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.Normal,
                    color = LazurePigments.ankyInk,
                ),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                time,
                style = AnkyType.Caption.copy(
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Normal,
                    color = LazurePigments.ankyInkSoft.copy(alpha = 0.9f),
                ),
                maxLines = 1,
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                AnkyDuration.clock(anky.durationMs),
                style = AnkyType.Body.copy(
                    fontFamily = FontFamily.Serif,
                    fontSize = 17.sp,
                    color = LazurePigments.ankyInk.copy(alpha = 0.85f),
                ),
                maxLines = 1,
            )
            Icon(
                imageVector = Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = LazurePigments.ankyInkSoft.copy(alpha = 0.7f),
                modifier = Modifier.size(13.dp),
            )
        }
    }
}

/** The words themselves, one breath long — newline-flattened, "···" when empty. */
internal fun archiveRowPreview(reconstructedText: String): String {
    val text = reconstructedText
        .trim()
        .replace("\n", " ")
    return text.ifEmpty { "···" }
}
