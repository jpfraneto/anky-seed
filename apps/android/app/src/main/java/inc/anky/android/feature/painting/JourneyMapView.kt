package inc.anky.android.feature.painting

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.R
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.level.journey.JourneyCelebrationLedger
import inc.anky.android.core.level.journey.JourneyDay
import inc.anky.android.core.level.journey.JourneySnapshot
import inc.anky.android.core.level.journey.JourneySojourn
import inc.anky.android.ui.lazure.AnkySunGlyph
import inc.anky.android.ui.lazure.LazurePigments
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Decoded kingdom paintings, downsampled once to roughly the card's pixel
 * width and kept for the app's lifetime (eight stills; the scroll only ever
 * composites, never re-decodes). Port of iOS `JourneyKingdomAtlas`.
 *
 * The kingdoms are internal geography — no screen ever names one.
 */
object JourneyKingdomAtlas {
    private val images = ConcurrentHashMap<Int, Bitmap>()

    fun assetPath(imageIndex: Int): String = "journeykingdoms/kingdom${imageIndex + 1}.png"

    /** Blocking decode — call from Dispatchers.IO. Deduped by the cache. */
    fun image(imageIndex: Int, targetWidthPx: Int, loadAsset: (String) -> ByteArray?): Bitmap? {
        images[imageIndex]?.let { return it }
        val bytes = loadAsset(assetPath(imageIndex)) ?: return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val options = BitmapFactory.Options().apply {
            inSampleSize = JourneyImageSampling.inSampleSize(bounds.outWidth, targetWidthPx)
        }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
        return images.putIfAbsent(imageIndex, decoded) ?: decoded
    }
}

/**
 * Page two of the main pager: the writing journey — eight kingdom paintings
 * stacked into one continuous vertical world inside the square card,
 * primordia at the bottom, poiesis at the top. Each seam melts: the UPPER
 * image's bottom edge alpha-fades over exactly the 4% overlap band
 * (graphicsLayer offscreen + DstIn vertical gradient). 96 day markers sit
 * at their authored positions; the walk auto-scrolls to today on open.
 *
 * @param positions `JourneyPositions.parse(...)` of the bundled JSON.
 * @param snapshot `JourneyState.derive(...)` of the sealed sessions.
 * @param heldAtFirstTile Beneath the paywall veil, progress is hidden until
 *   the journey opens (anky waiting at the first stone).
 * @param celebrationLedger bloom-once bookkeeping; null skips celebration.
 * @param loadAsset maps `journeykingdoms/kingdomN.png` to bytes.
 */
