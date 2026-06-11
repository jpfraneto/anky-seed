package inc.anky.android.feature.map

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.R
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.storage.SessionDay
import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyMapBackground
import inc.anky.android.ui.theme.AnkyType
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun MapScreen(
    viewModel: MapViewModel,
    onOpenReveal: (String) -> Unit,
    onOpenAllAnkys: () -> Unit = {},
) {
    LaunchedEffect(Unit) {
        while (true) {
            viewModel.refresh()
            delay(60_000)
        }
    }
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val selectedDayEpoch = rememberSaveable { mutableStateOf<Long?>(null) }
    val selectedDay = selectedDayEpoch.value?.let { epoch ->
        state.days.firstOrNull { it.dayEpochMs == epoch }
    }
    val labels = mapLabels()

    AnkyMapBackground(modifier = Modifier.testTag("map-screen")) {
        state.errorMessage?.let { error ->
            Text(
                labels.couldNotLoadMap,
                style = AnkyType.Body.copy(color = AnkyColors.Paper),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 72.dp, start = 24.dp, end = 24.dp),
            )
        }
        if (selectedDay == null) {
            TrailMap(
                days = state.days,
                ankys = state.completeAnkyCount,
                minutes = state.totalWritingMinutes,
                streak = state.currentStreak,
                labels = labels,
                onOpenDay = { selectedDayEpoch.value = it.dayEpochMs },
                onOpenAllAnkys = onOpenAllAnkys,
            )
        } else {
            DayDetail(
                day = selectedDay,
                labels = labels,
                onBack = { selectedDayEpoch.value = null },
                onOpenReveal = onOpenReveal,
            )
        }
    }
}

@Composable
fun MapAllAnkysScreen(
    viewModel: MapViewModel,
    onBack: () -> Unit,
    onOpenReveal: (String) -> Unit,
) {
    LaunchedEffect(Unit) {
        viewModel.refresh()
    }
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val labels = mapLabels()
    val sessions = state.completeAnkySessions
    val title = when (sessions.size) {
        0 -> stringResource(R.string.zero_ankys)
        1 -> stringResource(R.string.one_anky_count_format, sessions.size)
        else -> stringResource(R.string.ankys_count_format, sessions.size)
    }

    MapSessionListScreen(
        title = title,
        sessions = sessions,
        emptyMessage = stringResource(R.string.all_ankys_empty_message),
        labels = labels,
        onBack = onBack,
        onOpenReveal = onOpenReveal,
        showsDayInHeader = true,
    )
}

@Composable
private fun TrailMap(
    days: List<SessionDay>,
    ankys: Int,
    minutes: Int,
    streak: Int,
    labels: MapLabels,
    onOpenDay: (SessionDay) -> Unit,
    onOpenAllAnkys: () -> Unit,
) {
    val displayDays = days.reversed()
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val todayIndex = displayDays.indexOfFirst { isToday(it.dayEpochMs) }
    val rowHeight = 104.dp
    val showCurrentDayButton = remember(todayIndex, listState) {
        derivedStateOf {
            todayIndex >= 0 && listState.layoutInfo.visibleItemsInfo.none { it.index == todayIndex }
        }
    }
    val currentDayIsBeforeVisible = remember(todayIndex, listState) {
        derivedStateOf { todayIndex >= 0 && todayIndex < listState.firstVisibleItemIndex }
    }

    LaunchedEffect(todayIndex, displayDays.size) {
        if (todayIndex >= 0) listState.animateScrollToItem(todayIndex)
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val centerPadding = ((maxHeight - rowHeight) / 2).coerceAtLeast(0.dp)
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            contentPadding = PaddingValues(
                top = centerPadding,
                bottom = centerPadding + maxHeight,
            ),
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            if (displayDays.isEmpty()) {
                item {
                    Text(
                        labels.noWritingSaved,
                        style = AnkyType.Body.copy(fontSize = 20.sp, color = AnkyColors.PaperMuted),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 96.dp),
                    )
                }
            }
            itemsIndexed(displayDays, key = { _, day -> day.dayEpochMs }) { index, day ->
                TrailDayNode(
                    day = day,
                    index = index,
                    dayCount = displayDays.size,
                    rowHeight = rowHeight,
                    labels = labels,
                    onOpenDay = onOpenDay,
                )
            }
        }
        if (showCurrentDayButton.value) {
            IconButton(
                onClick = {
                    scope.launch { listState.animateScrollToItem(todayIndex) }
                },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = 18.dp, bottom = 18.dp)
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.12f))
                    .semantics {
                        contentDescription = labels.goToCurrentDay
                    },
            ) {
                Icon(
                    imageVector = if (currentDayIsBeforeVisible.value) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                    contentDescription = null,
                    tint = AnkyColors.Gold,
                    modifier = Modifier.size(30.dp),
                )
            }
        }
        MapStatsPanel(
            ankys = ankys,
            minutes = minutes,
            streak = streak,
            labels = labels,
            onClick = onOpenAllAnkys,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 34.dp, start = 20.dp, end = 20.dp),
        )
    }
}

