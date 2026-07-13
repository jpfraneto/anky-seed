package inc.anky.android.feature.painting

import android.graphics.Bitmap
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.R
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.gate.GateStateStore
import inc.anky.android.core.gate.QuickPassStore
import inc.anky.android.core.gate.UnlockStateStore
import inc.anky.android.core.level.AnkyFunnel
import inc.anky.android.core.level.AnkyLevel
import inc.anky.android.core.level.LevelPaintingCoordinator
import inc.anky.android.core.level.LevelProgressStore
import inc.anky.android.core.level.LevelSessionStat
import inc.anky.android.core.level.PaintingAssetStore
import inc.anky.android.core.level.PaintingPackage
import inc.anky.android.core.level.journey.JourneyCelebrationLedger
import inc.anky.android.core.level.journey.JourneyDay
import inc.anky.android.core.level.journey.JourneyPositions
import inc.anky.android.core.level.journey.JourneySessionInput
import inc.anky.android.core.level.journey.JourneySnapshot
import inc.anky.android.core.level.journey.JourneyState
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.subscription.EntitlementStore
import inc.anky.android.ui.lazure.AnkySunGlyph
import inc.anky.android.ui.lazure.LazureDivider
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.lazure.LevelTheme
import inc.anky.android.ui.lazure.VeiledFeature
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Everything the painting home needs, constructed by the integrator
 * (AppContainer) — this feature owns no wiring. Session/anchor providers
 * are lambdas so the feature never imports the storage layer directly.
 */
data class PaintingHomeDependencies(
    val levelProgressStore: LevelProgressStore,
    val paintingAssetStore: PaintingAssetStore,
    val coordinator: LevelPaintingCoordinator,
    val entitlementStore: EntitlementStore,
    val quickPassStore: QuickPassStore,
    val gateStateStore: GateStateStore,
    val unlockStateStore: UnlockStateStore,
    val funnel: AnkyFunnel,
    val celebrationLedger: JourneyCelebrationLedger,
    /** `context.assets.open(path).readBytes()`, null on failure. */
    val loadAsset: (String) -> ByteArray?,
    /** filesDir, for the widget snapshot (GlanceSharedState). */
    val filesDir: File,
    /** Live check of the blocking permission (usage access / accessibility). */
    val isGateAuthorized: () -> Boolean,
    /** WritingAnchorStore.writerName. */
    val writerName: () -> String?,
    /** AvatarStore image, if any. */
    val avatar: () -> Bitmap? = { null },
    /** SessionIndexStore adapted: newest first. */
    val recentSessions: () -> List<PaintingHomeSession>,
    /** SessionIndexStore adapted for JourneyState.derive. */
    val journeySessions: () -> List<JourneySessionInput>,
    /** SessionIndexStore adapted for the one-time level backfill. */
    val backfillSessionStats: () -> List<LevelSessionStat>,
)

/** One sealed session as the History card shows it. */
data class PaintingHomeSession(
    val hash: String,
    val createdAtMs: Long,
    val preview: String,
    val durationMs: Long,
)

/**
 * THE PAINTING IS THE APP.
 *
 * The main screen is a two-page pager: page one is the current level's
 * painting at its true progress, page two the journey map. Everything else
 * (write, quick pass, history, blocked apps) is quiet chrome beneath the
 * frame. No streak pill, no flame, no day counter — the paintings and the
 * journey tiles tell the story in the product's own language.
 *
 * Port of iOS `PaintingHomeView` (+ its `BoundaryCeremonyVeilView`).
 *
 * @param blockedAppIcons icons of the apps waiting behind the door
 *   (integrator supplies from the launcher's icon cache).
 * @param paywallSheet slot for the paywall (journey veil / boundary
 *   ceremony); invoked with the funnel origin while it should be shown.
 */
