package inc.anky.android.feature.onboarding

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import inc.anky.android.R
import inc.anky.android.core.gate.DailyTargetStore
import inc.anky.android.core.gate.GateStorage
import inc.anky.android.core.gate.WriteBeforeScrollEventLogStore
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WritingAnchorStore
import inc.anky.android.core.storage.AvatarStore
import inc.anky.android.ui.lazure.AnkySunGlyph
import inc.anky.android.ui.lazure.LazureDivider
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureType
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.lazure.ThreadButton
import inc.anky.android.ui.lazure.VeilCard
import inc.anky.android.ui.lazure.WatercolorVeil
import inc.anky.android.ui.lazure.WatercolorVeilRegister
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The 13-screen onboarding — port of iOS
 * `Features/Onboarding/OnboardingView.swift` plus the screen-12/13 handling
 * that lives in `AppRoot.swift` (`finishOnboardingScreens`,
 * `presentDayOneThresholdIfNeeded`, `DayOneThresholdOverlay`).
 *
 * Screens 1–5 are the pre-dawn world (aubergine washes pooling on
 * parchment); from screen 6 the lazure wall dawns behind Anky and stays —
 * including screen 10, the paywall. One tap or gesture per screen; the only
 * typing is the optional name.
 *
 * Slots (built by other workstreams):
 *  - [paywall]  renders screen 10; call its `onDone` to continue. The flow
 *    itself skips the page while [isEntitledForGating] answers true and
 *    blocks forward swipes past it.
 *  - [gateSetup] renders screen 12 after notifications; call its `onDone`
 *    when setup closes (Done or dismiss — iOS advances on either).
 *
 * Completion contract (identical to iOS AppRoot):
 *  - [onGateSetupRequested] fires once when screen 11 finishes — the shell
 *    should open the live writing surface *underneath* the flow (the Day 1
 *    threshold is translucent over it).
 *  - [onCompleted] fires ONLY from the Day 1 threshold's "Start writing";
 *    the caller sets `anky.onboardingCompleted` there. The flow marks
 *    `anky.onboardingLastScreen` (0 = finished) on every advance.
 */
