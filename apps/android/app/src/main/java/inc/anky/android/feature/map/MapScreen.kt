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
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
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
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

@Composable
fun MapScreen(
    viewModel: MapViewModel,
    onOpenReveal: (String) -> Unit,
) {
    LaunchedEffect(Unit) { viewModel.refresh() }
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val selectedDay = remember { mutableStateOf<SessionDay?>(null) }

    AnkyMapBackground(modifier = Modifier.testTag("map-screen")) {
        if (selectedDay.value == null) {
            TrailMap(
                days = state.days,
                onOpenDay = { selectedDay.value = it },
            )
        } else {
            DayDetail(
                day = selectedDay.value!!,
                onBack = { selectedDay.value = null },
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
        Canvas(Modifier.fillMaxSize()) {
            if (displayDays.isEmpty()) return@Canvas
            val row = 124.dp.toPx()
            val points = displayDays.indices.map { index ->
                Offset(x = trailX(index, size.width), y = 86.dp.toPx() + row * index)
            }
            for (i in 1 until points.size) {
                drawLine(
                    color = Color.White.copy(alpha = 0.15f),
                    start = points[i - 1],
                    end = points[i],
                    strokeWidth = 18.dp.toPx(),
                )
                drawLine(
                    color = AnkyColors.Accent.copy(alpha = 0.24f),
                    start = points[i - 1],
                    end = points[i],
                    strokeWidth = 3.dp.toPx(),
                    pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(1f, 18f)),
                )
            }
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(vertical = 48.dp),
            state = listState,
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            if (displayDays.isEmpty()) {
                item {
                    Text(
                        "no writing saved",
                        style = AnkyType.Heading.copy(fontSize = 20.sp, color = AnkyColors.PaperMuted),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 96.dp),
                    )
                }
            }
            itemsIndexed(displayDays, key = { _, day -> day.dayEpochMs }) { index, day ->
                TrailDayNode(day = day, index = index, onOpenDay = onOpenDay)
            }
        }
        if (showCurrentDayButton.value) {
            IconButton(
                onClick = {
                    scope.launch { listState.animateScrollToItem(todayIndex) }
                },
                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 18.dp, bottom = 18.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.28f)),
            ) {
                Icon(
                    imageVector = if (currentDayIsBeforeVisible.value) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                    contentDescription = "Go to current day",
                    tint = AnkyColors.Gold,
                    modifier = Modifier.size(30.dp),
                )
            }
        }
    }
}

@Composable
private fun TrailDayNode(day: SessionDay, index: Int, onOpenDay: (SessionDay) -> Unit) {
    val today = isToday(day.dayEpochMs)
    BoxWithConstraints(Modifier.fillMaxWidth().height(124.dp)) {
        val density = LocalDensity.current
        val maxWidthPx = with(density) { maxWidth.toPx() }
        val nodeWidthPx = with(density) { 150.dp.toPx() }
        val x = (trailX(index, maxWidthPx) - nodeWidthPx / 2f).roundToInt()
        Column(
            modifier = Modifier
                .width(150.dp)
                .height(124.dp)
                .offset { androidx.compose.ui.unit.IntOffset(x, 0) }
                .clickable { onOpenDay(day) },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(contentAlignment = Alignment.TopEnd) {
                if (today) {
                    Image(
                        painter = painterResource(R.drawable.today_anky_icon),
                        contentDescription = null,
                        modifier = Modifier
                            .size(64.dp)
                            .clip(CircleShape)
                            .border(2.dp, dayColor(day.dayInRegion), CircleShape),
                    )
                } else {
                    Box(
                        Modifier
                            .size(48.dp)
                            .clip(CircleShape)
                            .background(dayColor(day.dayInRegion))
                            .border(1.5.dp, dayColor(day.dayInRegion).copy(alpha = 0.72f), CircleShape)
                            .padding(12.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            if (day.completeCount > 0) "✦" else if (day.fragmentCount > 0) "∙" else "○",
                            color = daySymbolColor(day.dayInRegion),
                        )
                    }
                }
                ActivityPips(day, Modifier.offset(x = 20.dp, y = (-8).dp))
            }
            Column(
                modifier = Modifier
                    .clip(RoundedCornerShape(percent = 50))
                    .background(Color.Black.copy(alpha = 0.22f))
                    .border(1.dp, AnkyColors.PaperMuted.copy(alpha = 0.18f), RoundedCornerShape(percent = 50))
                    .padding(horizontal = 8.dp, vertical = 5.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    if (today) "Today" else DateTimeFormatter.ofPattern("MMM d").withZone(ZoneId.systemDefault()).format(Instant.ofEpochMilli(day.dayEpochMs)),
                    style = AnkyType.Caption.copy(
                        fontWeight = if (today) FontWeight.SemiBold else FontWeight.Medium,
                        color = AnkyColors.Paper,
                    ),
                )
                Text(
                    trailSummary(day),
                    style = AnkyType.Caption.copy(fontSize = 10.sp, color = AnkyColors.PaperMuted),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun ActivityPips(day: SessionDay, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.24f))
            .border(1.dp, AnkyColors.PaperMuted.copy(alpha = 0.18f), CircleShape)
            .padding(horizontal = 6.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        repeat(day.completeCount.coerceAtMost(3)) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(AnkyColors.Success))
        }
        repeat(day.fragmentCount.coerceAtMost(3)) {
            Box(Modifier.size(5.dp).background(Color(0xFFF97316)))
        }
        val overflowCount = day.completeCount + day.fragmentCount - 6
        if (overflowCount > 0) {
            Text(
                "+$overflowCount",
                style = AnkyType.Caption.copy(fontSize = 8.sp, fontWeight = FontWeight.Bold, color = AnkyColors.PaperMuted),
            )
        }
        if (day.completeCount == 0 && day.fragmentCount == 0) {
            Canvas(Modifier.size(6.dp)) {
                drawCircle(Color.White.copy(alpha = 0.34f), style = Stroke(1.dp.toPx()))
            }
        }
    }
}

@Composable
private fun DayDetail(day: SessionDay, onBack: () -> Unit, onOpenReveal: (String) -> Unit) {
    Box(Modifier.fillMaxSize().background(AnkyColors.Ink.copy(alpha = 0.76f))) {
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
                    DateTimeFormatter.ofPattern("MMMM d, yyyy").withZone(ZoneId.systemDefault()).format(Instant.ofEpochMilli(day.dayEpochMs)).lowercase(),
                    style = AnkyType.Heading,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.size(48.dp))
            }
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(horizontal = 26.dp, vertical = 24.dp),
            ) {
                val ankys = day.sessions.filter { it.isComplete }
                val fragments = day.sessions.filter { !it.isComplete }
                if (day.sessions.isEmpty()) item {
                    Text("no writing saved", style = AnkyType.Heading.copy(fontSize = 20.sp, color = AnkyColors.PaperMuted), modifier = Modifier.fillMaxWidth().padding(top = 96.dp), textAlign = TextAlign.Center)
                }
                if (ankys.isNotEmpty()) {
                    item { SectionTitle("ankys") }
                    items(ankys, key = { it.hash }) { SessionRow(it, onOpenReveal) }
                }
                if (fragments.isNotEmpty()) {
                    item { SectionTitle("fragments") }
                    items(fragments, key = { it.hash }) { SessionRow(it, onOpenReveal) }
                }
            }
        }
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(title, style = AnkyType.Heading.copy(fontSize = 24.sp), modifier = Modifier.padding(top = 8.dp, bottom = 2.dp))
}

