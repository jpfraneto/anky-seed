package inc.anky.android.feature.painting

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.colorspace.ColorSpaces
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.level.AnkyLevel
import inc.anky.android.core.level.LevelPaintingCoordinator
import inc.anky.android.core.level.PaintingPackage
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.lazure.LevelTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The level-up ceremony.
 *
 * The frame never moves — PaintingFrameMath places it exactly where the
 * main screen holds it; the world darkens and blooms around it. Sequence
 * (CeremonyTiming, second-exact with iOS): final strokes → held breath →
 * candlelit aubergine → WELCOME TO LEVEL {N} → the 8-second glimpse
 * (bloom, breath, recede) → ghost Begin → drain.
 *
 * Every animation is kicked from a LaunchedEffect — never in composition —
 * which is Compose's "one frame after insertion": the freshly inserted
 * painting materializes at its start value before the tween begins (the
 * iOS DispatchQueue.main.async trick, guaranteed by construction here).
 */
@Composable
fun UnveilCeremonyView(
    level: Int,
    coordinator: LevelPaintingCoordinator,
    onFinished: () -> Unit,
) {
    var beat by remember { mutableStateOf(CeremonyBeat.FinalStrokes) }
    var completedPackage by remember { mutableStateOf<PaintingPackage?>(null) }
    var glimpsePackage by remember { mutableStateOf<PaintingPackage?>(null) }
    var generationExcerpts by remember { mutableStateOf<List<String>>(emptyList()) }
    var packagesLoaded by remember { mutableStateOf(false) }

    val completedProgress = remember { Animatable(0.72f) }
    val glimpseProgress = remember { Animatable(0f) }
    val darkness = remember { Animatable(0f) }
    val titleOpacity = remember { Animatable(0f) }
    val beginOpacity = remember { Animatable(0f) }
    val glowOvershoot = remember { Animatable(0f) }
    val contentOpacity = remember { Animatable(1f) }

    val theme = remember(completedPackage, glimpsePackage) {
        (glimpsePackage ?: completedPackage)
            ?.let { LevelTheme.fromPalette(it.palette) }
            ?: LevelTheme.Fallback
    }

    val completedAssets = rememberPaintingRevealAssets(completedPackage)
    val glimpseAssets = rememberPaintingRevealAssets(glimpsePackage)

    val scope = rememberCoroutineScope()
    val easeInOut = remember { CubicBezierEasing(0.42f, 0f, 0.58f, 1f) }
    val easeIn = remember { CubicBezierEasing(0.42f, 0f, 1f, 1f) }

    // MARK: The sequence

    LaunchedEffect(Unit) {
        val (completed, glimpse) = withContext(Dispatchers.IO) { coordinator.ceremonyPackages(level) }
        completedPackage = completed
        glimpsePackage = glimpse
        generationExcerpts = coordinator.paintingGenerationExcerpts()
        packagesLoaded = true

        // 1. The final strokes land: eyes, gold — the 70-80% payoff fires.
        completedProgress.snapTo(0.72f)
        launch {
            completedProgress.animateTo(
                1f,
                tween(CeremonyTiming.millis(CeremonyTiming.FinalStrokesSeconds).toInt(), easing = easeInOut),
            )
        }
        delay(CeremonyTiming.millis(CeremonyTiming.FinalStrokesSeconds))

        // 2. One held breath, fully alive.
        beat = CeremonyBeat.HeldBreath
        delay(CeremonyTiming.millis(CeremonyTiming.HeldBreathSeconds))

        // 3. Candlelit aubergine — living darkness, never pure black.
        beat = CeremonyBeat.Darkening
        launch {
            darkness.animateTo(
                1f,
                tween(CeremonyTiming.millis(CeremonyTiming.DarkeningSeconds).toInt(), easing = easeInOut),
            )
        }
        delay(CeremonyTiming.millis(CeremonyTiming.DarkeningSeconds))

        // 4. WELCOME TO LEVEL {N}.
        beat = CeremonyBeat.Title
        launch {
            titleOpacity.animateTo(
                1f,
                tween(CeremonyTiming.millis(CeremonyTiming.TitleFadeSeconds).toInt(), easing = easeIn),
            )
        }
        delay(CeremonyTiming.millis(CeremonyTiming.TitleFadeSeconds))

        // 5. The glimpse. If the writer outran generation, the darkness
        // simply breathes longer while anky paints.
        if (glimpsePackage == null) {
            beat = CeremonyBeat.WaitingForGlimpse
            coordinator.waitForCeremonyPackage(level)?.let { glimpsePackage = it }
        }
        if (glimpsePackage != null) {
            beat = CeremonyBeat.GlimpseBloom
            glimpseProgress.snapTo(0f)
            launch {
                glimpseProgress.animateTo(
                    1f,
                    tween(CeremonyTiming.millis(CeremonyTiming.GlimpseBloomSeconds).toInt(), easing = easeInOut),
                )
            }
            delay(CeremonyTiming.millis(CeremonyTiming.GlimpseBloomSeconds))

            beat = CeremonyBeat.GlimpseHold
            delay(CeremonyTiming.millis(CeremonyTiming.GlimpseHoldSeconds))

            beat = CeremonyBeat.GlimpseRecede
            launch {
                glimpseProgress.animateTo(
                    0f,
                    tween(CeremonyTiming.millis(CeremonyTiming.GlimpseRecedeSeconds).toInt(), easing = easeInOut),
                )
            }
        }
        // 6. Begin fades in during the recede — anky shows you where you're
        // going; you earn it back stroke by stroke. (Generation still
        // breathing? Don't hold the writer hostage — the glimpse will be
        // waiting on the main painting instead.)
        beat = CeremonyBeat.Begin
        beginOpacity.animateTo(
            1f,
            tween(CeremonyTiming.millis(CeremonyTiming.BeginFadeSeconds).toInt(), easing = easeIn),
        )
    }

    fun drainAndFinish() {
        if (beat == CeremonyBeat.Drain) return
        beat = CeremonyBeat.Drain
        coordinator.markCeremonyShown(level)
        val drainMs = CeremonyTiming.millis(CeremonyTiming.DrainSeconds)
        scope.launch { contentOpacity.animateTo(0f, tween(600)) }
        // Pigment bleeds outward into the room: the glow overshoots in the
        // palette, then settles as the darkness lifts.
        scope.launch {
            glowOvershoot.animateTo(1.6f, tween((drainMs * 0.45).toInt(), easing = easeInOut))
            glowOvershoot.animateTo(0f, tween(drainMs.toInt(), easing = easeInOut))
        }
        scope.launch {
            delay((drainMs * 0.25).toLong())
            darkness.animateTo(0f, tween(drainMs.toInt(), easing = easeInOut))
        }
        scope.launch {
            delay(drainMs)
            onFinished()
        }
    }

    val showsGlimpsePainting = glimpsePackage != null && beat in setOf(
        CeremonyBeat.GlimpseBloom,
        CeremonyBeat.GlimpseHold,
        CeremonyBeat.GlimpseRecede,
        CeremonyBeat.Begin,
        CeremonyBeat.Drain,
    )

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val frame = PaintingFrameMath.frameRect(maxWidth.value, maxHeight.value)

        // The room: warm paper below, living aubergine darkness above.
        LazureWall(mood = theme.wallMood)
        Box(
            Modifier
                .fillMaxSize()
                .alpha(darkness.value)
                .drawBehind {
                    drawRect(CeremonyAubergine)
                    drawRect(
                        Brush.radialGradient(
                            colors = listOf(
                                CeremonyBurntUmber.copy(alpha = 0.55f),
                                CeremonyBurntUmber.copy(alpha = 0f),
                            ),
                            center = Offset(size.width / 2f, size.height / 2f),
                            radius = 420.dp.toPx(),
                        ),
                    )
                },
        )

        AnimatedVisibility(
            visible = beat == CeremonyBeat.WaitingForGlimpse,
            enter = fadeIn(tween(400)),
            exit = fadeOut(tween(400)),
        ) {
            PaintingGenerationWaitView(excerpts = generationExcerpts)
        }

        // The never-moving frame.
        if (packagesLoaded) {
            if (showsGlimpsePainting) {
                PaintingView(
                    assets = glimpseAssets,
                    progress = glimpseProgress.value.toDouble(),
                    glowTint = theme.glowTint,
                    glowStrength = 1f + glowOvershoot.value,
                    modifier = Modifier
                        .offset(x = frame.x.dp, y = frame.y.dp)
                        .size(frame.width.dp, frame.height.dp),
                )
            } else if (completedPackage != null) {
                PaintingView(
                    assets = completedAssets,
                    progress = completedProgress.value.toDouble(),
                    glowTint = theme.glowTint,
                    glowStrength = 1f + glowOvershoot.value,
                    modifier = Modifier
                        .offset(x = frame.x.dp, y = frame.y.dp)
                        .size(frame.width.dp, frame.height.dp),
                )
            }
        }

        // WELCOME TO LEVEL {N} + the painting's provenance line.
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier
                .fillMaxWidth()
                .offset(y = (frame.maxY + 40f).dp)
                .alpha(titleOpacity.value * contentOpacity.value),
        ) {
            Text(
                text = AnkyCopyRegistry.ceremonyTitle(level),
                style = TextStyle(
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 15.sp,
                    letterSpacing = 6.sp,
                ),
                color = LazurePigments.ankyGold,
            )
            val completedTitle = completedPackage?.title.orEmpty()
            if (completedTitle.isNotEmpty()) {
                Text(
                    text = AnkyCopyRegistry.ceremonyLine(
                        paintingTitle = completedTitle,
                        seconds = AnkyLevel.thresholdSeconds(level)
                            .coerceAtMost(Int.MAX_VALUE.toLong())
                            .toInt(),
                    ),
                    style = TextStyle(
                        fontFamily = FontFamily.Serif,
                        fontSize = 14.sp,
                        lineHeight = 20.sp,
                        textAlign = TextAlign.Center,
                    ),
                    color = LazurePigments.ankyPaperDeep.copy(alpha = 0.85f),
                    modifier = Modifier.padding(horizontal = 40.dp),
                )
            }
        }

        // The ghost Begin button.
        Box(
            Modifier
                .fillMaxWidth()
                .offset(y = (frame.maxY + 122f).dp)
                .alpha(beginOpacity.value * contentOpacity.value),
            contentAlignment = Alignment.Center,
        ) {
            val interactionSource = remember { MutableInteractionSource() }
            Text(
                text = AnkyCopyRegistry.ceremonyBegin,
                style = TextStyle(
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.Medium,
                    fontSize = 16.sp,
                ),
                color = LazurePigments.ankyGoldLight,
                modifier = Modifier
                    .border(1.dp, LazurePigments.ankyGold.copy(alpha = 0.55f), CircleShape)
                    .clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        role = Role.Button,
                        enabled = beat == CeremonyBeat.Begin,
                        onClick = { drainAndFinish() },
                    )
                    .padding(horizontal = 38.dp, vertical = 12.dp),
            )
        }
    }
}

/** Deep aubergine — candlelit darkness, never pure black. */
private val CeremonyAubergine =
    Color(red = 0.16f, green = 0.10f, blue = 0.17f, alpha = 1f, colorSpace = ColorSpaces.DisplayP3)

/** Burnt umber warmth breathing at the center of the darkness. */
private val CeremonyBurntUmber =
    Color(red = 0.32f, green = 0.18f, blue = 0.10f, alpha = 1f, colorSpace = ColorSpaces.DisplayP3)