@Composable
fun AnkyOnboardingFlow(
    dailyTargetStore: DailyTargetStore,
    writingAnchorStore: WritingAnchorStore,
    eventLog: WriteBeforeScrollEventLogStore,
    avatarStore: AvatarStore,
    flowPreferences: SharedPreferences,
    isEntitledForGating: () -> Boolean,
    onGateSetupRequested: () -> Unit,
    onCompleted: () -> Unit,
    modifier: Modifier = Modifier,
    onSyncTrialReminder: () -> Unit = {},
    paywall: @Composable (onDone: () -> Unit) -> Unit,
    gateSetup: @Composable (onDone: () -> Unit) -> Unit,
) {
    val flowState = remember { OnboardingFlowState(isEntitledForGating) }
    val progress = remember(flowPreferences) { OnboardingFlowProgress(flowPreferences) }
    val scope = rememberCoroutineScope()
    val view = LocalView.current

    var stage by remember { mutableStateOf(OnboardingStage.Screens) }
    val pagerState = rememberPagerState(pageCount = { OnboardingFlowState.ScreenCount })
    val currentScreen = pagerState.currentPage + 1

    // Screen state is hoisted here because pager pages leave composition.
    var writerName by remember { mutableStateOf("") }
    var phoneHoursBracket by remember { mutableStateOf<PhoneHoursBracket?>(null) }
    var targetMinutes by remember { mutableIntStateOf(DailyTargetStore.DefaultMinutes) }
    var avatarBitmap by remember {
        mutableStateOf(avatarStore.loadData()?.let { BitmapFactory.decodeByteArray(it, 0, it.size) })
    }

    val isDawn = stage != OnboardingStage.Screens || flowState.isDawn(currentScreen)

    fun goTo(screen: Int) {
        scope.launch { pagerState.animateScrollToPage(screen - 1) }
    }

    /** iOS `finishOnboardingScreens()`: screens 1–11 done, gate setup is screen 12. */
    fun finishScreens() {
        progress.mark(OnboardingFlowState.GateSetupScreen)
        onGateSetupRequested()
        stage = OnboardingStage.GateSetup
    }

    fun advance(haptic: Boolean = false) {
        if (haptic) view.lightHaptic()
        val next = flowState.nextScreen(currentScreen)
        if (next != null) goTo(next) else finishScreens()
    }

    // Analytics-free abandonment marker, on every advance (and retreat).
    LaunchedEffect(currentScreen, stage) {
        when (stage) {
            OnboardingStage.Screens -> progress.mark(currentScreen)
            OnboardingStage.GateSetup -> progress.mark(OnboardingFlowState.GateSetupScreen)
            OnboardingStage.DayOneThreshold -> progress.mark(OnboardingFlowState.DayOneThresholdScreen)
        }
    }

    // Returning subscriber, restore, or QA re-run: the ask was already
    // answered — continue past the paywall to notifications (iOS onAppear).
    LaunchedEffect(currentScreen) {
        if (currentScreen == OnboardingFlowState.PaywallScreen && isEntitledForGating()) {
            advance(haptic = false)
        }
    }

    val currentScreenState = rememberUpdatedState(currentScreen)
    val stageState = rememberUpdatedState(stage)
    val swipeModifier = Modifier.pointerSwipe { swipe ->
        if (stageState.value != OnboardingStage.Screens) return@pointerSwipe
        val screen = currentScreenState.value
        when (swipe) {
            OnboardingSwipe.Advance -> if (flowState.allowsForwardSwipe(screen)) {
                view.lightHaptic()
                flowState.nextScreen(screen)?.let(::goTo)
            }
            OnboardingSwipe.Retreat -> if (flowState.allowsBackwardSwipe(screen)) {
                view.lightHaptic()
                flowState.previousScreen(screen)?.let(::goTo)
            }
        }
    }

    val flowLabel = stringResource(R.string.onboarding_flow_accessibility)
    Box(
        modifier
            .fillMaxSize()
            .semantics { contentDescription = flowLabel },
    ) {
        when (stage) {
            OnboardingStage.Screens -> {
                OnboardingBackdrop(
                    isDawn = isDawn,
                    showsDawnVeil = currentScreen == OnboardingFlowState.MeetAnkyScreen,
                )
                Column(
                    Modifier
                        .fillMaxSize()
                        .then(swipeModifier)
                        .imePadding(),
                ) {
                    HorizontalPager(
                        state = pagerState,
                        userScrollEnabled = false,
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth(),
                    ) { page ->
                        when (page + 1) {
                            1 -> ProblemScreen(onAdvance = { advance() })
                            2 -> SolutionScreen(onAdvance = { advance() })
                            3 -> MechanismScreen(onAdvance = { advance() })
                            4 -> HoursScreen(
                                onBracketChosen = { bracket ->
                                    view.lightHaptic()
                                    phoneHoursBracket = bracket
                                    flowPreferences.edit()
                                        .putString(PhoneHoursBracket.PreferenceKey, bracket.rawValue)
                                        .apply()
                                    advance(haptic = false)
                                },
                            )
                            5 -> MathScreen(
                                isCurrent = currentScreen == 5,
                                bracket = phoneHoursBracket,
                                onAdvance = { advance() },
                            )
                            6 -> MeetAnkyScreen(onAdvance = { advance() })
                            7 -> NameScreen(
                                writerName = writerName,
                                onWriterNameChange = { writerName = it },
                                avatarBitmap = avatarBitmap,
                                onAvatarCaptured = { bitmap ->
                                    avatarStore.save(bitmap.toJpegBytes())
                                    avatarBitmap = bitmap
                                },
                                onContinue = {
                                    writingAnchorStore.save(
                                        writerName = writerName,
                                        anchorSentence = writingAnchorStore.anchorSentence,
                                    )
                                    advance()
                                },
                                onLater = {
                                    writerName = ""
                                    view.lightHaptic()
                                    advance()
                                },
                            )
                            8 -> TargetScreen(
                                targetMinutes = targetMinutes,
                                onTargetMinutesChange = { targetMinutes = it },
                                onCommit = {
                                    dailyTargetStore.setInitialTarget(targetMinutes)
                                    eventLog.append(
                                        WriteBeforeScrollEventName.OnboardingTargetSet,
                                        metadata = mapOf(
                                            "targetMinutes" to "$targetMinutes",
                                            "changedFromDefault" to
                                                "${targetMinutes != DailyTargetStore.DefaultMinutes}",
                                        ),
                                    )
                                    advance()
                                },
                            )
                            9 -> JourneyScreen(
                                storyName = storyName(writerName, writingAnchorStore),
                                onAdvance = { advance() },
                            )
                            10 -> Box(Modifier.fillMaxSize()) {
                                paywall { advance(haptic = false) }
                            }
                            else -> NotificationsScreen(
                                onSyncTrialReminder = onSyncTrialReminder,
                                onFinished = { finishScreens() },
                            )
                        }
                    }

                    OnboardingDots(
                        current = currentScreen,
                        total = OnboardingFlowState.ScreenCount,
                        isDawn = isDawn,
                        modifier = Modifier
                            .align(Alignment.CenterHorizontally)
                            .padding(top = 20.dp, bottom = 34.dp),
                    )
                }
            }

            OnboardingStage.GateSetup -> {
                LazureWall(LazureMood.Dawn)
                gateSetup { stage = OnboardingStage.DayOneThreshold }
            }

            OnboardingStage.DayOneThreshold ->
                // Translucent over whatever the shell placed beneath the
                // flow — the live writing surface, per the iOS threshold.
                AnkyDayOneThresholdOverlay(
                    onStartWriting = {
                        progress.markFinished()
                        onCompleted()
                    },
                )
        }
    }
}

private enum class OnboardingStage { Screens, GateSetup, DayOneThreshold }

/** The story is told about the typed name, else a previously stored one. */
private fun storyName(typedName: String, anchorStore: WritingAnchorStore): String? {
    val typed = typedName.trim()
    if (typed.isNotEmpty()) return typed
    // Android's WritingAnchorStore substitutes "You" when unset; that
    // placeholder must not name the third-person story.
    return anchorStore.writerName?.takeIf { it != WritingAnchorStore.DefaultWriterName }
}

// MARK: - Background (pre-dawn aubergine → dawn)