@Composable
fun PaintingHomeView(
    dependencies: PaintingHomeDependencies,
    onWrite: () -> Unit,
    onChooseApps: () -> Unit,
    onContinueSetup: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenArchive: () -> Unit,
    onOpenYou: () -> Unit,
    onEmergencyBreath: () -> Unit,
    blockedAppIcons: List<ImageBitmap> = emptyList(),
    paywallSheet: @Composable (origin: String, onDismiss: () -> Unit) -> Unit,
) {
    val entitlementState by dependencies.entitlementStore.state.collectAsStateWithLifecycle()
    val entitled = remember(entitlementState.isEntitled) {
        dependencies.entitlementStore.isEntitledForGating
    }

    var refreshTick by remember { mutableIntStateOf(0) }

    // MARK: Level & painting state

    data class LevelUi(
        val progress: AnkyLevel.Progress,
        val atBoundary: Boolean,
        val ceremonyOwed: Boolean,
        val pkg: PaintingPackage?,
    )

    val levelUi by produceState<LevelUi?>(initialValue = null, entitled, refreshTick) {
        value = withContext(Dispatchers.IO) {
            val store = dependencies.levelProgressStore
            store.backfillIfNeeded(dependencies.backfillSessionStats())
            dependencies.paintingAssetStore.installStarterIfNeeded(dependencies.loadAsset)
            // Phase-3: the free tier presents the boundary — level 2 serenely
            // complete — while the counter underneath keeps every second.
            val progress = store.presentedProgress(entitled = entitled)
            val atBoundary = store.isAtBoundary(entitled = entitled)
            // The painting for the level the writer is IN; if it isn't
            // installed (yet), fall back to the newest one we have.
            val installed = dependencies.paintingAssetStore.installedPackage(progress.level)
                ?: dependencies.paintingAssetStore.installedLevels().lastOrNull()
                    ?.let { dependencies.paintingAssetStore.installedPackage(it) }
            LevelUi(
                progress = progress,
                atBoundary = atBoundary,
                ceremonyOwed = store.owedCeremonyLevel != null && !atBoundary,
                pkg = installed,
            )
        }
    }

    val theme = remember(levelUi?.pkg?.level) {
        levelUi?.pkg?.let { LevelTheme.fromPalette(it.palette) } ?: LevelTheme.Fallback
    }
    val revealAssets = rememberPaintingRevealAssets(levelUi?.pkg)

    // MARK: Gate / signal state

    data class GateUi(
        val phase: PaintingGatePhase,
        val quickPassesRemaining: Int,
        val isShieldActive: Boolean,
        val isCurrentlyUnlocked: Boolean,
        val sessions: List<PaintingHomeSession>,
        val writerName: String?,
        val avatar: Bitmap?,
    )

    val gateUi by produceState<GateUi?>(initialValue = null, refreshTick) {
        value = withContext(Dispatchers.IO) {
            val now = Instant.now()
            val gateState = dependencies.gateStateStore.load()
            val unlockState = dependencies.unlockStateStore.load()
            GateUi(
                phase = PaintingHomeLogic.gatePhase(
                    isAuthorized = dependencies.isGateAuthorized(),
                    isGateConfigured = gateState.hasSelection,
                ),
                quickPassesRemaining = dependencies.quickPassStore.remainingPasses(now),
                isShieldActive = gateState.shieldActive,
                isCurrentlyUnlocked = gateState.isUnlocked(now) || unlockState.isUnlocked(now),
                sessions = dependencies.recentSessions(),
                writerName = dependencies.writerName(),
                avatar = dependencies.avatar(),
            )
        }
    }

    // MARK: Journey state

    val journeyPositions by produceState<List<JourneyDay>>(initialValue = emptyList()) {
        value = withContext(Dispatchers.IO) {
            JourneyPositions.parseOrEmpty(
                dependencies.loadAsset(JourneyPositions.AssetPath)?.toString(Charsets.UTF_8),
            )
        }
    }
    val journeySnapshot by produceState(initialValue = JourneySnapshot(), refreshTick) {
        value = withContext(Dispatchers.IO) {
            JourneyState.derive(dependencies.journeySessions())
        }
    }

    // MARK: Post-session stroke beat + presented progress

    val displayedProgress = remember { Animatable(0f) }
    var strokeBeatActive by remember { mutableStateOf(false) }
    val easeInOut = remember { CubicBezierEasing(0.42f, 0f, 0.58f, 1f) }
    val scope = rememberCoroutineScope()

    val paintingProgress = levelUi?.let {
        PaintingHomeLogic.paintingProgress(it.pkg?.level, it.progress.level, it.progress.percent)
    } ?: 0.0

    LaunchedEffect(levelUi?.pkg?.level, levelUi?.progress?.totalSeconds, revealAssets != null) {
        val ui = levelUi ?: return@LaunchedEffect
        val target = paintingProgress.toFloat()
        // Today's strokes arrive over ~2-3s, proportional to seconds written.
        val pending = if (revealAssets != null) {
            withContext(Dispatchers.IO) { dependencies.levelProgressStore.consumePendingStrokeSeconds() }
        } else {
            0L
        }
        if (pending > 0) {
            strokeBeatActive = true
            displayedProgress.snapTo(
                StrokeBeat.startProgress(target.toDouble(), pending, ui.progress.secondsRequired).toFloat(),
            )
            displayedProgress.animateTo(
                target,
                tween(
                    CeremonyTiming.millis(StrokeBeat.durationSeconds(pending)).toInt(),
                    easing = easeInOut,
                ),
            )
            strokeBeatActive = false
        } else {
            displayedProgress.snapTo(target)
        }
        // GlanceSync hook: the widget snapshot follows every progress change.
        withContext(Dispatchers.IO) {
            PaintingGlanceSync.sync(
                filesDir = dependencies.filesDir,
                progressStore = dependencies.levelProgressStore,
                assetStore = dependencies.paintingAssetStore,
                entitled = entitled,
            )
        }
    }

    fun skipStrokeBeat() {
        strokeBeatActive = false
        scope.launch {
            displayedProgress.animateTo(paintingProgress.toFloat(), tween(200))
        }
    }

    // MARK: Overlays

    var showsGallery by remember { mutableStateOf(false) }
    var showsBoundaryVeil by remember { mutableStateOf(false) }
    var paywallOrigin by remember { mutableStateOf<String?>(null) }

    // Unveiling: the boundary dissolves the moment entitlement lands.
    LaunchedEffect(entitled) {
        if (entitled) {
            showsBoundaryVeil = false
        }
        refreshTick += 1
    }

    Box(Modifier.fillMaxSize()) {
        LazureWall(mood = theme.wallMood)

        BoxWithConstraints(Modifier.fillMaxSize()) {
            val frame = PaintingFrameMath.frameRect(maxWidth.value, maxHeight.value)
            val side = frame.width.dp

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
            ) {
                Column(
                    Modifier.widthIn(max = 620.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    HomeHeader(
                        writerName = gateUi?.writerName,
                        avatar = gateUi?.avatar,
                        onOpenYou = onOpenYou,
                        onOpenSettings = onOpenSettings,
                        modifier = Modifier
                            .padding(horizontal = 24.dp)
                            .padding(top = 12.dp),
                    )

                    HeroPager(
                        side = side,
                        entitled = entitled,
                        levelUi = levelUi?.let { Triple(it.progress.level, it.atBoundary, it.ceremonyOwed) },
                        revealAssets = revealAssets,
                        displayedProgress = displayedProgress.value.toDouble(),
                        theme = theme,
                        journeyPositions = journeyPositions,
                        journeySnapshot = journeySnapshot,
                        celebrationLedger = dependencies.celebrationLedger,
                        loadAsset = dependencies.loadAsset,
                        onPaintingTap = {
                            when {
                                strokeBeatActive -> skipStrokeBeat()
                                levelUi?.atBoundary == true -> showsBoundaryVeil = true
                                else -> showsGallery = true
                            }
                        },
                        onJourneyVeilTap = {
                            dependencies.funnel.report(AnkyFunnel.VeilTapped, origin = "journey")
                            paywallOrigin = "journey"
                        },
                        modifier = Modifier.padding(top = maxOf(8f, frame.minY - 68f).dp),
                    )

                    HomeChrome(
                        gateUi = gateUi?.let {
                            HomeChromeState(
                                phase = it.phase,
                                quickPassesRemaining = it.quickPassesRemaining,
                                showsEmergency = PaintingHomeLogic.showsEmergencyLink(
                                    it.phase,
                                    it.isShieldActive,
                                    it.isCurrentlyUnlocked,
                                ),
                                sessions = it.sessions,
                            )
                        },
                        theme = theme,
                        thumbnail = revealAssets?.finalBitmap,
                        blockedAppIcons = blockedAppIcons,
                        onWrite = onWrite,
                        onChooseApps = onChooseApps,
                        onContinueSetup = onContinueSetup,
                        onEmergencyBreath = onEmergencyBreath,
                        onOpenArchive = onOpenArchive,
                        modifier = Modifier
                            .padding(horizontal = 24.dp)
                            .padding(top = 26.dp, bottom = 120.dp),
                    )
                }
            }
        }

        if (showsGallery) {
            GalleryView(
                currentLevel = levelUi?.progress?.level ?: 1,
                assetStore = dependencies.paintingAssetStore,
                progressStore = dependencies.levelProgressStore,
                onClose = { showsGallery = false },
            )
        }

        if (showsBoundaryVeil) {
            BoundaryCeremonyVeil(
                onVeilTap = {
                    dependencies.funnel.report(AnkyFunnel.VeilTapped, origin = "ceremony")
                    paywallOrigin = "ceremony"
                },
                onDismiss = { showsBoundaryVeil = false },
            )
        }

        paywallOrigin?.let { origin ->
            paywallSheet(origin) { paywallOrigin = null }
        }
    }
}

