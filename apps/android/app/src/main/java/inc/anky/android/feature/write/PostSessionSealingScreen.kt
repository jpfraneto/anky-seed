package inc.anky.android.feature.write

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import inc.anky.android.R
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.ui.lazure.AnkySunGlyph
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.lazure.ReflectionGhost
import inc.anky.android.ui.lazure.VeiledFeature

/**
 * The three beats after terminal silence — seal (min 3s) → mirror → gate —
 * ported from iOS `PostSessionSealingView` (ios/Anky/AppRoot.swift). The
 * sealing is an evening-mood moment: a violet-forward lazure wash.
 */
@Composable
fun PostSessionSealingScreen(
    sealed: SealedWritingSession,
    reflectionMarkdown: String,
    reflectionResolved: Boolean,
    reflectionFailed: Boolean,
    reflectionVeiled: Boolean,
    onStartReflection: () -> Unit,
    onMomentShown: () -> Unit,
    onVeilTap: () -> Unit,
    onMomentCta: () -> Unit,
    onEmergency: () -> Unit,
    onGate: () -> Unit,
    onStay: () -> Unit,
    freeTargetMoment: (@Composable () -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    var phase by remember { mutableStateOf(SealingPhase.Seal) }
    var sealMinimumElapsed by remember { mutableStateOf(false) }
    var didLeaveDuringSeal by remember { mutableStateOf(false) }
    var skipsSealMotion by remember { mutableStateOf(false) }
    val hashLine = remember(sealed.artifact.hash) { sealedHashLine(sealed.artifact.hash) }
    val lifecycleOwner = LocalLifecycleOwner.current

    LaunchedEffect(Unit) {
        onStartReflection()
        kotlinx.coroutines.delay(3_000)
        sealMinimumElapsed = true
    }

    // iOS scenePhase handling: leaving during the seal beat skips the motion
    // and advances the moment the writer returns.
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> if (phase == SealingPhase.Seal) didLeaveDuringSeal = true
                Lifecycle.Event.ON_START -> if (didLeaveDuringSeal) {
                    sealMinimumElapsed = true
                    skipsSealMotion = true
                }
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(sealMinimumElapsed, reflectionResolved) {
        if (phase == SealingPhase.Seal && sealMinimumElapsed && reflectionResolved) {
            phase = SealingPhase.Mirror
            kotlinx.coroutines.delay(1_000)
            if (phase == SealingPhase.Mirror) {
                phase = SealingPhase.Gate
                if (sealed.showsFreeTargetMoment) {
                    // The day's one showing is spent only when the moment
                    // actually renders (iOS onMomentShown).
                    onMomentShown()
                }
            }
        }
    }

    Box(modifier = modifier.fillMaxSize().testTag("sealing-screen")) {
        LazureWall(mood = LazureMood.Dusk)

        Crossfade(targetState = phase == SealingPhase.Seal, label = "sealing-phase") { isSealBeat ->
            if (isSealBeat) {
                SealBeat(hashLine = hashLine, skipsMotion = skipsSealMotion)
            } else {
                MirrorAndGateBeat(
                    sealed = sealed,
                    hashLine = hashLine,
                    reflectionMarkdown = reflectionMarkdown,
                    reflectionFailed = reflectionFailed,
                    reflectionVeiled = reflectionVeiled,
                    showsGate = phase == SealingPhase.Gate,
                    onVeilTap = onVeilTap,
                    onMomentCta = onMomentCta,
                    onEmergency = onEmergency,
                    onGate = onGate,
                    onStay = onStay,
                    freeTargetMoment = freeTargetMoment,
                )
            }
        }
    }
}

private enum class SealingPhase {
    Seal,
    Mirror,
    Gate,
}

/** iOS hashLine: `"Sealed · FIRST4...LAST4"` — the exact format. */
internal fun sealedHashLine(hash: String): String {
    val prefix = hash.take(4)
    val suffix = hash.takeLast(4)
    return "Sealed · $prefix...$suffix"
}

@Composable
private fun SealBeat(hashLine: String, skipsMotion: Boolean) {
    var gathered by remember { mutableStateOf(skipsMotion) }
    LaunchedEffect(Unit) { gathered = true }
    val gatherProgress by animateFloatAsState(
        targetValue = if (gathered) 1f else 0f,
        animationSpec = tween(durationMillis = if (skipsMotion) 0 else 2_750),
        label = "seal-gather",
    )

    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Box(
                Modifier
                    .size(126.dp)
                    .blur(26.dp)
                    .background(
                        LazurePigments.ankyViolet.copy(alpha = 0.10f + 0.10f * gatherProgress),
                        CircleShape,
                    ),
            )
            AnkySunGlyph(
                size = 96.dp,
                color = LazurePigments.ankyGold,
                modifier = Modifier.scale(1.25f - 0.71f * gatherProgress),
            )
        }
        Spacer(Modifier.height(12.dp))
        Text(
            text = hashLine,
            style = TextStyle(
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium,
                fontSize = 12.sp,
                color = LazurePigments.ankyInkSoft.copy(alpha = 0.8f),
            ),
            modifier = Modifier.testTag("sealing-hash-line"),
        )
    }
}

