package inc.anky.android.feature.geshtu

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Spa
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.app.AppContainer
import inc.anky.android.app.UserSettings
import inc.anky.android.core.continuity.GeshtuContinuity
import inc.anky.android.core.continuity.GeshtuEvent
import inc.anky.android.core.continuity.GeshtuPhase
import inc.anky.android.core.continuity.GeshtuReducer
import inc.anky.android.core.identity.BiometricGate
import inc.anky.android.core.mirror.AnkyReflectionPrompt
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.core.storage.SingleAnkyImporter
import inc.anky.android.feature.paywall.PaywallSheet
import inc.anky.android.feature.reveal.RevealViewModel
import inc.anky.android.feature.write.SealedWritingSession
import inc.anky.android.feature.write.WriteScreen
import inc.anky.android.feature.write.WriteViewModel
import inc.anky.android.feature.you.YouScreen
import inc.anky.android.feature.you.YouViewModel
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureType
import inc.anky.android.ui.lazure.LazureWall
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlinx.coroutines.launch

/**
 * Android's native body for the Geshtu continuity genome.
 *
 * WORLD is always mounted beneath DEVICE. There are no tabs and no route
 * stack: the fixed Anchor summons writing, stillness closes it, and the
 * crossroads resolves the sealed day into continuation, reflection, or local
 * memory.
 */