@Composable
private fun OnboardingBackdrop(isDawn: Boolean, showsDawnVeil: Boolean) {
    val dawnAlpha by animateFloatAsState(
        targetValue = if (isDawn) 1f else 0f,
        animationSpec = tween(durationMillis = 1200),
        label = "onboardingDawn",
    )
    Box(Modifier.fillMaxSize()) {
        if (dawnAlpha < 1f) {
            // The scroll world before dawn: deep violet lazure pooling on
            // parchment — the ceremony's aubergine register, never black.
            Box(Modifier.fillMaxSize().graphicsLayer { alpha = 1f - dawnAlpha }) {
                LazureWall(LazureMood.Dusk)
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                colors = listOf(
                                    LazurePigments.ankyViolet.copy(alpha = 0.26f),
                                    LazurePigments.ankyViolet.copy(alpha = 0.08f),
                                    LazurePigments.ankyRose.copy(alpha = 0.10f),
                                    LazurePigments.ankyViolet.copy(alpha = 0.20f),
                                ),
                            ),
                        ),
                )
            }
        }
        if (dawnAlpha > 0f) {
            Box(Modifier.fillMaxSize().graphicsLayer { alpha = dawnAlpha }) {
                LazureWall(LazureMood.Dawn)
            }
        }
        // A breathing wash for the one true threshold: the world turning
        // to light when Anky steps forward.
        AnimatedVisibility(visible = showsDawnVeil, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize().graphicsLayer { alpha = 0.6f }) {
                WatercolorVeil(register = WatercolorVeilRegister.Pale)
            }
        }
    }
}

// MARK: - Screens 1–3 · problem / solution / mechanism

@Composable
private fun ProblemScreen(onAdvance: () -> Unit) {
    NightScreenColumn {
        OnboardingPainting(R.drawable.onboarding_1)
        NightTitle(stringResource(R.string.onboarding_problem_title))
        NightBody(stringResource(R.string.onboarding_problem_body))
        NightCta(stringResource(R.string.onboarding_problem_cta), onClick = onAdvance)
    }
}

@Composable
private fun SolutionScreen(onAdvance: () -> Unit) {
    NightScreenColumn {
        OnboardingPainting(R.drawable.onboarding_2)
        NightTitle(stringResource(R.string.onboarding_solution_title))
        NightBody(stringResource(R.string.onboarding_solution_body))
        NightCta(stringResource(R.string.onboarding_solution_cta), onClick = onAdvance)
    }
}

@Composable
private fun MechanismScreen(onAdvance: () -> Unit) {
    NightScreenColumn {
        OnboardingPainting(R.drawable.onboarding_3)
        NightTitle(stringResource(R.string.onboarding_mechanism_title))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NightBody(stringResource(R.string.onboarding_mechanism_body_quick))
            NightBody(stringResource(R.string.onboarding_mechanism_body_daily))
        }
        NightCta(stringResource(R.string.onboarding_mechanism_cta), onClick = onAdvance)
    }
}

// MARK: - Screen 4 · Make it personal

@Composable
private fun HoursScreen(onBracketChosen: (PhoneHoursBracket) -> Unit) {
    NightScreenColumn(spacing = 12.dp) {
        OnboardingPainting(R.drawable.onboarding_4, maxWidth = 368.dp, maxHeight = 336.dp)
        NightTitle(stringResource(R.string.onboarding_hours_title))
        NightBody(stringResource(R.string.onboarding_hours_body))

        Column(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.padding(top = 8.dp),
        ) {
            PhoneHoursBracket.entries.forEach { bracket ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(54.dp)
                        .clip(OnboardingCapsule)
                        .background(LazurePigments.ankyPaper.copy(alpha = 0.72f))
                        .border(0.7.dp, LazurePigments.ankyGold.copy(alpha = 0.45f), OnboardingCapsule)
                        .clickable { onBracketChosen(bracket) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = stringResource(bracket.labelRes),
                        fontFamily = FontFamily.Serif,
                        fontWeight = FontWeight.Medium,
                        fontSize = 19.sp,
                        color = LazurePigments.ankyInk,
                    )
                }
            }
        }
    }
}

private val PhoneHoursBracket.labelRes: Int
    get() = when (this) {
        PhoneHoursBracket.OneToTwo -> R.string.onboarding_hours_bracket_1_2
        PhoneHoursBracket.ThreeToFour -> R.string.onboarding_hours_bracket_3_4
        PhoneHoursBracket.FiveToSix -> R.string.onboarding_hours_bracket_5_6
        PhoneHoursBracket.SevenPlus -> R.string.onboarding_hours_bracket_7_plus
    }

// MARK: - Screen 5 · The visceral math

/**
 * The timed reveal beats, matching iOS `revealMathBeats()`:
 * beat one at 0.15s (0.6s ease), beat two at 0.95s (0.6s), CTA at 1.7s (0.5s).
 */