// MARK: Hero pager

@Composable
private fun HeroPager(
    side: Dp,
    entitled: Boolean,
    levelUi: Triple<Int, Boolean, Boolean>?, // (level, atBoundary, ceremonyOwed)
    revealAssets: PaintingRevealAssets?,
    displayedProgress: Double,
    theme: LevelTheme,
    journeyPositions: List<JourneyDay>,
    journeySnapshot: JourneySnapshot,
    celebrationLedger: JourneyCelebrationLedger,
    loadAsset: (String) -> ByteArray?,
    onPaintingTap: () -> Unit,
    onJourneyVeilTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val pagerState = rememberPagerState(pageCount = { 2 })

    Column(
        modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier
                .fillMaxWidth()
                .height(side + 8.dp),
        ) { page ->
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                if (page == 0) {
                    PaintingPage(
                        side = side,
                        level = levelUi?.first ?: 1,
                        ceremonyOwed = levelUi?.third == true,
                        revealAssets = revealAssets,
                        displayedProgress = displayedProgress,
                        theme = theme,
                        onTap = onPaintingTap,
                    )
                } else if (entitled) {
                    JourneyMapView(
                        side = side,
                        positions = journeyPositions,
                        snapshot = journeySnapshot,
                        loadAsset = loadAsset,
                        celebrationLedger = celebrationLedger,
                    )
                } else {
                    // Phase-3 §3: the journey misted, anky waiting at tile 1.
                    VeiledFeature(
                        surface = "journey",
                        message = AnkyCopyRegistry.veilJourney,
                        onTap = onJourneyVeilTap,
                        modifier = Modifier.size(side),
                    ) {
                        JourneyMapView(
                            side = side,
                            positions = journeyPositions,
                            snapshot = journeySnapshot,
                            loadAsset = loadAsset,
                            heldAtFirstTile = true,
                        )
                    }
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            repeat(2) { page ->
                Box(
                    Modifier
                        .size(6.dp)
                        .background(
                            if (pagerState.currentPage == page) {
                                LazurePigments.ankyGold
                            } else {
                                LazurePigments.ankyInkSoft.copy(alpha = 0.28f)
                            },
                            CircleShape,
                        ),
                )
            }
        }
    }
}