@Composable
fun GeshtuWorldScreen(
    container: AppContainer,
    settings: UserSettings,
    biometricGate: BiometricGate,
    onAppLockChange: (Boolean) -> Unit,
    deepLinkUri: String? = null,
    onDeepLinkHandled: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    var continuity by remember { mutableStateOf(GeshtuContinuity()) }
    var showsOnboarding by remember(settings.onboardingCompleted) {
        mutableStateOf(!settings.onboardingCompleted)
    }
    var showsPaywall by remember { mutableStateOf(false) }

    fun dispatch(event: GeshtuEvent) {
        continuity = GeshtuReducer.reduce(continuity, event)
    }

    val writeViewModel = remember(settings.mirrorBaseUrl) {
        WriteViewModel(
            activeDraftStore = container.activeDraftStore,
            archive = container.archive,
            reflectionStore = container.reflectionStore,
            indexStore = container.sessionIndexStore,
            identityProvider = { container.identityStore.loadOrCreate() },
            mirrorClientProvider = { container.mirrorClient(settings.mirrorBaseUrl) },
            writingPreferencesStore = container.writingPreferencesStore,
            gateSession = container.gateSession,
            entitledForGating = {
                container.entitlementStore.isEntitledForGating ||
                    container.entitlementStore.state.value.isEntitled
            },
            onSealedComplete = container::creditSealedSession,
            onApplyUnlock = { grant ->
                container.gateRuntime.unlockApplier.applyUnlock(grant)
            },
        )
    }
    val writeState = writeViewModel.state.collectAsStateWithLifecycle().value
    val pendingArtifact = remember(continuity.pendingSessionHash, writeState.sealedSession) {
        writeState.sealedSession?.artifact
            ?: continuity.pendingSessionHash?.let { hash ->
                runCatching { container.archive.load(hash) }.getOrNull()
            }
    }
    val reflectionAllowed =
        container.entitlementStore.isEntitledForGating ||
            container.entitlementStore.state.collectAsStateWithLifecycle().value.isEntitled
    val reflectionViewModel = remember(continuity.pendingSessionHash, settings.mirrorBaseUrl) {
        continuity.pendingSessionHash?.let { hash ->
            RevealViewModel(
                hash = hash,
                archive = container.archive,
                reflectionStore = container.reflectionStore,
                requestStore = container.reflectionRequestStore,
                indexStore = container.sessionIndexStore,
                identityStore = container.identityStore,
                mirrorClientProvider = { container.mirrorClient(settings.mirrorBaseUrl) },
                entitledForGatingProvider = {
                    container.entitlementStore.isEntitledForGating ||
                        container.entitlementStore.state.value.isEntitled
                },
            )
        }
    }
    val reflectionState = if (reflectionViewModel == null) {
        null
    } else {
        reflectionViewModel.state.collectAsStateWithLifecycle().value
    }

    val youViewModel = remember {
        YouViewModel(
            identityStore = container.identityStore,
            settingsStore = container.settingsStore,
            reminderScheduler = container.reminderScheduler,
            creditsClient = container.creditsClient,
            reflectionCreditCache = container.reflectionCreditCache,
            exporter = container.exporter,
            backupImporter = container.backupImporter,
            activeDraftStore = container.activeDraftStore,
            archive = container.archive,
            reflectionStore = container.reflectionStore,
            requestStore = container.reflectionRequestStore,
            indexStore = container.sessionIndexStore,
            appOpenStore = container.appOpenStore,
            encryptedBackupStore = container.encryptedBackupStore,
            biometricGate = biometricGate,
            entitlementStore = container.entitlementStore,
        )
    }

    fun settleCurrentDay() {
        writeViewModel.finishSealing()
        container.encryptedBackupStore.backUpIfEnabled()
        dispatch(GeshtuEvent.Settle)
    }

    fun openFreshWriting() {
        writeViewModel.clearCompletedSession()
        writeViewModel.openWritingPortal()
        dispatch(GeshtuEvent.OpenWriting)
    }

    fun requestReflection() {
        val artifact = pendingArtifact ?: return
        if (!reflectionAllowed) {
            copyText(
                context = view.context,
                label = "Anky reflection prompt",
                text = AnkyReflectionPrompt.build(artifact.reconstructedText),
            )
            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            showsPaywall = true
            return
        }
        dispatch(GeshtuEvent.SendOffering)
    }

    LaunchedEffect(Unit) {
        writeViewModel.openWritingPortal()
    }
    LaunchedEffect(deepLinkUri) {
        when (deepLinkUri) {
            "anky://write" -> {
                openFreshWriting()
                onDeepLinkHandled()
            }
            "anky://painting" -> {
                dispatch(GeshtuEvent.Settle)
                onDeepLinkHandled()
            }
        }
    }
    LaunchedEffect(writeState.acceptedGlyphCount) {
        if (writeState.acceptedGlyphCount > 0 && showsOnboarding) {
            showsOnboarding = false
            container.settingsStore.setOnboardingCompleted(true)
        }
    }
    LaunchedEffect(continuity.phase, reflectionViewModel) {
        if (continuity.phase == GeshtuPhase.Reflection) {
            reflectionViewModel?.refreshEntitlement()
            reflectionViewModel?.askAnky()
        }
    }

    Box(modifier.fillMaxSize()) {
        LazureWall(mood = LazureMood.Dawn, modifier = Modifier.fillMaxSize())

        GeshtuWorldSurface(
            continuity = continuity,
            archive = container.archive.list(),
            reflections = container.reflectionStore.list().associateBy(LocalReflection::hash),
            onOpenEntry = { dispatch(GeshtuEvent.OpenEntry(it.hash)) },
            onCloseEntry = { dispatch(GeshtuEvent.CloseEntry) },
            onArmLateOffering = { dispatch(GeshtuEvent.ArmLateOffering) },
            onOpenSeed = { dispatch(GeshtuEvent.OpenSeed) },
            modifier = Modifier.fillMaxSize(),
        )

        if (continuity.phase == GeshtuPhase.Landing || continuity.phase == GeshtuPhase.EntryOpen) {
            val openedWriting = continuity.openedEntryHash?.let { hash ->
                archiveText(container.archive.list(), hash)
            }
            GeshtuTopChrome(
                writing = openedWriting,
                showsSettings = true,
                onSettings = { dispatch(GeshtuEvent.OpenSeed) },
            )
        }

        AnimatedVisibility(
            visible = continuity.isDeviceSpace,
            enter = slideInVertically(
                initialOffsetY = { it },
                animationSpec = tween(420),
            ) + fadeIn(tween(260)),
            exit = slideOutVertically(
                targetOffsetY = { it },
                animationSpec = tween(360),
            ) + fadeOut(tween(220)),
            modifier = Modifier.fillMaxSize().zIndex(10f),
        ) {
            when (continuity.phase) {
                GeshtuPhase.Writing -> WriteScreen(
                    viewModel = writeViewModel,
                    onImported = {},
                    onCompleted = {},
                    onCloseToMap = { dispatch(GeshtuEvent.Settle) },
                    onImportAnkyText = { text ->
                        SingleAnkyImporter.importText(
                            rawText = text,
                            archive = container.archive,
                            reflectionStore = container.reflectionStore,
                            indexStore = container.sessionIndexStore,
                        )
                    },
                    onImportAnkyBytes = { bytes ->
                        SingleAnkyImporter.importBytes(
                            bytes = bytes,
                            archive = container.archive,
                            reflectionStore = container.reflectionStore,
                            indexStore = container.sessionIndexStore,
                        )
                    },
                    axisMode = true,
                    onAxisSealed = { sealed: SealedWritingSession ->
                        dispatch(GeshtuEvent.ChannelClosed(sealed.artifact.hash))
                    },
                )

                GeshtuPhase.ChannelClosed -> ClosedChannelSurface(
                    artifact = pendingArtifact,
                    onKeepWriting = {
                        if (writeViewModel.resumeSealedSession(allowCompleted = true)) {
                            dispatch(GeshtuEvent.KeepWriting)
                            writeViewModel.openWritingPortal()
                        }
                    },
                    onReflection = ::requestReflection,
                    onLeave = ::settleCurrentDay,
                )

                GeshtuPhase.Reflection -> ReflectionSurface(
                    artifact = pendingArtifact,
                    reflectionMarkdown = reflectionState?.reflection?.reflection
                        ?: reflectionState?.streamingReflectionMarkdown.orEmpty(),
                    isResolved = reflectionState?.reflection != null,
                    didFail = reflectionState?.error != null,
                    onRetry = { reflectionViewModel?.askAnky() },
                    onSettle = ::settleCurrentDay,
                )

                else -> Unit
            }
        }

        if (continuity.anchorIsVisible) {
            GeshtuAnchor(
                offeringStands = continuity.offeringStands,
                onClick = {
                    view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    if (continuity.offeringStands) {
                        requestReflection()
                    } else {
                        openFreshWriting()
                    }
                },
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 8.dp)
                    .zIndex(1000f),
            )
        }

        if (continuity.phase == GeshtuPhase.Seed) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(LazurePigments.ankyPaper)
                    .zIndex(1400f),
            ) {
                YouScreen(
                    viewModel = youViewModel,
                    onWriteRequested = {
                        dispatch(GeshtuEvent.CloseSeed)
                        openFreshWriting()
                    },
                    onAccountDeleted = {
                        writeViewModel.resetAfterAccountDeletion()
                        dispatch(GeshtuEvent.Settle)
                    },
                    onAppLockChange = onAppLockChange,
                )
                IconButton(
                    onClick = { dispatch(GeshtuEvent.CloseSeed) },
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(12.dp)
                        .background(LazurePigments.ankyPaper.copy(alpha = 0.88f), CircleShape),
                ) {
                    Icon(
                        Icons.Outlined.KeyboardArrowDown,
                        contentDescription = "Close settings",
                        tint = LazurePigments.ankyInkSoft,
                    )
                }
            }
        }

        if (showsOnboarding) {
            GeshtuNameOnboarding(
                onFinished = { name ->
                    container.writingAnchorStore.save(
                        writerName = name.takeIf(String::isNotBlank),
                        anchorSentence = container.writingAnchorStore.anchorSentence,
                    )
                    showsOnboarding = false
                    scope.launch {
                        container.settingsStore.setOnboardingCompleted(true)
                    }
                    writeViewModel.openWritingPortal()
                },
                modifier = Modifier.fillMaxSize().zIndex(3000f),
            )
        }

        if (showsPaywall) {
            PaywallSheet(
                store = container.entitlementStore,
                origin = "reflection",
                onDismiss = { showsPaywall = false },
                onShowTerms = {},
                onShowPrivacy = {},
                subscriptionPreferences = container.subscriptionPreferences,
            )
        }
    }
}