@Composable
private fun MathScreen(
    isCurrent: Boolean,
    bracket: PhoneHoursBracket?,
    onAdvance: () -> Unit,
) {
    var beatOneVisible by remember { mutableStateOf(false) }
    var beatTwoVisible by remember { mutableStateOf(false) }
    var ctaVisible by remember { mutableStateOf(false) }

    LaunchedEffect(isCurrent) {
        beatOneVisible = false
        beatTwoVisible = false
        ctaVisible = false
        if (isCurrent) {
            delay(150)
            beatOneVisible = true
            delay(800) // 0.95s absolute
            beatTwoVisible = true
            delay(750) // 1.7s absolute
            ctaVisible = true
        }
    }

    val wakingYears = OnboardingFlowState.wakingYears(bracket)

    NightScreenColumn(spacing = 14.dp) {
        OnboardingPainting(R.drawable.onboarding_5, maxWidth = 344.dp, maxHeight = 304.dp)

        MathBeat(visible = beatOneVisible, durationMillis = 600) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    text = stringResource(R.string.onboarding_math_years_format, wakingYears),
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.Medium,
                    fontSize = 52.sp,
                    color = LazurePigments.ankyMadder,
                    textAlign = TextAlign.Center,
                )
                Text(
                    text = stringResource(R.string.onboarding_math_waking_life),
                    fontFamily = FontFamily.Serif,
                    fontSize = 20.sp,
                    color = LazurePigments.ankyInkSoft,
                    textAlign = TextAlign.Center,
                )
            }
        }

        MathBeat(visible = beatTwoVisible, durationMillis = 600) {
            Text(
                text = stringResource(R.string.onboarding_math_question),
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.Medium,
                fontSize = 21.sp,
                lineHeight = 30.sp,
                color = LazurePigments.ankyUmber,
                textAlign = TextAlign.Center,
            )
        }

        MathBeat(visible = ctaVisible, durationMillis = 500, lift = false) {
            NightCta(stringResource(R.string.onboarding_math_cta), onClick = onAdvance)
        }
    }
}

/** Fade + 10dp rise, the iOS beat treatment. */
@Composable
private fun MathBeat(
    visible: Boolean,
    durationMillis: Int,
    lift: Boolean = true,
    content: @Composable () -> Unit,
) {
    val alpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = tween(durationMillis),
        label = "mathBeatAlpha",
    )
    val offset by animateDpAsState(
        targetValue = if (visible || !lift) 0.dp else 10.dp,
        animationSpec = tween(durationMillis),
        label = "mathBeatOffset",
    )
    val density = LocalDensity.current
    Box(
        Modifier.graphicsLayer {
            this.alpha = alpha
            translationY = with(density) { offset.toPx() }
        },
    ) {
        content()
    }
}

// MARK: - Screen 6 · Meet Anky (dawn)

@Composable
private fun MeetAnkyScreen(onAdvance: () -> Unit) {
    DawnScreenColumn {
        AnkySpriteFigure(OnboardingSpriteSequence.WaveFront, size = 190.dp)
        Text(
            text = stringResource(R.string.onboarding_meet_title),
            style = LazureType.ankyTitle,
            color = LazurePigments.ankyInk,
            textAlign = TextAlign.Center,
        )
        DawnBody(stringResource(R.string.onboarding_meet_body))
        DawnCta(stringResource(R.string.onboarding_meet_cta), onClick = onAdvance)
    }
}

// MARK: - Screen 7 · The name (+ optional selfie)

@Composable
private fun NameScreen(
    writerName: String,
    onWriterNameChange: (String) -> Unit,
    avatarBitmap: Bitmap?,
    onAvatarCaptured: (Bitmap) -> Unit,
    onContinue: () -> Unit,
    onLater: () -> Unit,
) {
    val view = LocalView.current
    val context = LocalContext.current
    val imeVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0

    val selfieLauncher = rememberLauncherForActivityResult(
        contract = remember { FrontCameraPreviewContract() },
    ) { bitmap ->
        if (bitmap != null) onAvatarCaptured(bitmap)
    }

    DawnScreenColumn {
        // Anky listens for the name — and steps aside when the keyboard
        // needs the room.
        if (!imeVisible) {
            AnkySpriteFigure(OnboardingSpriteSequence.ShyListening, size = 110.dp)
        }

        Text(
            text = stringResource(R.string.onboarding_name_title),
            style = LazureType.ankyTitle,
            color = LazurePigments.ankyInk,
            textAlign = TextAlign.Center,
        )

        if (context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
            SelfieButton(
                avatarBitmap = avatarBitmap,
                onTakeSelfie = {
                    view.lightHaptic()
                    selfieLauncher.launch(null)
                },
            )
        }

        VeilCard(modifier = Modifier.fillMaxWidth()) {
            BasicTextField(
                value = writerName,
                onValueChange = onWriterNameChange,
                textStyle = LazureType.ankyProse.copy(color = LazurePigments.ankyInk),
                cursorBrush = SolidColor(LazurePigments.ankyInk),
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Words,
                    autoCorrect = false,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = { onContinue() }),
                modifier = Modifier.fillMaxWidth(),
                decorationBox = { innerTextField ->
                    Box {
                        if (writerName.isEmpty()) {
                            Text(
                                text = stringResource(R.string.onboarding_name_placeholder),
                                style = LazureType.ankyProse,
                                color = LazurePigments.ankyInkSoft.copy(alpha = 0.72f),
                            )
                        }
                        innerTextField()
                    }
                },
            )
        }

        Text(
            text = stringResource(R.string.onboarding_name_privacy),
            style = LazureType.ankyCaption,
            color = LazurePigments.ankyInkSoft,
            textAlign = TextAlign.Center,
        )

        DawnCta(stringResource(R.string.onboarding_name_cta), onClick = onContinue)

        Text(
            text = stringResource(R.string.onboarding_name_later),
            style = LazureType.ankyCaption,
            color = LazurePigments.ankyInkSoft.copy(alpha = 0.8f),
            textDecoration = TextDecoration.Underline,
            modifier = Modifier.clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onLater,
            ),
        )
    }
}