@Composable
private fun SessionRow(session: SessionSummary, onOpenReveal: (String) -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().clickable { onOpenReveal(session.hash) }.padding(vertical = 15.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        if (session.hasReflection && !session.reflectionTitle.isNullOrBlank()) {
            Text(
                session.reflectionTitle.lowercase(),
                style = AnkyType.Heading.copy(fontSize = 19.sp),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Text(session.preview, style = AnkyType.Body, maxLines = 3, overflow = TextOverflow.Ellipsis)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(timeText(session), style = metadataStyle())
            MetadataDot()
            Text(AnkyDuration.formatted(session.durationMs), style = metadataStyle())
            MetadataDot()
            Text("${session.wordCount} ${if (session.wordCount == 1) "word" else "words"}", style = metadataStyle())
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.16f)))
    }
}

@Composable private fun MetadataDot() = Box(Modifier.size(3.dp).clip(CircleShape).background(AnkyColors.Gold.copy(alpha = 0.44f)))

private fun metadataStyle() = androidx.compose.ui.text.TextStyle(
    fontFamily = FontFamily.Serif,
    fontWeight = FontWeight.Medium,
    fontSize = 12.sp,
    color = AnkyColors.PaperMuted,
)

private fun trailX(index: Int, width: Float): Float {
    val pattern = listOf(-0.28f, 0.04f, 0.31f, 0.17f, -0.12f, -0.35f, -0.08f, 0.24f)
    val usable = maxOf(120f, width - 108f)
    val center = width / 2f
    return (center + pattern[index % pattern.size] * usable).coerceIn(76f, width - 76f)
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

private fun daySymbolColor(dayInRegion: Int): Color = when (((dayInRegion.coerceAtLeast(1) - 1) % 8) + 1) {
    3, 8 -> Color.Black.copy(alpha = 0.76f)
    else -> Color.White
}

private fun trailSummary(day: SessionDay): String {
    if (day.completeCount == 0 && day.fragmentCount == 0) return "No writing"
    val ankyWord = if (day.completeCount == 1) "anky" else "ankys"
    val fragmentWord = if (day.fragmentCount == 1) "fragment" else "fragments"
    return "${day.completeCount} $ankyWord · ${day.fragmentCount} $fragmentWord"
}

private fun isToday(epochMs: Long): Boolean {
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone).atStartOfDay(zone).toInstant().toEpochMilli()
    return epochMs == today
}

private fun timeText(session: SessionSummary): String =
    DateTimeFormatter.ofPattern("h:mm a").withZone(ZoneId.systemDefault()).format(session.createdAt).lowercase()