@Composable
private fun GeshtuNameOnboarding(
    onFinished: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var name by remember { mutableStateOf("") }
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }

    Box(modifier.background(LazurePigments.ankyPaper)) {
        LazureWall(mood = LazureMood.Dawn, modifier = Modifier.fillMaxSize())
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.fillMaxSize().padding(horizontal = 36.dp),
        ) {
            Text(
                "what should i call you?",
                color = LazurePigments.ankyInk,
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.Light,
                fontSize = 26.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(40.dp))
            BasicTextField(
                value = name,
                onValueChange = { name = it.replace("\n", "") },
                textStyle = androidx.compose.ui.text.TextStyle(
                    color = LazurePigments.ankyInk,
                    fontFamily = FontFamily.Serif,
                    fontSize = 22.sp,
                    textAlign = TextAlign.Center,
                ),
                singleLine = true,
                cursorBrush = SolidColor(LazurePigments.ankyUmber),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Words,
                    imeAction = androidx.compose.ui.text.input.ImeAction.Done,
                ),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(
                    onDone = { onFinished(name.trim()) },
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .focusRequester(focusRequester)
                    .padding(horizontal = 42.dp, vertical = 8.dp)
                    .drawBehind {
                        drawLine(
                            color = LazurePigments.ankyInk.copy(alpha = 0.14f),
                            start = Offset(size.width * 0.2f, size.height),
                            end = Offset(size.width * 0.8f, size.height),
                            strokeWidth = 0.5.dp.toPx(),
                        )
                    },
            )
        }
    }
}