/**
 * The optional selfie: taken once here, kept only on this phone (AvatarStore
 * JPEG), and worn as the writer's face across the rest of the app.
 */
@Composable
private fun SelfieButton(
    avatarBitmap: Bitmap?,
    onTakeSelfie: () -> Unit,
) {
    val selfieLabel = stringResource(R.string.onboarding_selfie_accessibility)
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onTakeSelfie,
            )
            .semantics { contentDescription = selfieLabel },
    ) {
        Box(
            modifier = Modifier
                .size(92.dp)
                .clip(CircleShape)
                .background(
                    if (avatarBitmap == null) LazurePigments.ankyPaper.copy(alpha = 0.62f) else LazurePigments.ankyPaper,
                )
                .border(1.dp, LazurePigments.ankyGold.copy(alpha = 0.55f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (avatarBitmap != null) {
                Image(
                    bitmap = avatarBitmap.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Icon(
                    imageVector = Icons.Outlined.PhotoCamera,
                    contentDescription = null,
                    tint = LazurePigments.ankyInkSoft,
                    modifier = Modifier.size(26.dp),
                )
            }
        }
        Text(
            text = stringResource(
                if (avatarBitmap == null) R.string.onboarding_selfie_add else R.string.onboarding_selfie_retake,
            ),
            style = LazureType.ankyCaption,
            color = LazurePigments.ankyInkSoft.copy(alpha = 0.85f),
        )
    }
}

/**
 * `TakePicturePreview` with the front-camera hints — the platform picker
 * honors them where it can (iOS sets `cameraDevice = .front`). The bitmap
 * never leaves the device; JPEG encoding at quality 85 mirrors iOS
 * `jpegData(compressionQuality: 0.85)`.
 */
private class FrontCameraPreviewContract : ActivityResultContracts.TakePicturePreview() {
    override fun createIntent(context: Context, input: Void?): Intent =
        super.createIntent(context, input).apply {
            putExtra("android.intent.extras.CAMERA_FACING", 1)
            putExtra("android.intent.extras.LENS_FACING_FRONT", 1)
            putExtra("android.intent.extra.USE_FRONT_CAMERA", true)
        }
}

private fun Bitmap.toJpegBytes(): ByteArray =
    ByteArrayOutputStream().use { stream ->
        compress(Bitmap.CompressFormat.JPEG, 85, stream)
        stream.toByteArray()
    }

// MARK: - Screen 8 · The target

@Composable
private fun TargetScreen(
    targetMinutes: Int,
    onTargetMinutesChange: (Int) -> Unit,
    onCommit: () -> Unit,
) {
    val view = LocalView.current
    val range = DailyTargetStore.MinutesRange

    DawnScreenColumn {
        AnkySpriteFigure(OnboardingSpriteSequence.Seated, size = 110.dp)

        Text(
            text = stringResource(R.string.onboarding_target_title),
            style = LazureType.ankyTitle,
            color = LazurePigments.ankyInk,
            textAlign = TextAlign.Center,
        )

        VeilCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = if (targetMinutes == 1) {
                        stringResource(R.string.onboarding_target_minutes_one)
                    } else {
                        stringResource(R.string.onboarding_target_minutes_format, targetMinutes)
                    },
                    style = LazureType.ankyHeading,
                    color = LazurePigments.ankyInk,
                )

                Slider(
                    value = targetMinutes.toFloat(),
                    onValueChange = { onTargetMinutesChange(it.roundToInt().coerceIn(range)) },
                    valueRange = range.first.toFloat()..range.last.toFloat(),
                    steps = range.last - range.first - 1,
                    colors = SliderDefaults.colors(
                        thumbColor = LazurePigments.ankyGold,
                        activeTrackColor = LazurePigments.ankyGold,
                        inactiveTrackColor = LazurePigments.ankyInkSoft.copy(alpha = 0.25f),
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )

                Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp)) {
                    range.forEach { minute ->
                        val selected = minute == targetMinutes
                        Text(
                            text = "$minute",
                            fontFamily = FontFamily.Monospace,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            fontSize = 14.sp,
                            textAlign = TextAlign.Center,
                            color = if (selected) {
                                LazurePigments.ankyGold
                            } else {
                                LazurePigments.ankyInkSoft.copy(alpha = 0.55f)
                            },
                            modifier = Modifier
                                .weight(1f)
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) {
                                    view.lightHaptic()
                                    onTargetMinutesChange(minute)
                                },
                        )
                    }
                }
            }
        }

        Text(
            text = stringResource(R.string.onboarding_target_floor),
            style = LazureType.ankyCaption,
            color = LazurePigments.ankyInkSoft,
            textAlign = TextAlign.Center,
            lineHeight = 17.sp,
        )

        DawnCta(
            stringResource(R.string.onboarding_target_cta_format, targetMinutes),
            onClick = onCommit,
        )
    }
}

// MARK: - Screen 9 · The journey container