@Composable
fun JourneyMapView(
    side: Dp,
    positions: List<JourneyDay>,
    snapshot: JourneySnapshot,
    loadAsset: (String) -> ByteArray?,
    modifier: Modifier = Modifier,
    heldAtFirstTile: Boolean = false,
    celebrationLedger: JourneyCelebrationLedger? = null,
) {
    val shown = if (heldAtFirstTile) JourneySnapshot() else snapshot
    val geometry = remember(side) { JourneyMapGeometry(side.value) }
    val density = LocalDensity.current
    val sidePx = with(density) { side.roundToPx() }

    val scrollState = rememberScrollState()

    // Which day blooms this visit (shown once per newly completed day).
    var celebratingIndex by remember { mutableStateOf<Int?>(null) }
    LaunchedEffect(shown.completedDays) {
        val ledger = celebrationLedger ?: return@LaunchedEffect
        if (heldAtFirstTile) return@LaunchedEffect
        if (shown.completedDays > ledger.celebratedCount()) {
            celebratingIndex = shown.writtenDayIndices.maxOrNull()
            ledger.markCelebrated(shown.completedDays)
        }
    }

    // Auto-scroll to the current day on open (before any writing: day 0,
    // the bottom of the world).
    val currentStoneIndex = shown.writtenDayIndices.maxOrNull() ?: 0
    LaunchedEffect(side, positions, currentStoneIndex) {
        val day = positions.getOrNull(currentStoneIndex) ?: return@LaunchedEffect
        val (_, yDp) = geometry.point(day)
        val offsetDp = geometry.scrollOffsetCentering(yDp, side.value)
        scrollState.scrollTo(with(density) { offsetDp.dp.roundToPx() })
    }

    Box(
        modifier
            .size(side)
            .clip(RoundedCornerShape(6.dp))
            .border(1.dp, LazurePigments.ankyGold.copy(alpha = 0.45f), RoundedCornerShape(6.dp)),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .verticalScroll(scrollState),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(geometry.totalHeight.dp),
            ) {
                // Paintings, drawn bottom-of-world first so each upper
                // kingdom's faded bottom edge composites over the one below.
                for (imageIndex in 0 until JourneySojourn.KingdomCount) {
                    KingdomImage(
                        imageIndex = imageIndex,
                        side = side,
                        topOffset = geometry.imageTop(imageIndex).dp,
                        fadesBottomEdge = imageIndex > 0,
                        overlapFraction = JourneyMapGeometry.SeamOverlapFraction,
                        targetWidthPx = sidePx,
                        loadAsset = loadAsset,
                    )
                }

                // The 96 days of the sojourn.
                for (day in positions) {
                    val state = journeyDayState(day.index, shown)
                    val (xDp, yDp) = geometry.point(day)
                    JourneyDayMarker(
                        state = state,
                        markerSide = side * 0.058f,
                        celebrates = celebratingIndex == day.index,
                        modifier = Modifier.offset(
                            x = xDp.dp - side * 0.058f / 2,
                            y = yDp.dp - side * 0.058f / 2,
                        ),
                    )
                }
            }
        }

        // Chrome over the map: day pill above, stat pills below.
        Column(
            Modifier
                .fillMaxSize()
                .padding(10.dp)
                .clearAndSetSemantics { },
        ) {
            Row {
                Text(
                    text = AnkyCopyRegistry.journeyDayLabel(shown.currentJourneyDay, JourneySojourn.TotalDays),
                    style = TextStyle(
                        fontFamily = FontFamily.Serif,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = maxOf(13f, side.value * 0.040f).sp,
                    ),
                    color = LazurePigments.ankyInk.copy(alpha = 0.88f),
                    modifier = Modifier
                        .background(LazurePigments.ankyPaper.copy(alpha = 0.58f), CircleShape)
                        .border(0.6.dp, LazurePigments.ankyGold.copy(alpha = 0.35f), CircleShape)
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically) {
                JourneyStatPill(
                    side = side,
                    text = stringResource(R.string.journey_minutes_written, shown.minutesWritten),
                ) {
                    AnkySunGlyph(size = side * 0.044f, color = LazurePigments.ankyInk.copy(alpha = 0.72f))
                }
                Spacer(Modifier.weight(1f))
                JourneyStatPill(
                    side = side,
                    text = stringResource(R.string.journey_writings_count, shown.writingsCount),
                ) {
                    // Feather stat glyph lives in drawables owned elsewhere;
                    // the spiral sun carries both pills for now.
                    AnkySunGlyph(size = side * 0.036f, color = LazurePigments.ankyInk.copy(alpha = 0.72f))
                }
            }
        }
    }
}

/**
 * One kingdom painting at its stacked offset. When [fadesBottomEdge] is
 * set, the bottom [overlapFraction] of the image dissolves to transparent
 * through a DstIn vertical gradient (drawn offscreen so the fade applies
 * to the image alone) — the misty seam melting into the kingdom below.
 */