@Composable
private fun MapStatsPanel(
    ankys: Int,
    minutes: Int,
    streak: Int,
    labels: MapLabels,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(68.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(AnkyColors.Ink.copy(alpha = 0.78f))
            .border(1.dp, AnkyColors.Gold.copy(alpha = 0.22f), RoundedCornerShape(18.dp))
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = labels.openAllAnkys },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        MapStatCell(R.drawable.you_icon_feather_stat, ankys.toString(), labels.ankys)
        MapStatsDivider()
        MapStatCell(R.drawable.you_icon_clock_stat, minutes.toString(), labels.minutes)
        MapStatsDivider()
        MapStatCell(R.drawable.you_icon_flame_stat, streak.toString(), labels.streak)
    }
}

@Composable
private fun RowScope.MapStatCell(icon: Int, value: String, label: String) {
    Row(
        modifier = Modifier.weight(1f).padding(horizontal = 6.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painter = painterResource(icon),
            contentDescription = null,
            modifier = Modifier.size(28.dp),
        )
        Column(Modifier.padding(start = 8.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                value,
                style = AnkyType.Body.copy(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AnkyColors.Paper),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                label,
                style = AnkyType.Caption.copy(fontSize = 10.sp, color = AnkyColors.Paper.copy(alpha = 0.58f)),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun MapStatsDivider() {
    Box(
        Modifier
            .size(width = 1.dp, height = 34.dp)
            .background(AnkyColors.Gold.copy(alpha = 0.18f)),
    )
}

@Composable
private fun TrailDayNode(
    day: SessionDay,
    index: Int,
    dayCount: Int,
    rowHeight: androidx.compose.ui.unit.Dp,
    labels: MapLabels,
    onOpenDay: (SessionDay) -> Unit,
) {
    val today = isToday(day.dayEpochMs)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(rowHeight)
            .clickable { onOpenDay(day) }
            .semantics {
                contentDescription = dayAccessibilityLabel(day, labels.today)
        },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            if (dayCount <= 1) return@Canvas
            val x = size.width / 2f
            val centerY = size.height / 2f
            val startY = if (index == 0) centerY else 0f
            val endY = if (index == dayCount - 1) centerY else size.height
            drawLine(
                color = Color.White.copy(alpha = 0.13f),
                start = Offset(x, startY),
                end = Offset(x, endY),
                strokeWidth = 10.dp.toPx(),
                cap = androidx.compose.ui.graphics.StrokeCap.Round,
            )
            drawLine(
                color = Color.White.copy(alpha = 0.28f),
                start = Offset(x, startY),
                end = Offset(x, endY),
                strokeWidth = 1.2.dp.toPx(),
                cap = androidx.compose.ui.graphics.StrokeCap.Round,
            )
        }
        Box(
            modifier = Modifier.size(width = 190.dp, height = 86.dp),
            contentAlignment = Alignment.Center,
        ) {
            if (today) {
                Box(contentAlignment = Alignment.Center) {
                    Image(
                        painter = painterResource(R.drawable.today_anky_icon),
                        contentDescription = null,
                        modifier = Modifier
                            .size(68.dp)
                            .clip(CircleShape),
                    )
                    Box(
                        Modifier
                            .size(68.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.42f)),
                    )
                    Text(
                        day.dayIndex.toString(),
                        style = AnkyType.Heading.copy(
                            fontSize = 22.sp,
                            fontWeight = FontWeight.ExtraBold,
                            color = Color.White,
                        ),
                    )
                    CurrentDayProgressRing(Modifier.size(78.dp))
                }
            } else {
                DayCircle(day = day, size = 48.dp, fontSize = 16.sp)
            }
            if (day.showsTrailCompletionMarker) {
                DayCompletionMarker(labels.showedUp, Modifier.offset(x = 56.dp))
            }
        }
    }
}

internal fun dayAccessibilityLabel(day: SessionDay, todayLabel: String = "Today"): String {
    val date = if (isToday(day.dayEpochMs)) {
        todayLabel
    } else {
        Instant.ofEpochMilli(day.dayEpochMs).formattedForMapDay()
    }
    return "$date, ${day.trailActivitySummary}"
}

private fun Instant.formattedForMapDay(): String =
    DateTimeFormatter
        .ofLocalizedDate(FormatStyle.MEDIUM)
        .withLocale(Locale.getDefault())
        .withZone(ZoneOffset.UTC)
        .format(this)

@Composable
private fun DayCircle(day: SessionDay, size: androidx.compose.ui.unit.Dp, fontSize: androidx.compose.ui.unit.TextUnit) {
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize().clip(CircleShape)) {
            val hasAnky = day.hasAnky
            val nodeFill = dayColor(day.dayInRegion)
            val textureOpacity = 0.22f
            drawCircle(Color.Black.copy(alpha = if (hasAnky) 0.76f else 0.58f))
            drawRect(
                brush = Brush.linearGradient(
                    colors = listOf(
                        Color.White.copy(alpha = 0.10f * textureOpacity),
                        Color.Transparent,
                        Color.Black.copy(alpha = (if (hasAnky) 0.22f else 0.34f) * textureOpacity),
                    ),
                    start = Offset.Zero,
                    end = Offset(this.size.width, this.size.height),
                ),
            )
            val spacing = maxOf(7.dp.toPx(), this.size.width / 7f)
            var x = -this.size.height
            while (x < this.size.width + this.size.height) {
                drawLine(
                    color = Color.White.copy(alpha = if (hasAnky) 0.08f else 0.05f),
                    start = Offset(x, this.size.height),
                    end = Offset(x + this.size.height, 0f),
                    strokeWidth = 1.dp.toPx(),
                )
                x += spacing
            }
            drawCircle(Color.White.copy(alpha = if (hasAnky) 0.10f else 0.05f), radius = this.size.minDimension * 0.42f, center = Offset(this.size.width * 0.30f, this.size.height * 0.26f))
            drawCircle(
                color = if (hasAnky) nodeFill.copy(alpha = 0.76f) else Color.White.copy(alpha = 0.18f),
                style = Stroke(width = 2.dp.toPx()),
            )
        }
        Text(
            day.dayIndex.toString(),
            style = AnkyType.Heading.copy(
                fontSize = fontSize,
                fontWeight = FontWeight.ExtraBold,
                color = if (day.hasAnky) Color.White.copy(alpha = 0.82f) else Color.White.copy(alpha = 0.42f),
            ),
        )
    }
}