@Composable
private fun JourneyScreen(storyName: String?, onAdvance: () -> Unit) {
    DawnScreenColumn {
        Text(
            text = stringResource(R.string.onboarding_journey_title),
            style = LazureType.ankyTitle,
            color = LazurePigments.ankyInk,
            textAlign = TextAlign.Center,
        )

        VeilCard(modifier = Modifier.fillMaxWidth(), padding = 16.dp) {
            OnboardingJourneyStory.story(storyName).forEach { entry ->
                Row(
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.padding(vertical = 6.dp),
                ) {
                    Text(
                        text = "${entry.day}",
                        fontFamily = FontFamily.Serif,
                        fontWeight = FontWeight.Medium,
                        fontSize = 17.sp,
                        textAlign = TextAlign.End,
                        color = if (entry.isMilestone) {
                            LazurePigments.ankyGold
                        } else {
                            LazurePigments.ankyInkSoft.copy(alpha = 0.7f)
                        },
                        modifier = Modifier.widthIn(min = 20.dp),
                    )
                    Text(
                        text = journeyLine(entry, storyName),
                        fontFamily = FontFamily.Serif,
                        fontWeight = if (entry.isMilestone) FontWeight.Medium else FontWeight.Normal,
                        fontSize = 14.sp,
                        lineHeight = 19.sp,
                        color = if (entry.isMilestone) LazurePigments.ankyInk else LazurePigments.ankyInkSoft,
                    )
                }
                if (entry.day < OnboardingJourneyStory.DayCount) {
                    LazureDivider(Modifier.padding(start = 32.dp))
                }
            }
        }

        Text(
            text = stringResource(R.string.onboarding_journey_footnote),
            style = LazureType.ankyCaption,
            color = LazurePigments.ankyInkSoft,
        )

        DawnCta(stringResource(R.string.onboarding_journey_cta), onClick = onAdvance)
    }
}

/** iOS `OnboardingJourneyDay.story(for:)`, resolved against string resources. */
@Composable
private fun journeyLine(entry: OnboardingJourneyDay, storyName: String?): String = when (entry.day) {
    1 -> if (entry.usesNamedVariant) {
        stringResource(R.string.onboarding_journey_day1_named_format, storyName.orEmpty())
    } else {
        stringResource(R.string.onboarding_journey_day1)
    }
    2 -> stringResource(R.string.onboarding_journey_day2_format, DailyTargetStore.DefaultMinutes)
    3 -> stringResource(R.string.onboarding_journey_day3)
    4 -> if (entry.usesNamedVariant) {
        stringResource(R.string.onboarding_journey_day4_named)
    } else {
        stringResource(R.string.onboarding_journey_day4)
    }
    5 -> stringResource(R.string.onboarding_journey_day5)
    6 -> if (entry.usesNamedVariant) {
        stringResource(R.string.onboarding_journey_day6_named)
    } else {
        stringResource(R.string.onboarding_journey_day6)
    }
    7 -> stringResource(R.string.onboarding_journey_day7)
    else -> stringResource(R.string.onboarding_journey_day8)
}

// MARK: - Screen 11 · Notifications

@Composable
private fun NotificationsScreen(
    onSyncTrialReminder: () -> Unit,
    onFinished: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var denied by remember { mutableStateOf(false) }
    var isRequesting by remember { mutableStateOf(false) }

    fun complete(granted: Boolean) {
        // The trial started one screen before permission existed — place
        // the honest reminder now that it can actually fire.
        onSyncTrialReminder()
        if (granted) {
            onFinished()
        } else {
            denied = true
            scope.launch {
                delay(1400)
                onFinished()
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> complete(granted) }

    DawnScreenColumn {
        AnkySpriteFigure(OnboardingSpriteSequence.IdleFront, size = 130.dp)

        Text(
            text = stringResource(R.string.onboarding_notifications_title),
            style = LazureType.ankyTitle,
            color = LazurePigments.ankyInk,
            textAlign = TextAlign.Center,
        )

        DawnBody(stringResource(R.string.onboarding_notifications_body))

        AnimatedVisibility(visible = denied, enter = fadeIn(tween(300)), exit = fadeOut()) {
            Text(
                text = stringResource(R.string.onboarding_notifications_denied),
                style = LazureType.ankyCaption,
                color = LazurePigments.ankyInkSoft,
                textAlign = TextAlign.Center,
            )
        }

        DawnCta(
            stringResource(R.string.onboarding_notifications_cta),
            enabled = !isRequesting,
            onClick = {
                if (isRequesting) return@DawnCta
                isRequesting = true
                val needsRuntimePermission = Build.VERSION.SDK_INT >= 33 &&
                    ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.POST_NOTIFICATIONS,
                    ) != PackageManager.PERMISSION_GRANTED
                if (needsRuntimePermission) {
                    permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    complete(granted = true)
                }
            },
        )
    }
}

// MARK: - Screen 13 · Day 1 threshold overlay

/**
 * Shown over the live writing surface after gate setup — port of iOS
 * `DayOneThresholdOverlay` in `OnboardingView.swift`. Dismissing it is the
 * moment onboarding completes: the caller's [onStartWriting] must set
 * `anky.onboardingCompleted` (and, when used standalone, mark the flow
 * progress finished via [progress]).
 */
@Composable
fun AnkyDayOneThresholdOverlay(
    onStartWriting: () -> Unit,
    modifier: Modifier = Modifier,
    progress: OnboardingFlowProgress? = null,
) {
    LaunchedEffect(Unit) {
        progress?.mark(OnboardingFlowState.DayOneThresholdScreen)
    }
    val view = LocalView.current

    Box(
        modifier
            .fillMaxSize()
            // iOS layers .ultraThinMaterial + paper at 0.55; with no live
            // blur at this layer, two paper washes stand in.
            .background(LazurePigments.ankyPaperDeep.copy(alpha = 0.35f))
            .background(LazurePigments.ankyPaper.copy(alpha = 0.55f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
            modifier = Modifier
                .padding(horizontal = 44.dp)
                .widthIn(max = 520.dp),
        ) {
            AnkySunGlyph(size = 44.dp, color = LazurePigments.ankyGold)

            Text(
                text = stringResource(R.string.onboarding_day_one_title),
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.Medium,
                fontSize = 44.sp,
                color = LazurePigments.ankyInk,
            )

            Text(
                text = stringResource(R.string.onboarding_day_one_body),
                style = LazureType.ankyHeading,
                color = LazurePigments.ankyInkSoft,
                textAlign = TextAlign.Center,
            )

            ThreadButton(
                text = stringResource(R.string.onboarding_day_one_cta),
                onClick = {
                    view.successHaptic()
                    onStartWriting()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 10.dp),
            )
        }
    }
}

// MARK: - Shared pieces

private val OnboardingCapsule = RoundedCornerShape(percent = 50)

/** Pre-dawn screens: tighter 13dp rhythm (iOS `VStack(spacing: 13)`). */
@Composable
private fun NightScreenColumn(
    spacing: Dp = 13.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 30.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(spacing, Alignment.CenterVertically),
        content = content,
    )
}

/** Dawn screens: 18dp rhythm (iOS `VStack(spacing: 18)`). */
@Composable
private fun DawnScreenColumn(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 30.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically),
        content = content,
    )
}