@Composable
private fun KingdomImage(
    imageIndex: Int,
    side: Dp,
    topOffset: Dp,
    fadesBottomEdge: Boolean,
    overlapFraction: Float,
    targetWidthPx: Int,
    loadAsset: (String) -> ByteArray?,
) {
    val bitmap by produceState<Bitmap?>(initialValue = null, imageIndex, targetWidthPx) {
        value = withContext(Dispatchers.IO) {
            JourneyKingdomAtlas.image(imageIndex, targetWidthPx, loadAsset)
        }
    }

    val base = Modifier
        .offset(y = topOffset)
        .size(side)
    val faded = if (fadesBottomEdge) {
        base
            .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
            .drawWithContent {
                drawContent()
                val bandTop = size.height * (1f - overlapFraction)
                drawRect(
                    brush = Brush.verticalGradient(
                        colors = listOf(Color.White, Color.Transparent),
                        startY = bandTop,
                        endY = size.height,
                    ),
                    blendMode = BlendMode.DstIn,
                )
            }
    } else {
        base
    }

    Box(faded) {
        bitmap?.let {
            Image(
                bitmap = it.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.FillBounds,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

/**
 * One stepping stone. Completed days glow gold; the current day carries the
 * spiral sun and blooms in when newly celebrated; missed days are a faint
 * madder wash (never punitive red); future days are barely-there paper.
 */
@Composable
private fun JourneyDayMarker(
    state: JourneyDayState,
    markerSide: Dp,
    celebrates: Boolean,
    modifier: Modifier = Modifier,
) {
    val bloom = remember(celebrates) { Animatable(if (celebrates) 0.55f else 1f) }
    LaunchedEffect(celebrates) {
        if (celebrates) {
            bloom.animateTo(1.05f, tween(350))
            bloom.animateTo(1f, tween(200))
        }
    }

    val shape = RoundedCornerShape(markerSide * 0.20f)
    val (fill, border) = when (state) {
        JourneyDayState.Completed, JourneyDayState.Current -> Pair(
            Brush.linearGradient(
                colors = listOf(
                    LazurePigments.ankyPaper.copy(alpha = 0.72f),
                    LazurePigments.ankyGoldLight.copy(alpha = 0.88f),
                    LazurePigments.ankyGold.copy(alpha = 0.76f),
                ),
            ),
            LazurePigments.ankyGoldLight.copy(alpha = 0.82f),
        )
        JourneyDayState.Missed -> Pair(
            Brush.linearGradient(
                colors = listOf(
                    Color(0.64f, 0.20f, 0.16f, 0.34f),
                    Color(0.48f, 0.12f, 0.12f, 0.30f),
                ),
            ),
            Color(0.52f, 0.16f, 0.12f, 0.28f),
        )
        JourneyDayState.Future -> Pair(
            Brush.linearGradient(
                colors = listOf(
                    LazurePigments.ankyPaper.copy(alpha = 0.16f),
                    LazurePigments.ankyPaper.copy(alpha = 0.10f),
                ),
            ),
            LazurePigments.ankyPaper.copy(alpha = 0.22f),
        )
    }

    Box(
        modifier
            .size(markerSide)
            .scale(bloom.value)
            .clip(shape)
            .background(fill)
            .border(maxOf(1f, markerSide.value * 0.030f).dp, border, shape),
        contentAlignment = Alignment.Center,
    ) {
        if (state == JourneyDayState.Current) {
            AnkySunGlyph(
                size = markerSide * 0.42f,
                color = LazurePigments.ankyInk.copy(alpha = 0.58f),
            )
        }
    }
}

@Composable
private fun JourneyStatPill(
    side: Dp,
    text: String,
    icon: @Composable () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .background(LazurePigments.ankyPaper.copy(alpha = 0.42f), CircleShape)
            .border(0.6.dp, LazurePigments.ankyGold.copy(alpha = 0.30f), CircleShape)
            .padding(start = 4.dp, end = 12.dp, top = 4.dp, bottom = 4.dp),
    ) {
        Box(
            Modifier
                .size(side * 0.074f)
                .background(LazurePigments.ankyPaper.copy(alpha = 0.68f), CircleShape)
                .border(0.7.dp, LazurePigments.ankyGold.copy(alpha = 0.42f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            icon()
        }
        Text(
            text = text,
            style = TextStyle(
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.Medium,
                fontSize = maxOf(12f, side.value * 0.038f).sp,
            ),
            color = LazurePigments.ankyInk.copy(alpha = 0.88f),
            maxLines = 1,
        )
    }
}