@Composable
private fun MirrorAndGateBeat(
    sealed: SealedWritingSession,
    hashLine: String,
    reflectionMarkdown: String,
    reflectionFailed: Boolean,
    reflectionVeiled: Boolean,
    showsGate: Boolean,
    onVeilTap: () -> Unit,
    onMomentCta: () -> Unit,
    onEmergency: () -> Unit,
    onGate: () -> Unit,
    onStay: () -> Unit,
    freeTargetMoment: (@Composable () -> Unit)?,
) {
    val reflectionText = reflectionMarkdown.trim().ifEmpty {
        stringResource(R.string.write_sealing_fallback)
    }
    val gateTitle = when {
        sealed.unlockGrant == null -> stringResource(R.string.write_sealing_done)
        sealed.isGateOriginated -> stringResource(
            R.string.write_sealing_go_back_to,
            sealed.gateOriginAppDisplayName ?: stringResource(R.string.write_sealing_the_app),
        )
        else -> stringResource(R.string.write_sealing_continue)
    }
    val remainingTodayText = stringResource(
        R.string.write_sealing_stay_format,
        AnkyDuration.clock(sealed.remainingToTargetMs),
    )
    val firstGateLine = stringResource(R.string.write_sealing_first_gate_line)
        .takeIf { sealed.isFirstGate && sealed.unlockGrant != null }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 28.dp, vertical = 18.dp)
            .widthIn(max = 620.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Spacer(Modifier.height(54.dp))

        if (reflectionVeiled) {
            // The reflection-shaped card under the parchment mist — one tap
            // from the paywall, never a dead end. Free sessions make zero
            // LLM calls; the veil stands where the reflection would.
            VeiledFeature(
                surface = "reflection",
                message = AnkyCopyRegistry.veilReflection,
                onTap = onVeilTap,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 235.dp),
            ) {
                ReflectionGhost()
            }
        } else {
            Text(
                text = reflectionText,
                style = TextStyle(
                    fontFamily = FontFamily.Serif,
                    fontSize = if (reflectionFailed) 22.sp else 25.sp,
                    lineHeight = if (reflectionFailed) 30.sp else 33.sp,
                    color = if (reflectionFailed) LazurePigments.ankyInkSoft else LazurePigments.ankyInk,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("sealing-reflection"),
            )
        }

        AnimatedVisibility(
            visible = showsGate,
            enter = fadeIn(animationSpec = tween(780)),
            exit = fadeOut(animationSpec = tween(300)),
        ) {
            if (sealed.showsFreeTargetMoment) {
                freeTargetMoment?.invoke() ?: FreeTargetMomentBlock(
                    showsEmergencyLink = sealed.quickPassesRemaining <= 0,
                    onMomentCta = onMomentCta,
                    onEmergency = onEmergency,
                    onDismiss = onGate,
                )
            } else {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(13.dp),
                    modifier = Modifier.padding(top = 10.dp),
                ) {
                    if (firstGateLine != null) {
                        Text(
                            text = firstGateLine,
                            style = TextStyle(
                                fontFamily = FontFamily.Serif,
                                fontWeight = FontWeight.Medium,
                                fontSize = 15.sp,
                                lineHeight = 21.sp,
                                color = LazurePigments.ankyViolet.copy(alpha = 0.92f),
                                textAlign = TextAlign.Center,
                            ),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }

                    SealingGateButton(
                        title = gateTitle,
                        onClick = onGate,
                        modifier = Modifier.testTag("sealing-gate-button"),
                    )

                    Text(
                        text = remainingTodayText,
                        style = TextStyle(
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Medium,
                            fontSize = 13.sp,
                            color = LazurePigments.ankyInkSoft,
                        ),
                        modifier = Modifier
                            .clickable(onClick = onStay)
                            .padding(6.dp)
                            .testTag("sealing-stay-button"),
                    )
                }
            }
        }

        Spacer(Modifier.height(34.dp))

        Text(
            text = hashLine,
            style = TextStyle(
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium,
                fontSize = 11.sp,
                color = LazurePigments.ankyInk.copy(alpha = 0.35f),
                textAlign = TextAlign.Center,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 18.dp),
        )
    }
}