/** The onboarding paintings — same art as iOS `onboarding-1..5`. */
@Composable
private fun ColumnScope.OnboardingPainting(
    imageRes: Int,
    maxWidth: Dp = 400.dp,
    maxHeight: Dp = 480.dp,
) {
    Image(
        painter = painterResource(imageRes),
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = Modifier
            .weight(1f, fill = false)
            .widthIn(max = maxWidth)
            .heightIn(max = maxHeight)
            .fillMaxWidth()
            .drawBehind {
                // iOS gives the paintings a gold glow shadow (0.16 / r18 / y8).
                val glow = LazurePigments.ankyGold.copy(alpha = 0.16f)
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(glow, glow.copy(alpha = 0f)),
                        center = Offset(size.width / 2f, size.height / 2f + 8.dp.toPx()),
                        radius = size.minDimension / 2f + 18.dp.toPx(),
                    ),
                    radius = size.minDimension / 2f + 18.dp.toPx(),
                    center = Offset(size.width / 2f, size.height / 2f + 8.dp.toPx()),
                )
            },
    )
}

@Composable
private fun NightTitle(text: String) {
    Text(
        text = text,
        fontFamily = FontFamily.Serif,
        fontWeight = FontWeight.Medium,
        fontSize = 27.sp,
        lineHeight = 36.sp,
        color = LazurePigments.ankyInk,
        textAlign = TextAlign.Center,
    )
}

@Composable
private fun NightBody(text: String) {
    Text(
        text = text,
        fontFamily = FontFamily.Serif,
        fontSize = 17.sp,
        lineHeight = 26.sp,
        color = LazurePigments.ankyInkSoft,
        textAlign = TextAlign.Center,
    )
}

@Composable
private fun DawnBody(text: String) {
    Text(
        text = text,
        style = LazureType.ankyProse,
        color = LazurePigments.ankyInkSoft,
        textAlign = TextAlign.Center,
    )
}

/**
 * Pre-dawn CTA: the golden thread as a thin outline on parchment — at dawn
 * ([DawnCta] → [ThreadButton]) it fills with light.
 */
@Composable
private fun NightCta(text: String, onClick: () -> Unit) {
    val view = LocalView.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp)
            .height(60.dp)
            .drawBehind {
                val glow = LazurePigments.ankyGold.copy(alpha = 0.24f)
                val center = Offset(size.width / 2f, size.height / 2f + 4.dp.toPx())
                val radius = size.height / 2f + 14.dp.toPx()
                // Stretch the halo horizontally so it hugs the capsule
                // (same trick as ThreadButton's breathing glow).
                scale(scaleX = size.width / size.height, scaleY = 1f, pivot = center) {
                    drawCircle(
                        brush = Brush.radialGradient(
                            colors = listOf(glow, glow.copy(alpha = 0f)),
                            center = center,
                            radius = radius,
                        ),
                        radius = radius,
                        center = center,
                    )
                }
            }
            .clip(OnboardingCapsule)
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        LazurePigments.ankyPaper.copy(alpha = 0.85f),
                        LazurePigments.ankyGoldLight.copy(alpha = 0.45f),
                    ),
                ),
            )
            .border(
                width = 1.dp,
                brush = Brush.linearGradient(
                    colors = listOf(LazurePigments.ankyGoldLight, LazurePigments.ankyGold),
                ),
                shape = OnboardingCapsule,
            )
            .clickable {
                view.lightHaptic()
                onClick()
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            fontFamily = FontFamily.Serif,
            fontWeight = FontWeight.SemiBold,
            fontSize = 20.sp,
            color = LazurePigments.ankyInk,
            textAlign = TextAlign.Center,
        )
    }
}

/** Dawn CTA: the golden thread filled with light (iOS `ThreadButtonStyle`). */
@Composable
private fun DawnCta(text: String, onClick: () -> Unit, enabled: Boolean = true) {
    val view = LocalView.current
    ThreadButton(
        text = text,
        enabled = enabled,
        onClick = {
            view.lightHaptic()
            onClick()
        },
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp),
    )
}