@Composable
private fun GeshtuWorldSurface(
    continuity: GeshtuContinuity,
    archive: List<SavedAnky>,
    reflections: Map<String, LocalReflection>,
    onOpenEntry: (SavedAnky) -> Unit,
    onCloseEntry: () -> Unit,
    onArmLateOffering: () -> Unit,
    onOpenSeed: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ordered = remember(archive) { archive.sortedByDescending(SavedAnky::createdAt) }
    if (ordered.isEmpty()) {
        Box(modifier, contentAlignment = Alignment.Center) {
            Text(
                "nothing here yet.\neverything you write will rise.",
                color = LazurePigments.ankyInkSoft,
                fontFamily = FontFamily.Serif,
                fontStyle = FontStyle.Italic,
                fontSize = 19.sp,
                lineHeight = 28.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 44.dp, vertical = 180.dp),
            )
        }
        return
    }

    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(top = 56.dp, start = 32.dp, end = 32.dp, bottom = 220.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        itemsIndexed(ordered, key = { _, entry -> entry.hash }) { index, entry ->
            if (index > 0) {
                StrataGarment(
                    emphasized = continuity.openedEntryHash == entry.hash ||
                        continuity.openedEntryHash == ordered.getOrNull(index - 1)?.hash,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
                )
            }
            if (continuity.openedEntryHash == entry.hash) {
                OpenedStrataEntry(
                    entry = entry,
                    reflection = reflections[entry.hash],
                    onClose = onCloseEntry,
                    showsLateOffering = !continuity.isLateOfferingArmed,
                    onArmLateOffering = onArmLateOffering,
                )
            } else {
                StrataEntryRow(
                    entry = entry,
                    ageOpacity = (1f - index * 0.11f).coerceAtLeast(0.16f),
                    onClick = { onOpenEntry(entry) },
                )
            }
        }
        item {
            IconButton(
                onClick = onOpenSeed,
                modifier = Modifier.fillMaxWidth().padding(top = 26.dp),
            ) {
                Icon(
                    Icons.Outlined.Spa,
                    contentDescription = "The seed. Settings and account.",
                    tint = LazurePigments.ankyGold.copy(alpha = 0.58f),
                )
            }
        }
    }
}

@Composable
private fun StrataEntryRow(
    entry: SavedAnky,
    ageOpacity: Float,
    onClick: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .alpha(ageOpacity)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
    ) {
        Text(
            firstLine(entry.reconstructedText),
            color = LazurePigments.ankyInk,
            fontFamily = FontFamily.Serif,
            fontSize = 20.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(6.dp))
        Text(
            strataDate(entry),
            color = LazurePigments.ankyInkSoft,
            fontFamily = FontFamily.Serif,
            fontSize = 12.sp,
        )
    }
}