@Composable
private fun PaintingPage(
    side: Dp,
    level: Int,
    ceremonyOwed: Boolean,
    revealAssets: PaintingRevealAssets?,
    displayedProgress: Double,
    theme: LevelTheme,
    onTap: () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    Box(
        Modifier
            .size(side)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onTap,
            ),
    ) {
        if (revealAssets != null) {
            // A completed painting whose ceremony is still owed carries a
            // small waiting glow until the unveiling.
            PaintingView(
                assets = revealAssets,
                progress = displayedProgress,
                glowTint = theme.glowTint,
                glowStrength = if (ceremonyOwed) 1.45f else 1f,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            // Package not ready yet: a waiting canvas, breathing.
            Box(
                Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(6.dp))
                    .background(LazurePigments.ankyPaperDeep),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = stringResource(R.string.painting_preparing_canvas),
                    style = TextStyle(fontFamily = FontFamily.SansSerif, fontSize = 12.sp),
                    color = LazurePigments.ankyInkSoft,
                )
            }
        }

        // lvl badge, top-leading.
        Text(
            text = stringResource(R.string.painting_level_badge, level),
            style = TextStyle(
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.SemiBold,
                fontSize = 12.sp,
            ),
            color = LazurePigments.ankyGold,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(10.dp)
                .background(LazurePigments.ankyInk.copy(alpha = 0.35f), CircleShape)
                .padding(horizontal = 10.dp, vertical = 5.dp),
        )

        // Spiral + progress bar + percent, resting on the frame's bottom edge.
        FrameFooter(
            progress = displayedProgress,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 14.dp)
                .padding(bottom = 10.dp),
        )
    }
}