@Composable
private fun CurrentDayProgressRing(modifier: Modifier = Modifier) {
    val label = stringResource(R.string.map_utc_day_progress)
    Canvas(
        modifier.semantics {
            contentDescription = label
        },
    ) {
        drawCircle(
            color = Color.Black.copy(alpha = 0.68f),
            style = Stroke(width = 4.dp.toPx()),
        )
        drawArc(
            color = AnkyColors.Gold.copy(alpha = 0.54f),
            startAngle = -90f,
            sweepAngle = (AnkyDuration.utcDayProgress(Instant.now()) * 360.0).toFloat(),
            useCenter = false,
            style = Stroke(width = 4.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round),
        )
    }
}

@Composable
private fun DayCompletionMarker(contentDescription: String, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(8.dp)
            .clip(CircleShape)
            .background(AnkyColors.Gold.copy(alpha = 0.88f))
            .border(3.dp, Color.Black.copy(alpha = 0.62f), CircleShape)
            .semantics {
                this.contentDescription = contentDescription
            },
    )
}

@Composable
private fun DayDetail(day: SessionDay, labels: MapLabels, onBack: () -> Unit, onOpenReveal: (String) -> Unit) {
    MapSessionListScreen(
        title = DateTimeFormatter
            .ofPattern("MMMM d, yyyy")
            .withZone(ZoneOffset.UTC)
            .format(Instant.ofEpochMilli(day.dayEpochMs))
            .lowercase(),
        sessions = day.sessions.sortedByDescending { it.createdAt },
        emptyMessage = stringResource(R.string.day_empty_message),
        labels = labels,
        onBack = onBack,
        onOpenReveal = onOpenReveal,
    )
}