@Composable
private fun OpenedStrataEntry(
    entry: SavedAnky,
    reflection: LocalReflection?,
    onClose: () -> Unit,
    showsLateOffering: Boolean,
    onArmLateOffering: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(bottom = 34.dp)) {
        Text(
            strataDate(entry, long = true),
            color = LazurePigments.ankyInkSoft,
            fontFamily = FontFamily.Serif,
            fontSize = 13.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClose)
                .padding(bottom = 20.dp),
        )
        Text(
            entry.reconstructedText,
            color = LazurePigments.ankyUmber.copy(alpha = 0.92f),
            style = LazureType.ankyProse,
            lineHeight = 28.sp,
        )
        reflection?.reflection?.takeIf(String::isNotBlank)?.let { reflected ->
            Box(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 34.dp),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier
                        .size(width = 46.dp, height = 1.dp)
                        .background(LazurePigments.ankyGold.copy(alpha = 0.3f)),
                )
            }
            Text(
                reflected,
                color = LazurePigments.ankySlate,
                fontFamily = FontFamily.Serif,
                fontStyle = FontStyle.Italic,
                fontSize = 18.sp,
                lineHeight = 28.sp,
            )
        } ?: run {
            if (entry.isComplete && showsLateOffering) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 34.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    LateOfferingGlyph(onClick = onArmLateOffering)
                }
            }
        }
    }
}

@Composable
private fun LateOfferingGlyph(onClick: () -> Unit) {
    Box(
        Modifier
            .size(58.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(34.dp)) {
            drawCircle(LazurePigments.ankyInk.copy(alpha = 0.10f))
            val path = Path()
            val points = 54
            val maxRadius = 11.dp.toPx()
            for (step in 0..points) {
                val fraction = step.toFloat() / points
                val angle = fraction * 2.4f * 2f * PI.toFloat()
                val radius = maxRadius * fraction
                val point = Offset(
                    center.x + cos(angle) * radius,
                    center.y + sin(angle) * radius,
                )
                if (step == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
            }
            drawPath(
                path,
                LazurePigments.ankyInkSoft.copy(alpha = 0.55f),
                style = Stroke(width = 1.4.dp.toPx(), cap = StrokeCap.Round),
            )
        }
    }
}

@Composable
private fun StrataGarment(
    emphasized: Boolean,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier.height(14.dp)) {
        val centerY = size.height / 2
        val alpha = if (emphasized) 0.72f else 0.38f
        drawLine(
            brush = Brush.horizontalGradient(
                listOf(
                    Color.Transparent,
                    LazurePigments.ankyViolet.copy(alpha = alpha),
                    LazurePigments.ankyViolet.copy(alpha = alpha),
                    Color.Transparent,
                ),
            ),
            start = Offset(size.width * 0.18f, centerY),
            end = Offset(size.width * 0.82f, centerY),
            strokeWidth = 1.dp.toPx(),
        )
        val diamondPath = Path().apply {
            moveTo(size.width / 2, centerY - 5.dp.toPx())
            lineTo(size.width / 2 + 5.dp.toPx(), centerY)
            lineTo(size.width / 2, centerY + 5.dp.toPx())
            lineTo(size.width / 2 - 5.dp.toPx(), centerY)
            close()
        }
        drawPath(
            diamondPath,
            LazurePigments.ankyGold.copy(alpha = if (emphasized) 0.92f else 0.55f),
            style = Stroke(width = 1.dp.toPx()),
        )
        drawCircle(
            LazurePigments.ankyGold.copy(alpha = if (emphasized) 0.82f else 0.48f),
            radius = 1.8.dp.toPx(),
            center = center,
        )
    }
}