@Composable
private fun FrameFooter(progress: Double, modifier: Modifier = Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = modifier
            .background(LazurePigments.ankyInk.copy(alpha = 0.30f), CircleShape)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        AnkySunGlyph(size = 18.dp, color = LazurePigments.ankyGold.copy(alpha = 0.9f))

        Box(
            Modifier
                .weight(1f)
                .height(4.dp)
                .clip(CircleShape)
                .background(LazurePigments.ankyInk.copy(alpha = 0.25f)),
        ) {
            Box(
                Modifier
                    .fillMaxWidth(progress.toFloat().coerceIn(0.02f, 1f))
                    .height(4.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.horizontalGradient(
                            colors = listOf(LazurePigments.ankyGoldLight, LazurePigments.ankyGold),
                        ),
                    ),
            )
        }

        Text(
            text = "${(progress * 100).roundToInt()}%",
            style = TextStyle(
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.SemiBold,
                fontSize = 12.sp,
            ),
            color = LazurePigments.ankyPaper,
        )
    }
}

// MARK: Chrome beneath the frame

private data class HomeChromeState(
    val phase: PaintingGatePhase,
    val quickPassesRemaining: Int,
    val showsEmergency: Boolean,
    val sessions: List<PaintingHomeSession>,
)

@Composable
private fun HomeChrome(
    gateUi: HomeChromeState?,
    theme: LevelTheme,
    thumbnail: Bitmap?,
    blockedAppIcons: List<ImageBitmap>,
    onWrite: () -> Unit,
    onChooseApps: () -> Unit,
    onContinueSetup: () -> Unit,
    onEmergencyBreath: () -> Unit,
    onOpenArchive: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val phase = gateUi?.phase ?: PaintingGatePhase.Ready
    Column(
        modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        PrimaryCtaButton(
            phase = phase,
            theme = theme,
            onWrite = onWrite,
            onChooseApps = onChooseApps,
            onContinueSetup = onContinueSetup,
        )

        if (gateUi != null && PaintingHomeLogic.showsQuickPassLine(phase, gateUi.quickPassesRemaining)) {
            val interactionSource = remember { MutableInteractionSource() }
            Text(
                text = AnkyCopyRegistry.gatePassLine(gateUi.quickPassesRemaining),
                style = TextStyle(
                    fontFamily = FontFamily.SansSerif,
                    fontWeight = FontWeight.Medium,
                    fontSize = 14.sp,
                    textAlign = TextAlign.Center,
                ),
                color = LazurePigments.ankyInkSoft,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        role = Role.Button,
                        onClick = onWrite,
                    ),
            )
        }

        // Phase-2 §2: the emergency door must be reachable from inside the
        // app whenever the shield stands — the notification hop is never
        // the only route (it doesn't exist with notifications denied).
        if (gateUi?.showsEmergency == true) {
            val interactionSource = remember { MutableInteractionSource() }
            val emergencyLabel = stringResource(R.string.painting_emergency_a11y)
            Text(
                text = AnkyCopyRegistry.emergencyLink,
                style = TextStyle(
                    fontFamily = FontFamily.SansSerif,
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                ),
                color = LazurePigments.ankyInkSoft.copy(alpha = 0.75f),
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        role = Role.Button,
                        onClick = onEmergencyBreath,
                    )
                    .semantics { contentDescription = emergencyLabel },
            )
        }

        if (blockedAppIcons.isNotEmpty()) {
            BlockedAppsRow(icons = blockedAppIcons)
        }

        HistoryCard(
            sessions = gateUi?.sessions.orEmpty(),
            thumbnail = thumbnail,
            onOpenArchive = onOpenArchive,
        )
    }
}