// MARK: - Progress dots

@Composable
private fun OnboardingDots(
    current: Int,
    total: Int,
    isDawn: Boolean,
    modifier: Modifier = Modifier,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(9.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier,
    ) {
        (1..total).forEach { index ->
            val selected = index == current
            val dotSize by animateDpAsState(
                targetValue = if (selected) 8.dp else 6.dp,
                animationSpec = tween(250),
                label = "onboardingDot",
            )
            Box(
                Modifier
                    .size(dotSize)
                    .clip(CircleShape)
                    .background(
                        when {
                            selected -> LazurePigments.ankyGold
                            isDawn -> LazurePigments.ankyInk.copy(alpha = 0.18f)
                            else -> LazurePigments.ankyViolet.copy(alpha = 0.32f)
                        },
                    ),
            )
        }
    }
}

// MARK: - Anky sprite (frame animation over the shared anky### drawables)

/**
 * The sprite moments iOS `AnkySpriteView` lends to onboarding, using the
 * same frame windows as `AnkyPresenceOverlay` (Anky023–026 wave, 052–057
 * shy listening, 046–051 seated, 001–006 idle) at the iOS default 6fps.
 */
internal enum class OnboardingSpriteSequence(val frames: List<Int>, val fps: Int) {
    WaveFront(
        listOf(R.drawable.anky023, R.drawable.anky024, R.drawable.anky025, R.drawable.anky026),
        6,
    ),
    ShyListening(
        listOf(
            R.drawable.anky052, R.drawable.anky053, R.drawable.anky054,
            R.drawable.anky055, R.drawable.anky056, R.drawable.anky057,
        ),
        6,
    ),
    Seated(
        listOf(
            R.drawable.anky046, R.drawable.anky047, R.drawable.anky048,
            R.drawable.anky049, R.drawable.anky050, R.drawable.anky051,
        ),
        6,
    ),
    IdleFront(
        listOf(
            R.drawable.anky001, R.drawable.anky002, R.drawable.anky003,
            R.drawable.anky004, R.drawable.anky005, R.drawable.anky006,
        ),
        6,
    ),
}

@Composable
internal fun AnkySpriteFigure(
    sequence: OnboardingSpriteSequence,
    size: Dp,
    modifier: Modifier = Modifier,
) {
    var cursor by remember(sequence) { mutableIntStateOf(0) }
    LaunchedEffect(sequence) {
        if (sequence.frames.size > 1) {
            while (true) {
                delay(1000L / sequence.fps)
                cursor = (cursor + 1) % sequence.frames.size
            }
        }
    }
    Image(
        painter = painterResource(sequence.frames[cursor.coerceIn(sequence.frames.indices)]),
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = modifier.size(size),
    )
}

// MARK: - Gestures & haptics

/**
 * iOS `onboardingSwipeGesture`: judge the drag once, at its end, in
 * density-independent units — [OnboardingFlowState.swipeDirection] holds
 * the thresholds (>70, 1.35x horizontal dominance).
 */
private fun Modifier.pointerSwipe(onSwipe: (OnboardingSwipe) -> Unit): Modifier =
    pointerInput(Unit) {
        var totalX = 0f
        var totalY = 0f
        detectDragGestures(
            onDragStart = {
                totalX = 0f
                totalY = 0f
            },
            onDrag = { _, dragAmount ->
                totalX += dragAmount.x
                totalY += dragAmount.y
            },
            onDragEnd = {
                OnboardingFlowState.swipeDirection(totalX / density, totalY / density)
                    ?.let(onSwipe)
            },
        )
    }

private fun View.lightHaptic() {
    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
}

private fun View.successHaptic() {
    if (Build.VERSION.SDK_INT >= 30) {
        performHapticFeedback(HapticFeedbackConstants.CONFIRM)
    } else {
        performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }
}

// MARK: - Legacy entry point (until AnkyApp is rewired)

/**
 * Thin compatibility wrapper so `AnkyApp` keeps compiling until integration
 * rewires it to [AnkyOnboardingFlow] (see WIRING-onboarding.md). Uses no-op
 * paywall/gate-setup slots (those pages auto-advance) and never reads
 * entitlement truth.
 */
@Deprecated(
    "Integration should call AnkyOnboardingFlow with the real stores, " +
        "entitlement gate, paywall and gate-setup slots (WIRING-onboarding.md).",
    ReplaceWith("AnkyOnboardingFlow(...)"),
)
@Composable
fun AnkyOnboardingScreen(
    startWriting: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val gatePrefs = remember(context) { GateStorage.preferences(context) }
    AnkyOnboardingFlow(
        dailyTargetStore = remember(gatePrefs) { DailyTargetStore(gatePrefs) },
        writingAnchorStore = remember(gatePrefs) { WritingAnchorStore(gatePrefs) },
        eventLog = remember(gatePrefs) { WriteBeforeScrollEventLogStore(gatePrefs) },
        avatarStore = remember(context) { AvatarStore(context) },
        flowPreferences = gatePrefs,
        isEntitledForGating = { false },
        onGateSetupRequested = {},
        onCompleted = startWriting,
        modifier = modifier,
        paywall = { onDone -> LaunchedEffect(Unit) { onDone() } },
        gateSetup = { onDone -> LaunchedEffect(Unit) { onDone() } },
    )
}