@Composable
private fun ClosedChannelSurface(
    artifact: SavedAnky?,
    onKeepWriting: () -> Unit,
    onReflection: () -> Unit,
    onLeave: () -> Unit,
) {
    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(LazurePigments.ankyPaper, LazurePigments.ankyPaperDeep),
                ),
            ),
    ) {
        Text(
            artifact?.reconstructedText.orEmpty(),
            color = LazurePigments.ankyUmber.copy(alpha = 0.92f),
            style = LazureType.ankyProse,
            textAlign = TextAlign.Start,
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.Center)
                .padding(horizontal = 24.dp, vertical = 120.dp),
        )
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 54.dp),
        ) {
            CrossroadsButton("keep writing", prominent = false, onClick = onKeepWriting)
            CrossroadsButton("get anky's reflection", prominent = true, onClick = onReflection)
            CrossroadsButton("just leave", prominent = false, onClick = onLeave)
        }
        GeshtuTopChrome(
            writing = artifact?.reconstructedText,
            showsSettings = false,
            onSettings = {},
        )
    }
}

@Composable
private fun CrossroadsButton(
    label: String,
    prominent: Boolean,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        shape = RoundedCornerShape(100),
        colors = ButtonDefaults.buttonColors(
            containerColor = LazurePigments.ankyPaper.copy(alpha = if (prominent) 0.94f else 0.78f),
            contentColor = if (prominent) LazurePigments.ankyInk else LazurePigments.ankyInkSoft,
        ),
        contentPadding = PaddingValues(
            horizontal = if (prominent) 20.dp else 16.dp,
            vertical = if (prominent) 11.dp else 9.dp,
        ),
        modifier = Modifier.drawBehind {
            drawRoundRect(
                color = LazurePigments.ankyGold.copy(alpha = if (prominent) 0.6f else 0.35f),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2),
                style = Stroke(width = 1.dp.toPx()),
            )
        },
    ) {
        Text(
            label,
            fontFamily = FontFamily.Serif,
            fontStyle = FontStyle.Italic,
            fontSize = if (prominent) 16.sp else 14.sp,
        )
    }
}

@Composable
private fun ReflectionSurface(
    artifact: SavedAnky?,
    reflectionMarkdown: String,
    isResolved: Boolean,
    didFail: Boolean,
    onRetry: () -> Unit,
    onSettle: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(LazurePigments.ankyPaper, LazurePigments.ankyPaperDeep),
                ),
            ),
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = 82.dp, start = 30.dp, end = 30.dp, bottom = 90.dp),
        ) {
            item {
                Text(
                    artifact?.reconstructedText.orEmpty(),
                    color = LazurePigments.ankyUmber.copy(alpha = 0.90f),
                    style = LazureType.ankyProse,
                    lineHeight = 28.sp,
                )
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 34.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier
                            .size(width = 46.dp, height = 1.dp)
                            .background(LazurePigments.ankyGold.copy(alpha = 0.3f)),
                    )
                }
            }
            item {
                when {
                    didFail -> Text(
                        "the reflection was lost on the way\ntap to ask again",
                        color = LazurePigments.ankyInkSoft,
                        fontFamily = FontFamily.Serif,
                        fontStyle = FontStyle.Italic,
                        fontSize = 16.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(onClick = onRetry)
                            .padding(vertical = 30.dp),
                    )

                    reflectionMarkdown.isBlank() && !isResolved -> ListeningSpiral(
                        Modifier.fillMaxWidth().height(120.dp),
                    )

                    else -> Text(
                        reflectionMarkdown,
                        color = LazurePigments.ankySlate,
                        fontFamily = FontFamily.Serif,
                        fontStyle = FontStyle.Italic,
                        fontSize = 19.sp,
                        lineHeight = 30.sp,
                    )
                }
            }
            item {
                Text(
                    "let this day settle",
                    color = LazurePigments.ankyInkSoft,
                    fontFamily = FontFamily.Serif,
                    fontStyle = FontStyle.Italic,
                    fontSize = 14.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(enabled = isResolved || didFail, onClick = onSettle)
                        .padding(top = 72.dp, bottom = 30.dp)
                        .alpha(if (isResolved || didFail) 0.9f else 0.25f),
                )
            }
        }
        GeshtuTopChrome(
            writing = artifact?.reconstructedText,
            showsSettings = false,
            onSettings = {},
        )
    }
}