@Composable
private fun PrimaryCtaButton(
    phase: PaintingGatePhase,
    theme: LevelTheme,
    onWrite: () -> Unit,
    onChooseApps: () -> Unit,
    onContinueSetup: () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val label = when (PaintingHomeLogic.primaryCta(phase)) {
        PaintingPrimaryCta.Write -> stringResource(R.string.painting_cta_write)
        PaintingPrimaryCta.ChooseApps -> stringResource(R.string.painting_cta_choose_apps)
        PaintingPrimaryCta.ContinueSetup -> stringResource(R.string.painting_cta_continue_setup)
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .height(54.dp)
            .clip(CircleShape)
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        LazurePigments.ankyGoldLight.copy(alpha = 0.98f),
                        LazurePigments.ankyGold.copy(alpha = 0.96f),
                        theme.buttonWarmth.copy(alpha = 0.98f),
                    ),
                ),
            )
            .border(0.5.dp, LazurePigments.ankyInk.copy(alpha = 0.10f), CircleShape)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                role = Role.Button,
                onClick = {
                    when (phase) {
                        PaintingGatePhase.Ready -> onWrite()
                        PaintingGatePhase.NeedsSelection -> onChooseApps()
                        PaintingGatePhase.NeedsAuthorization -> onContinueSetup()
                    }
                },
            ),
    ) {
        Spacer(Modifier.weight(1f))
        AnkySunGlyph(size = 20.dp, color = LazurePigments.ankyInk)
        Text(
            text = label,
            style = TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.SemiBold,
                fontSize = 17.sp,
            ),
            color = LazurePigments.ankyInk,
        )
        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun BlockedAppsRow(icons: List<ImageBitmap>) {
    val rowLabel = stringResource(R.string.painting_blocked_apps_a11y)
    Row(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(vertical = 2.dp)
            .semantics { contentDescription = rowLabel },
    ) {
        icons.forEach { icon ->
            Box(
                Modifier
                    .size(34.dp)
                    .clip(RoundedCornerShape(9.dp))
                    .background(LazurePigments.ankyPaper.copy(alpha = 0.5f))
                    .border(0.5.dp, LazurePigments.ankyInk.copy(alpha = 0.08f), RoundedCornerShape(9.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    bitmap = icon,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.size(26.dp),
                )
            }
        }
    }
}

// MARK: History card

@Composable
private fun HistoryCard(
    sessions: List<PaintingHomeSession>,
    thumbnail: Bitmap?,
    onOpenArchive: () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        LazurePigments.ankyPaper.copy(alpha = 0.86f),
                        LazurePigments.ankyPaperDeep.copy(alpha = 0.62f),
                        LazurePigments.ankyPaper.copy(alpha = 0.56f),
                    ),
                ),
            )
            .border(0.7.dp, LazurePigments.ankyGold.copy(alpha = 0.18f), RoundedCornerShape(22.dp))
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onOpenArchive,
            )
            .padding(horizontal = 16.dp, vertical = 13.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
            modifier = Modifier.padding(bottom = if (sessions.isEmpty()) 10.dp else 8.dp),
        ) {
            AnkySunGlyph(size = 18.dp, color = LazurePigments.ankyInk.copy(alpha = 0.72f))
            Text(
                text = stringResource(R.string.painting_history_title),
                style = TextStyle(
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 20.sp,
                ),
                color = LazurePigments.ankyInk,
            )
        }

        if (sessions.isEmpty()) {
            Text(
                text = stringResource(R.string.painting_history_empty),
                style = TextStyle(fontFamily = FontFamily.Serif, fontSize = 15.sp),
                color = LazurePigments.ankyInkSoft,
                modifier = Modifier.padding(bottom = 2.dp),
            )
        } else {
            val visible = sessions.take(5)
            visible.forEachIndexed { index, session ->
                HistoryPreviewRow(session = session, thumbnail = thumbnail)
                if (index < visible.size - 1) {
                    LazureDivider(Modifier.padding(start = 46.dp))
                }
            }
        }
    }
}

private val HistoryDateFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d  ·  h:mm a", Locale.US)