@Composable
private fun MapSessionListScreen(
    title: String,
    sessions: List<SessionSummary>,
    emptyMessage: String,
    labels: MapLabels,
    onBack: () -> Unit,
    onOpenReveal: (String) -> Unit,
    showsDayInHeader: Boolean = false,
) {
    Box(Modifier.fillMaxSize()) {
        Image(
            painter = painterResource(R.drawable.map_background),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(Modifier.fillMaxSize().background(AnkyColors.Ink.copy(alpha = 0.76f)))
        Column(Modifier.fillMaxSize()) {
            MapSessionTopBar(title = title, backLabel = labels.back, onBack = onBack)
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val contentWidth = maxWidth * 0.87f
                val horizontalPadding = (maxWidth - contentWidth) / 2
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = horizontalPadding)
                        .padding(top = 34.dp, bottom = 104.dp),
                ) {
                    if (sessions.isEmpty()) item {
                        Text(
                            emptyMessage,
                            style = AnkyType.Body.copy(fontSize = 17.sp, color = AnkyColors.PaperMuted),
                            textAlign = TextAlign.Center,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 22.dp),
                        )
                    }
                    items(sessions, key = { it.hash }) { SessionRow(it, onOpenReveal, showsDayInHeader) }
                }
            }
        }
    }
}

@Composable
private fun MapSessionTopBar(title: String, backLabel: String, onBack: () -> Unit) {
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
            Spacer(Modifier.size(44.dp))
            Spacer(Modifier.size(44.dp))
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.13f)))
    }
}