@Composable
private fun ListeningSpiral(modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val points = 84
        val path = Path()
        val maxRadius = 42.dp.toPx()
        for (step in 0..points) {
            val fraction = step.toFloat() / points
            val angle = fraction * 2.4f * 2f * PI.toFloat()
            val radius = maxRadius * fraction
            val point = Offset(
                x = center.x + cos(angle) * radius,
                y = center.y + sin(angle) * radius,
            )
            if (step == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
        }
        drawPath(
            path,
            color = LazurePigments.ankyGold.copy(alpha = 0.46f),
            style = Stroke(width = 1.6.dp.toPx(), cap = StrokeCap.Round),
        )
    }
}

@Composable
private fun GeshtuAnchor(
    offeringStands: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier
            .size(108.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(
                brush = Brush.radialGradient(
                    listOf(
                        LazurePigments.ankyGoldLight.copy(alpha = if (offeringStands) 0.65f else 0.42f),
                        Color.Transparent,
                    ),
                ),
                radius = size.minDimension / 2,
            )
            drawCircle(
                color = Color(0xFF9E6F42),
                radius = 28.dp.toPx(),
            )
            drawCircle(
                color = Color(0xFFF0D095).copy(alpha = 0.52f),
                radius = 25.dp.toPx(),
                style = Stroke(width = 1.2.dp.toPx()),
            )
            val path = Path()
            val points = 72
            val maxRadius = 17.dp.toPx()
            for (step in 0..points) {
                val fraction = step.toFloat() / points
                val angle = fraction * 2.4f * 2f * PI.toFloat()
                val radius = maxRadius * fraction
                val point = Offset(
                    center.x + cos(angle) * radius,
                    center.y + sin(angle) * radius,
                )
                if (step == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
            }
            drawPath(
                path,
                LazurePigments.ankyGoldLight.copy(alpha = 0.88f),
                style = Stroke(width = 1.8.dp.toPx(), cap = StrokeCap.Round),
            )
        }
    }
}

@Composable
private fun GeshtuTopChrome(
    writing: String?,
    showsSettings: Boolean,
    onSettings: () -> Unit,
) {
    val context = LocalContext.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp, start = 14.dp, end = 14.dp),
    ) {
        Spacer(Modifier.weight(1f))
        writing?.takeIf(String::isNotBlank)?.let { text ->
            ChromeButton(
                icon = Icons.Outlined.ContentCopy,
                label = "Copy writing",
                modifier = Modifier.pointerInput(text) {
                    detectTapGestures(
                        onTap = { copyText(context, "Anky writing", text) },
                        onLongPress = {
                            copyText(
                                context,
                                "Anky reflection prompt",
                                AnkyReflectionPrompt.build(text),
                            )
                        },
                    )
                },
                onClick = {},
            )
            ChromeButton(
                icon = Icons.Outlined.Share,
                label = "Share writing",
                onClick = { shareText(context, text) },
            )
        }
        if (showsSettings) {
            ChromeButton(
                icon = Icons.Outlined.Settings,
                label = "Settings",
                onClick = onSettings,
            )
        }
    }
}

@Composable
private fun ChromeButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier
            .size(40.dp)
            .background(LazurePigments.ankyPaper.copy(alpha = 0.72f), CircleShape),
    ) {
        Icon(icon, contentDescription = label, tint = LazurePigments.ankyInkSoft)
    }
}

private fun firstLine(text: String): String =
    text.lineSequence().map(String::trim).firstOrNull(String::isNotBlank) ?: "—"

private fun archiveText(archive: List<SavedAnky>, hash: String): String? =
    archive.firstOrNull { it.hash == hash }?.reconstructedText

private fun strataDate(entry: SavedAnky, long: Boolean = false): String {
    val pattern = if (long) "dd MMMM yyyy" else "dd MMM yyyy"
    return DateTimeFormatter
        .ofPattern(pattern, Locale.getDefault())
        .withZone(ZoneId.systemDefault())
        .format(entry.createdAt)
        .lowercase(Locale.getDefault())
}

private fun copyText(context: Context, label: String, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

private fun shareText(context: Context, text: String) {
    val intent = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_TEXT, text)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(Intent.createChooser(intent, "Share writing").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}