@Composable
private fun HistoryPreviewRow(
    session: PaintingHomeSession,
    thumbnail: Bitmap?,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 7.dp),
    ) {
        if (thumbnail != null) {
            Image(
                bitmap = thumbnail.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .border(0.7.dp, LazurePigments.ankyGold.copy(alpha = 0.28f), CircleShape),
            )
        } else {
            Box(
                Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.radialGradient(
                            colors = listOf(
                                LazurePigments.ankyGoldLight.copy(alpha = 0.52f),
                                LazurePigments.ankyViolet.copy(alpha = 0.42f),
                                LazurePigments.ankyInk.copy(alpha = 0.18f),
                            ),
                        ),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                AnkySunGlyph(size = 16.dp, color = LazurePigments.ankyPaper.copy(alpha = 0.88f))
            }
        }

        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = HistoryDateFormatter.format(
                    Instant.ofEpochMilli(session.createdAtMs).atZone(ZoneId.systemDefault()),
                ),
                style = TextStyle(fontFamily = FontFamily.Serif, fontSize = 12.sp),
                color = LazurePigments.ankyInkSoft.copy(alpha = 0.78f),
                maxLines = 1,
            )
            Text(
                text = session.preview,
                style = TextStyle(fontFamily = FontFamily.Serif, fontSize = 14.sp),
                color = LazurePigments.ankyInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Column(horizontalAlignment = Alignment.End, modifier = Modifier.width(42.dp)) {
            Text(
                text = AnkyDuration.clock(session.durationMs),
                style = TextStyle(fontFamily = FontFamily.Serif, fontSize = 15.sp),
                color = LazurePigments.ankyInk,
            )
            Text(
                text = stringResource(R.string.painting_history_mins),
                style = TextStyle(fontFamily = FontFamily.Serif, fontSize = 10.sp),
                color = LazurePigments.ankyInkSoft.copy(alpha = 0.76f),
            )
        }

        Icon(
            imageVector = Icons.Filled.ChevronRight,
            contentDescription = null,
            tint = LazurePigments.ankyInkSoft.copy(alpha = 0.72f),
            modifier = Modifier.size(16.dp),
        )
    }
}

// MARK: Header

@Composable
private fun HomeHeader(
    writerName: String?,
    avatar: Bitmap?,
    onOpenYou: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth(),
    ) {
        if (writerName != null) {
            val interactionSource = remember { MutableInteractionSource() }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.clickable(
                    interactionSource = interactionSource,
                    indication = null,
                    onClick = onOpenYou,
                ),
            ) {
                if (avatar != null) {
                    Image(
                        bitmap = avatar.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .border(0.8.dp, LazurePigments.ankyGold.copy(alpha = 0.45f), CircleShape),
                    )
                }
                Text(
                    text = writerName,
                    style = TextStyle(
                        fontFamily = FontFamily.Serif,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 20.sp,
                    ),
                    color = LazurePigments.ankyInk,
                )
            }
        }

        Spacer(Modifier.weight(1f))

        val settingsInteraction = remember { MutableInteractionSource() }
        Box(
            Modifier
                .size(38.dp)
                .background(LazurePigments.ankyPaper.copy(alpha = 0.6f), CircleShape)
                .border(0.5.dp, LazurePigments.ankyInk.copy(alpha = 0.08f), CircleShape)
                .clickable(
                    interactionSource = settingsInteraction,
                    indication = null,
                    role = Role.Button,
                    onClick = onOpenSettings,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Outlined.Settings,
                contentDescription = stringResource(R.string.painting_settings_a11y),
                tint = LazurePigments.ankyInkSoft,
                modifier = Modifier.size(19.dp),
            )
        }
    }
}

// MARK: Boundary ceremony veil (phase-3 §2)

/**
 * The pending moment at the boundary. The level-2 painting is complete and
 * stays theirs; the *next* canvas waits under the veil, one tap from the
 * paywall. Serene, never broken — the bar behind reads 100%.
 */
@Composable
private fun BoundaryCeremonyVeil(
    onVeilTap: () -> Unit,
    onDismiss: () -> Unit,
) {
    Box(Modifier.fillMaxSize()) {
        LazureWall(mood = LazureMood.Dawn)

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(26.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            Spacer(Modifier.weight(1f))

            VeiledFeature(
                surface = "ceremony",
                message = AnkyCopyRegistry.veilCeremony,
                onTap = onVeilTap,
                modifier = Modifier
                    .padding(horizontal = 44.dp)
                    .fillMaxWidth()
                    .aspectRatio(1f),
            ) {
                // The waiting canvas — the same breathing paper the
                // entitled see while anky paints.
                Box(
                    Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(6.dp))
                        .background(LazurePigments.ankyPaperDeep),
                )
            }

            Spacer(Modifier.weight(1f))

            val interactionSource = remember { MutableInteractionSource() }
            Text(
                text = stringResource(R.string.painting_boundary_not_yet),
                style = TextStyle(
                    fontFamily = FontFamily.SansSerif,
                    fontSize = 12.sp,
                    textDecoration = TextDecoration.Underline,
                ),
                color = LazurePigments.ankyInkSoft.copy(alpha = 0.85f),
                modifier = Modifier
                    .clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        role = Role.Button,
                        onClick = onDismiss,
                    )
                    .padding(bottom = 44.dp),
            )
        }
    }
}