@Composable
private fun SessionRow(
    session: SessionSummary,
    onOpenReveal: (String) -> Unit,
    showsDayInHeader: Boolean = false,
) {
    val reflectedTitle = session.reflectedTitle()
    val displayTags = session.displayTags()
    val rowInteraction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = rowInteraction,
                indication = null,
            ) { onOpenReveal(session.hash) }
            .semantics(mergeDescendants = true) {
                contentDescription = sessionAccessibilityLabel(session)
            }
            .padding(top = 16.dp, bottom = 18.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    session.createdAt.formattedForMapSessionTime(showsDayInHeader),
                    style = AnkyType.Mono.copy(
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AnkyColors.Gold.copy(alpha = 0.78f),
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
            }
            reflectedTitle?.let {
                Text(
                    it,
                    style = AnkyType.Heading.copy(
                        fontSize = 29.sp,
                        fontWeight = FontWeight.Bold,
                        color = AnkyColors.Gold,
                    ),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                session.preview,
                style = AnkyType.Body.copy(
                    fontSize = 20.sp,
                    lineHeight = 28.sp,
                    fontWeight = FontWeight.Normal,
                    color = if (session.isComplete) AnkyColors.Paper.copy(alpha = 0.94f) else AnkyColors.PaperMuted.copy(alpha = 0.82f),
                ),
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            if (displayTags.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(top = 2.dp),
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    displayTags.forEach { tag ->
                        Text(
                            tag,
                            style = AnkyType.Mono.copy(
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = AnkyColors.Gold.copy(alpha = 0.92f),
                            ),
                            maxLines = 1,
                        )
                    }
                }
            }
            Spacer(Modifier.height(10.dp))
        }
        Box(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .height(1.dp)
                .background(AnkyColors.Gold.copy(alpha = 0.28f)),
        )
    }
}

internal fun sessionAccessibilityLabel(session: SessionSummary): String =
    listOfNotNull(
        session.reflectedTitle(),
        session.preview,
    ).joinToString(", ")

private fun SessionSummary.reflectedTitle(): String? =
    reflectionTitle
        ?.trim()
        ?.takeIf { hasReflection && it.isNotEmpty() }
        ?.lowercase()

private fun SessionSummary.displayTags(): List<String> =
    tags.mapNotNull { it.asMapHashtag() }

private fun String.asMapHashtag(): String? {
    val cleaned = trim()
        .trim('#')
        .replace(Regex("[\\s_]+"), "-")
        .lowercase()
    return cleaned.takeIf { it.isNotEmpty() }?.let { "#$it" }
}

private fun Instant.formattedForMapSessionTime(showsDayInHeader: Boolean = false): String {
    val time = DateTimeFormatter
        .ofLocalizedTime(FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .withZone(ZoneId.systemDefault())
        .format(this)
        .lowercase()
    if (!showsDayInHeader) return time
    val day = DateTimeFormatter
        .ofPattern("MMMM d, yyyy")
        .withLocale(Locale.getDefault())
        .withZone(ZoneOffset.UTC)
        .format(this)
    return "$time · $day"
}

private fun dayColor(dayInRegion: Int): Color = when (((dayInRegion.coerceAtLeast(1) - 1) % 8) + 1) {
    1 -> Color(0xFFE5484D)
    2 -> Color(0xFFF97316)
    3 -> Color(0xFFFACC15)
    4 -> Color(0xFF22C55E)
    5 -> Color(0xFF2563EB)
    6 -> Color(0xFF4F46E5)
    7 -> Color(0xFFA855F7)
    else -> Color(0xFFFFF7E0)
}

private fun isToday(epochMs: Long): Boolean {
    val today = LocalDate.now(ZoneOffset.UTC).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    return epochMs == today
}

private data class MapLabels(
    val noWritingSaved: String,
    val goToCurrentDay: String,
    val today: String,
    val openAllAnkys: String,
    val ankys: String,
    val minutes: String,
    val streak: String,
    val utcDayProgress: String,
    val showedUp: String,
    val back: String,
    val couldNotLoadMap: String,
)

@Composable
private fun mapLabels(): MapLabels =
    MapLabels(
        noWritingSaved = stringResource(R.string.map_no_writing_saved),
        goToCurrentDay = stringResource(R.string.map_go_to_current_day),
        today = stringResource(R.string.map_today),
        openAllAnkys = stringResource(R.string.open_all_ankys),
        ankys = stringResource(R.string.you_stat_ankys),
        minutes = stringResource(R.string.you_stat_minutes),
        streak = stringResource(R.string.you_stat_streak),
        utcDayProgress = stringResource(R.string.map_utc_day_progress),
        showedUp = stringResource(R.string.map_showed_up),
        back = stringResource(R.string.map_back),
        couldNotLoadMap = stringResource(R.string.map_could_not_load),
    )
