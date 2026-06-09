package inc.anky.android.feature.map

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
) {
    LaunchedEffect(Unit) {
        while (true) {
            viewModel.refresh()
            delay(60_000)
        }
    }
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val selectedDayEpoch = remember { mutableStateOf<Long?>(null) }
    val selectedDay = selectedDayEpoch.value?.let { epoch ->
        state.days.firstOrNull { it.dayEpochMs == epoch }
    }

    AnkyMapBackground(modifier = Modifier.testTag("map-screen")) {
        state.errorMessage?.let { error ->
            Text(
                error,
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
                onOpenDay = { selectedDayEpoch.value = it.dayEpochMs },
            )
        } else {
            DayDetail(
                day = selectedDay,
                onBack = { selectedDayEpoch.value = null },
                onOpenReveal = onOpenReveal,
            )
        }
    }
}

@Composable
private fun TrailMap(days: List<SessionDay>, onOpenDay: (SessionDay) -> Unit) {
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

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(vertical = 48.dp),
            state = listState,
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            if (displayDays.isEmpty()) {
                item {
                    Text(
                        "no writing saved",
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
                        contentDescription = "Go to current day"
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
    }
}

@Composable
private fun TrailDayNode(
    day: SessionDay,
    index: Int,
    dayCount: Int,
    rowHeight: androidx.compose.ui.unit.Dp,
    onOpenDay: (SessionDay) -> Unit,
) {
    val today = isToday(day.dayEpochMs)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(rowHeight)
            .clickable { onOpenDay(day) }
            .semantics {
                contentDescription = dayAccessibilityLabel(day)
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
                DayCompletionMarker(Modifier.offset(x = 56.dp))
            }
        }
    }
}

internal fun dayAccessibilityLabel(day: SessionDay): String {
    val date = if (isToday(day.dayEpochMs)) {
        "Today"
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
    Canvas(
        modifier.semantics {
            contentDescription = "UTC day progress"
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
private fun DayCompletionMarker(modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(8.dp)
            .clip(CircleShape)
            .background(AnkyColors.Gold.copy(alpha = 0.88f))
            .border(3.dp, Color.Black.copy(alpha = 0.62f), CircleShape)
            .semantics {
                contentDescription = "showed up"
            },
    )
}

@Composable
private fun DayDetail(day: SessionDay, onBack: () -> Unit, onOpenReveal: (String) -> Unit) {
    Box(Modifier.fillMaxSize()) {
        Image(
            painter = painterResource(R.drawable.map_background),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(Modifier.fillMaxSize().background(AnkyColors.Ink.copy(alpha = 0.76f)))
        Canvas(Modifier.fillMaxSize()) {
            listOf(0.18f, 0.54f, 0.82f).forEach { position ->
                drawLine(
                    color = AnkyColors.Gold.copy(alpha = 0.10f),
                    start = Offset(0f, size.height * position),
                    end = Offset(size.width, size.height * position),
                    strokeWidth = 1.dp.toPx(),
                )
            }
        }
        Column(Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier.fillMaxWidth().background(AnkyColors.Ink.copy(alpha = 0.96f)).padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onBack) {
                    Icon(
                        imageVector = Icons.Filled.ChevronLeft,
                        contentDescription = "Back",
                        tint = AnkyColors.Gold,
                        modifier = Modifier.size(30.dp),
                    )
                }
                Text(
                    DateTimeFormatter.ofPattern("MMMM d, yyyy").withZone(ZoneOffset.UTC).format(Instant.ofEpochMilli(day.dayEpochMs)).lowercase(),
                    style = AnkyType.Body.copy(
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AnkyColors.Paper,
                    ),
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.size(48.dp))
            }
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val contentWidth = maxWidth * 0.87f
                val horizontalPadding = (maxWidth - contentWidth) / 2
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = horizontalPadding)
                        .padding(top = 24.dp, bottom = 72.dp),
                ) {
                    if (day.sessions.isEmpty()) item {
                        Spacer(Modifier.fillMaxWidth().height(180.dp))
                    }
                    items(day.sessions, key = { it.hash }) { SessionRow(it, onOpenReveal) }
                }
            }
        }
    }
}

@Composable
private fun SessionRow(session: SessionSummary, onOpenReveal: (String) -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOpenReveal(session.hash) }
            .semantics(mergeDescendants = true) {
                contentDescription = sessionAccessibilityLabel(session)
            }
            .padding(vertical = 18.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            session.reflectedTitle()?.let { reflectedTitle ->
                Text(
                    reflectedTitle,
                    style = AnkyType.Heading.copy(fontSize = 19.sp),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                session.preview,
                style = AnkyType.Body.copy(
                    fontSize = if (session.isComplete) 17.sp else 16.sp,
                    fontWeight = if (session.isComplete && session.reflectionTitle.isNullOrBlank()) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (session.isComplete) AnkyColors.Paper else AnkyColors.PaperMuted,
                ),
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Box(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .height(1.5.dp)
                .background(AnkyColors.Gold.copy(alpha = 0.34f)),
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

private fun Instant.formattedForMapSessionTime(): String =
    DateTimeFormatter
        .ofLocalizedTime(FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .withZone(ZoneId.systemDefault())
        .format(this)
        .lowercase()

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