/**
 * Decision 2026-07-06 (option C): the free writer's target moment —
 * acknowledgment first, the subscriber fact second, the trial as an open
 * door. Dismissible in one tap; with no passes left the emergency breath
 * stays quietly visible so there is always a free way forward. This is the
 * built-in fallback; the paywall workstream can hand a richer card into the
 * `freeTargetMoment` slot.
 */
@Composable
private fun FreeTargetMomentBlock(
    showsEmergencyLink: Boolean,
    onMomentCta: () -> Unit,
    onEmergency: () -> Unit,
    onDismiss: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .padding(top = 10.dp)
            .testTag("sealing-free-target-moment"),
    ) {
        Text(
            text = AnkyCopyRegistry.freeTargetMomentTitle,
            style = TextStyle(
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.SemiBold,
                fontSize = 22.sp,
                color = LazurePigments.ankyInk,
                textAlign = TextAlign.Center,
            ),
            modifier = Modifier.fillMaxWidth(),
        )
        Text(
            text = AnkyCopyRegistry.freeTargetMomentLine,
            style = TextStyle(
                fontFamily = FontFamily.Serif,
                fontSize = 15.sp,
                lineHeight = 21.sp,
                color = LazurePigments.ankyInkSoft,
                textAlign = TextAlign.Center,
            ),
            modifier = Modifier.fillMaxWidth(),
        )
        Text(
            text = AnkyCopyRegistry.freeTargetMomentSubscriberLine,
            style = TextStyle(
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.Medium,
                fontSize = 15.sp,
                lineHeight = 21.sp,
                color = LazurePigments.ankyViolet.copy(alpha = 0.92f),
                textAlign = TextAlign.Center,
            ),
            modifier = Modifier.fillMaxWidth(),
        )

        SealingGateButton(
            title = AnkyCopyRegistry.freeTargetMomentCTA,
            onClick = onMomentCta,
            modifier = Modifier.testTag("sealing-moment-cta"),
        )

        if (showsEmergencyLink) {
            Text(
                text = AnkyCopyRegistry.emergencyLink,
                style = TextStyle(
                    fontSize = 13.sp,
                    color = LazurePigments.ankyInkSoft.copy(alpha = 0.75f),
                ),
                modifier = Modifier
                    .clickable(onClick = onEmergency)
                    .padding(4.dp),
            )
        }

        Text(
            text = AnkyCopyRegistry.freeTargetMomentDismiss,
            style = TextStyle(
                fontWeight = FontWeight.Medium,
                fontSize = 13.sp,
                color = LazurePigments.ankyInkSoft,
            ),
            modifier = Modifier
                .clickable(onClick = onDismiss)
                .padding(4.dp)
                .testTag("sealing-moment-dismiss"),
        )
    }
}

@Composable
private fun SealingGateButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 46.dp)
            .clip(CircleShape)
            .background(
                Brush.verticalGradient(
                    listOf(LazurePigments.ankyGoldLight, LazurePigments.ankyGold),
                ),
            )
            .border(0.5.dp, LazurePigments.ankyInk.copy(alpha = 0.10f), CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 22.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = title,
            style = TextStyle(
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                color = LazurePigments.ankyInk,
            ),
            maxLines = 1,
        )
    }
}
