package inc.anky.android.app

import android.content.Context
import android.content.ContextWrapper
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Map
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.NavType
import androidx.navigation.navArgument
import inc.anky.android.R
import inc.anky.android.core.identity.DeviceBiometricGate
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.feature.map.MapScreen
import inc.anky.android.feature.map.MapViewModel
import inc.anky.android.feature.reveal.RevealScreen
import inc.anky.android.feature.reveal.RevealViewModel
import inc.anky.android.feature.reveal.TagSessionsScreen
import inc.anky.android.feature.write.WriteScreen
import inc.anky.android.feature.write.WriteViewModel
import inc.anky.android.feature.you.YouInitialPage
import inc.anky.android.feature.you.YouScreen
import inc.anky.android.feature.you.YouViewModel
import inc.anky.android.core.storage.SingleAnkyImporter
import inc.anky.android.ui.components.AnkyChatAction
import inc.anky.android.ui.components.AnkyPresenceOverlay
import inc.anky.android.ui.components.AnkyConversationPrompt
import inc.anky.android.ui.components.AnkySequenceName
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyTheme

@Composable
fun AnkyApp(container: AppContainer) {
    AnkyTheme {
        val navController = rememberNavController()
        val tabs = listOf(AnkyRoute.Write, AnkyRoute.Map, AnkyRoute.You)
        val currentRoute = navController.currentBackStackEntryAsState().value?.destination?.route
        val settings = container.settingsStore.settings.collectAsStateWithLifecycle<UserSettings?>(
            initialValue = null,
        ).value
        val context = LocalContext.current
        val rootView = LocalView.current
        val biometricGate = remember(context) {
            DeviceBiometricGate { context.findFragmentActivity() }
        }
        val freeCreditPromptPrefs = remember(context) {
            context.getSharedPreferences("anky-credit-prompt", Context.MODE_PRIVATE)
        }
        val lifecycleOwner = LocalLifecycleOwner.current
        val lockState = remember { mutableStateOf(LockState.Locked) }
        val unlockAttempt = remember { mutableIntStateOf(0) }
        val failedAuthAttempts = remember { mutableIntStateOf(0) }
        val recoveryPhraseInput = remember { mutableStateOf("") }
        val recoveryError = remember { mutableStateOf<String?>(null) }
        val identityRecoveryNonce = remember { mutableIntStateOf(0) }
        val rootCreditBalance = remember { mutableStateOf<Int?>(null) }

        suspend fun refreshRootCreditBalance() {
            val identity = runCatching { container.identityStore.loadOrCreate() }.getOrNull() ?: return
            runCatching {
                container.creditsClient.configure(identity.accountId)
                rootCreditBalance.value = container.creditsClient.refresh().balance
            }
        }

        if (settings == null) {
            Box(modifier = Modifier.fillMaxSize())
            return@AnkyTheme
        }

        DisposableEffect(settings.appLockEnabled, lifecycleOwner) {
            val observer = LifecycleEventObserver { _, event ->
                when (event) {
                    Lifecycle.Event.ON_STOP -> {
                        if (settings.appLockEnabled) {
                            lockState.value = LockState.Locked
                            failedAuthAttempts.intValue = 0
                            recoveryPhraseInput.value = ""
                            recoveryError.value = null
                        }
                    }
                    Lifecycle.Event.ON_START -> {
                        if (settings.appLockEnabled && lockState.value != LockState.Unlocked) {
                            unlockAttempt.intValue += 1
                        }
                    }
                    else -> Unit
                }
            }
            lifecycleOwner.lifecycle.addObserver(observer)
            onDispose {
                lifecycleOwner.lifecycle.removeObserver(observer)
            }
        }

        LaunchedEffect(settings.appLockEnabled, unlockAttempt.intValue) {
            if (settings.appLockEnabled) {
                lockState.value = LockState.Authenticating
                if (biometricGate.authenticate("Unlock ANKY.")) {
                    failedAuthAttempts.intValue = 0
                    recoveryPhraseInput.value = ""
                    recoveryError.value = null
                    lockState.value = LockState.Unlocked
                } else {
                    failedAuthAttempts.intValue += 1
                    lockState.value = LockState.Failed
                }
            } else {
                failedAuthAttempts.intValue = 0
                recoveryPhraseInput.value = ""
                recoveryError.value = null
                lockState.value = LockState.Unlocked
            }
        }

        if (settings.appLockEnabled && lockState.value != LockState.Unlocked) {
            fun recoverIdentityFromPhrase() {
                val normalized = normalizeRecoveryPhrase(recoveryPhraseInput.value)
                if (normalized.split(" ").filter { it.isNotBlank() }.size != 12) {
                    recoveryError.value = "enter the 12 word recovery phrase."
                    return
                }
                runCatching {
                    container.identityStore.importRecoveryPhrase(normalized)
                }.onSuccess {
                    failedAuthAttempts.intValue = 0
                    recoveryPhraseInput.value = ""
                    recoveryError.value = null
                    identityRecoveryNonce.intValue += 1
                    lockState.value = LockState.Unlocked
                }.onFailure {
                    recoveryError.value = "that recovery phrase did not open this identity."
                }
            }

            Box(
                modifier = Modifier.fillMaxSize().background(Color.White),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    painter = painterResource(R.drawable.tellmewhoyouare),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    modifier = Modifier.padding(24.dp),
                ) {
                    if (lockState.value == LockState.Locked || lockState.value == LockState.Authenticating) {
                        CircularProgressIndicator(color = Color.White)
                    } else {
                        if (failedAuthAttempts.intValue >= 2) {
                            OutlinedTextField(
                                value = recoveryPhraseInput.value,
                                onValueChange = { value ->
                                    recoveryPhraseInput.value = value
                                    recoveryError.value = null
                                    if (normalizeRecoveryPhrase(value).split(" ").filter { it.isNotBlank() }.size == 12) {
                                        recoverIdentityFromPhrase()
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text("recovery phrase", color = Color.White.copy(alpha = 0.78f)) },
                                textStyle = TextStyle(color = Color.White),
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                                singleLine = false,
                            )
                            recoveryError.value?.let { message ->
                                Text(
                                    message,
                                    color = Color.White.copy(alpha = 0.82f),
                                    textAlign = TextAlign.Center,
                                )
                            }
                            Button(
                                onClick = { recoverIdentityFromPhrase() },
                                shape = RoundedCornerShape(14.dp),
                            ) { Text("recover identity") }
                        } else {
                            Text(
                                "face id didn't work. you should not be here",
                                color = Color.White,
                                textAlign = TextAlign.Center,
                            )
                            Button(
                                onClick = {
                                    recoveryError.value = null
                                    unlockAttempt.intValue += 1
                                },
                                shape = RoundedCornerShape(14.dp),
                            ) { Text("Try again") }
                        }
                    }
                }
            }
            return@AnkyTheme
        }

        LaunchedEffect(lockState.value) {
            if (lockState.value == LockState.Unlocked) {
                runCatching { container.appOpenStore.loadOrCreate() }
                refreshRootCreditBalance()
            }
        }

        val currentMirrorBaseUrl = rememberUpdatedState(settings.mirrorBaseUrl)
        val writeViewModel = remember {
            WriteViewModel(
                activeDraftStore = container.activeDraftStore,
                archive = container.archive,
                reflectionStore = container.reflectionStore,
                indexStore = container.sessionIndexStore,
                identityProvider = { container.identityStore.loadOrCreate() },
                mirrorClientProvider = { container.mirrorClient(currentMirrorBaseUrl.value) },
            )
        }
        val mapViewModel = remember {
            MapViewModel(
                archive = container.archive,
                reflectionStore = container.reflectionStore,
                indexStore = container.sessionIndexStore,
                appOpenStore = container.appOpenStore,
            )
        }
        val writeViewModelWithCurrentMirror = writeViewModel
        val writeState = writeViewModelWithCurrentMirror.state.collectAsStateWithLifecycle().value
        val showsLaunchDialogue = remember { mutableStateOf(true) }
        val companionNote = remember { mutableStateOf<String?>(null) }
        val writeCompanionNoteIndex = remember { mutableIntStateOf(0) }
        val mapCompanionNoteIndex = remember { mutableIntStateOf(0) }
        val youCompanionNoteIndex = remember { mutableIntStateOf(0) }
        val isShowingYouExperience = remember { mutableStateOf(false) }
        val importedCompletedHash = remember { mutableStateOf<String?>(null) }
        val postWriteCompletedHash = importedCompletedHash.value ?: writeState.completedHash

        LaunchedEffect(writeState.acceptedGlyphCount) {
            if (writeState.acceptedGlyphCount > 0) {
                showsLaunchDialogue.value = false
            }
        }
        LaunchedEffect(postWriteCompletedHash, lockState.value) {
            if (lockState.value == LockState.Unlocked && postWriteCompletedHash != null) {
                refreshRootCreditBalance()
            }
        }
        LaunchedEffect(currentRoute) {
            companionNote.value = null
            isShowingYouExperience.value = false
        }

        fun showCompanionNote(): Boolean {
            showsLaunchDialogue.value = false
            val messages = companionMessages(currentRoute, writeState.hasReachedRitualMark)
            val indexState = when (currentRoute) {
                AnkyRoute.Write.route, null -> writeCompanionNoteIndex
                AnkyRoute.Map.route -> mapCompanionNoteIndex
                AnkyRoute.You.route, AnkyRoute.YouCredits.route -> youCompanionNoteIndex
                else -> null
            }
            val index = indexState?.intValue ?: 0
            companionNote.value = messages[index % messages.size]
            indexState?.intValue = index + 1
            return true
        }

        fun beginRetryWriting() {
            showsLaunchDialogue.value = false
            companionNote.value = null
            importedCompletedHash.value = null
            writeViewModelWithCurrentMirror.consumeCompletedHash()
            navController.navigate(AnkyRoute.Write.route) {
                launchSingleTop = true
                popUpTo(AnkyRoute.Write.route) { inclusive = false }
            }
            writeViewModelWithCurrentMirror.openWritingPortal()
        }

        Box(Modifier.fillMaxSize()) {
            Scaffold(
                containerColor = AnkyColors.Background,
                bottomBar = {
                    if (
                        currentRoute != AnkyRoute.Write.route &&
                        currentRoute != AnkyRoute.Reveal.route &&
                        currentRoute != AnkyRoute.TagSessions.route &&
                        !isShowingYouExperience.value
                    ) {
                        NavigationBar(
                            containerColor = AnkyColors.Ink.copy(alpha = 0.96f),
                            contentColor = AnkyColors.Paper,
                        ) {
                            tabs.forEach { tab ->
                                NavigationBarItem(
                                    selected = tab.isSelectedForRoute(currentRoute),
                                    onClick = {
                                        navController.navigate(tab.route) {
                                            launchSingleTop = true
                                            popUpTo(AnkyRoute.Write.route)
                                        }
                                    },
                                    label = { Text(tab.label) },
                                    icon = {
                                        Icon(
                                            imageVector = tab.icon(),
                                            contentDescription = tab.label,
                                        )
                                    },
                                    colors = NavigationBarItemDefaults.colors(
                                        selectedIconColor = AnkyColors.Gold,
                                        selectedTextColor = AnkyColors.Gold,
                                        unselectedIconColor = AnkyColors.PaperMuted,
                                        unselectedTextColor = AnkyColors.PaperMuted,
                                        indicatorColor = AnkyColors.PanelStrong,
                                    ),
                                )
                            }
                        }
                    }
                },
            ) { padding ->
                NavHost(
                    navController = navController,
                    startDestination = AnkyRoute.Write.route,
                    modifier = Modifier.padding(padding),
                ) {
                    composable(AnkyRoute.Write.route) {
                        WriteScreen(
                            viewModel = writeViewModelWithCurrentMirror,
                            onImported = { hash ->
                                importedCompletedHash.value = hash
                                showsLaunchDialogue.value = false
                                companionNote.value = null
                            },
                            onCloseToMap = { navController.navigate(AnkyRoute.Map.route) },
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
                        )
                    }
                    composable(AnkyRoute.Map.route) {
                        MapScreen(
                            viewModel = mapViewModel,
                            onOpenReveal = { hash -> navController.navigate(AnkyRoute.Reveal.route(hash)) },
                        )
                    }
                    composable(AnkyRoute.You.route) {
                        val identityVersion = identityRecoveryNonce.intValue
                        val viewModel = remember(identityVersion) {
                            YouViewModel(
                                identityStore = container.identityStore,
                                settingsStore = container.settingsStore,
                                reminderScheduler = container.reminderScheduler,
                                creditsClient = container.creditsClient,
                                exporter = container.exporter,
                                backupImporter = container.backupImporter,
                                archive = container.archive,
                                reflectionStore = container.reflectionStore,
                                indexStore = container.sessionIndexStore,
                                biometricGate = biometricGate,
                            )
                        }
                        YouScreen(
                            viewModel = viewModel,
                            onExperienceVisibilityChanged = { isShowingYouExperience.value = it },
                        )
                    }
                    composable(AnkyRoute.YouCredits.route) {
                        val identityVersion = identityRecoveryNonce.intValue
                        val viewModel = remember(identityVersion) {
                            YouViewModel(
                                identityStore = container.identityStore,
                                settingsStore = container.settingsStore,
                                reminderScheduler = container.reminderScheduler,
                                creditsClient = container.creditsClient,
                                exporter = container.exporter,
                                backupImporter = container.backupImporter,
                                archive = container.archive,
                                reflectionStore = container.reflectionStore,
                                indexStore = container.sessionIndexStore,
                                biometricGate = biometricGate,
                            )
                        }
                        YouScreen(
                            viewModel = viewModel,
                            initialPage = YouInitialPage.Credits,
                            onInitialPageBack = { navController.popBackStack() },
                            onExperienceVisibilityChanged = { isShowingYouExperience.value = it },
                        )
                    }
                    composable(
                        AnkyRoute.Reveal.route,
                        arguments = listOf(
                            navArgument("hash") { type = NavType.StringType },
                            navArgument("reflect") {
                                type = NavType.BoolType
                                defaultValue = false
                            },
                        ),
                    ) { entry ->
                        val hash = entry.arguments?.getString("hash").orEmpty()
                        val startsReflectionOnAppear = entry.arguments?.getBoolean("reflect") ?: false
                        val viewModel = remember(hash, settings.mirrorBaseUrl) {
                            RevealViewModel(
                                hash = hash,
                                archive = container.archive,
                                reflectionStore = container.reflectionStore,
                                requestStore = container.reflectionRequestStore,
                                indexStore = container.sessionIndexStore,
                                identityStore = container.identityStore,
                                mirrorClientProvider = { container.mirrorClient(settings.mirrorBaseUrl) },
                                creditsClient = container.creditsClient,
                                hasClaimedFreeCreditsProvider = {
                                    freeCreditPromptPrefs.getBoolean("hasClaimedFreeReflections", false)
                                },
                                markFreeCreditsClaimed = {
                                    freeCreditPromptPrefs.edit().putBoolean("hasClaimedFreeReflections", true).apply()
                                },
                            )
                        }
                        RevealScreen(
                            viewModel = viewModel,
                            startsReflectionOnAppear = startsReflectionOnAppear,
                            onOpenTag = { tag -> navController.navigate(AnkyRoute.TagSessions.route(tag)) },
                            onOpenCredits = { navController.navigate(AnkyRoute.YouCredits.route) },
                            onDeleted = {
                                writeViewModelWithCurrentMirror.consumeCompletedHash()
                                mapViewModel.refresh()
                            },
                            onTryAgain = { beginRetryWriting() },
                            onBack = { navController.popBackStack() },
                        )
                    }
                    composable(
                        AnkyRoute.TagSessions.route,
                        arguments = listOf(navArgument("tag") { type = NavType.StringType }),
                    ) { entry ->
                        val tag = entry.arguments?.getString("tag").orEmpty()
                        TagSessionsScreen(
                            tag = tag,
                            sessionIndexStore = container.sessionIndexStore,
                            archive = container.archive,
                            onBack = { navController.popBackStack() },
                            onOpenReveal = { hash -> navController.navigate(AnkyRoute.Reveal.route(hash)) },
                        )
                    }
                }
            }
            if (!isShowingYouExperience.value) {
                AnkyPresenceOverlay(
                    defaultSequence = presenceSequence(currentRoute, writeState.hasReachedRitualMark),
                    goldenGlow = currentRoute == AnkyRoute.Write.route && writeState.hasReachedRitualMark,
                    transformToSigil = currentRoute == AnkyRoute.Write.route && writeState.acceptedGlyphCount > 0 && !writeState.hasReachedRitualMark,
                    onTap = {
                        if (currentRoute == AnkyRoute.Write.route && writeState.acceptedGlyphCount > 0 && !writeState.hasReachedRitualMark) {
                            writeViewModelWithCurrentMirror.startAnkyNudgeIfPossible()
                        } else if (currentRoute == AnkyRoute.Write.route && writeViewModelWithCurrentMirror.replayRecentPromptIfAvailable()) {
                            true
                        } else {
                            showCompanionNote()
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }
            if (
                currentRoute == AnkyRoute.Write.route &&
                postWriteCompletedHash != null
            ) {
                val postWriteCreditBadge = rootCreditBalance.value?.let(::creditBadge)
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
                    AnkyConversationPrompt(
                        message = "you wrote an anky.\n\ndo you want me to reflect it?",
                        actions = listOf(
                            AnkyChatAction("reflect (1 credit)", badge = postWriteCreditBadge, isPrimary = true) {
                                val hash = postWriteCompletedHash ?: return@AnkyChatAction
                                importedCompletedHash.value = null
                                writeViewModelWithCurrentMirror.consumeCompletedHash()
                                navController.navigate(AnkyRoute.Reveal.route(hash, reflect = true))
                            },
                            AnkyChatAction("not now") {
                                val hash = postWriteCompletedHash ?: return@AnkyChatAction
                                importedCompletedHash.value = null
                                writeViewModelWithCurrentMirror.consumeCompletedHash()
                                navController.navigate(AnkyRoute.Map.route) {
                                    launchSingleTop = true
                                    popUpTo(AnkyRoute.Write.route)
                                }
                                navController.navigate(AnkyRoute.Reveal.route(hash))
                            },
                        ),
                        modifier = Modifier
                            .padding(start = 108.dp, end = 18.dp, bottom = 96.dp),
                    )
                }
            } else if (
                currentRoute == AnkyRoute.Write.route &&
                writeState.errorMessage != null
            ) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
                    AnkyConversationPrompt(
                        message = writeState.errorMessage.orEmpty(),
                        onClose = writeViewModelWithCurrentMirror::dismissCurrentPrompt,
                        modifier = Modifier
                            .padding(start = 108.dp, end = 18.dp, bottom = 96.dp),
                    )
                }
            } else if (
                currentRoute == AnkyRoute.Write.route &&
                writeState.shouldShowNudgeDialogue &&
                writeState.nudgeDialogueMessage.isNotBlank()
            ) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
                    AnkyConversationPrompt(
                        message = writeState.nudgeDialogueMessage,
                        onClose = writeViewModelWithCurrentMirror::dismissCurrentPrompt,
                        modifier = Modifier
                            .padding(start = 108.dp, end = 18.dp, bottom = 96.dp),
                    )
                }
            } else if (companionNote.value != null && !isShowingYouExperience.value) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
                    AnkyConversationPrompt(
                        message = companionNote.value.orEmpty(),
                        onClose = { companionNote.value = null },
                        modifier = Modifier
                            .padding(start = 108.dp, end = 18.dp, bottom = 96.dp),
                    )
                }
            } else if (
                currentRoute == AnkyRoute.Write.route &&
                showsLaunchDialogue.value &&
                writeState.acceptedGlyphCount == 0 &&
                !writeState.isClosing &&
                writeState.errorMessage == null
            ) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
                    AnkyConversationPrompt(
                        message = if (writeState.todayAnkyCount > 0) {
                            "ankys today: ${writeState.todayAnkyCount}"
                        } else {
                            "the living .anky string is the state of this session."
                        },
                        actions = listOf(
                            AnkyChatAction(
                                if (writeState.todayAnkyCount > 0) "write again" else "write ${AnkyDuration.CompleteRitualMs / 60_000} minutes",
                                isPrimary = true,
                            ) {
                                rootView.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                                writeViewModelWithCurrentMirror.openWritingPortal()
                                showsLaunchDialogue.value = false
                            },
                        ),
                        steps = listOf(
                            "write one character",
                            "keep the thread alive",
                            "let silence close it",
                        ),
                        onClose = { showsLaunchDialogue.value = false },
                        modifier = Modifier
                            .padding(start = 108.dp, end = 18.dp, bottom = 96.dp),
                    )
                }
            }
        }
    }
}

private enum class LockState {
    Locked,
    Authenticating,
    Unlocked,
    Failed,
}

private fun normalizeRecoveryPhrase(text: String): String =
    text.lowercase().split(Regex("""\s+""")).filter { it.isNotBlank() }.joinToString(" ")

private fun creditBadge(balance: Int): String =
    "$balance ${if (balance == 1) "credit" else "credits"}"

private fun presenceSequence(route: String?, writeRitualComplete: Boolean): AnkySequenceName =
    when (route) {
        AnkyRoute.Write.route, null -> if (writeRitualComplete) AnkySequenceName.Celebrate else AnkySequenceName.FindingThread
        AnkyRoute.Map.route -> AnkySequenceName.WalkRight
        AnkyRoute.You.route, AnkyRoute.YouCredits.route -> AnkySequenceName.WaveFront
        else -> AnkySequenceName.IdleFront
    }

private fun companionMessages(route: String?, writeRitualComplete: Boolean): List<String> =
    when (route) {
        AnkyRoute.Write.route, null -> if (writeRitualComplete) {
            listOf(
                "you are here. the ritual is complete; let the final silence close it.",
                "you are here. this .anky is ready to become an artifact.",
                "you are here. the thread crossed ${AnkyDuration.CompleteRitualMs / 60_000} minutes. stay quiet and let it seal.",
            )
        } else {
            listOf(
                "you are here. this is the writing surface: one living thread, one character at a time.",
                "you are here. deletion is blocked on purpose; keep moving forward without editing.",
                "you are here. writing stays local unless you export it or ask for a reflection.",
                "you are here. ${AnkyDuration.CompleteRitualMs / 60_000} minutes turns a fragment into a complete .anky.",
            )
        }
        AnkyRoute.Map.route -> listOf(
            "you are here. the map is your local trail; every day exists even when it is quiet.",
            "you are here. tap a day to reopen its .ankys and saved reflections.",
            "you are here. the trail begins on the first day this app opened on this device.",
            "you are here. fragments and complete ankys both stay in your local archive.",
        )
        AnkyRoute.You.route, AnkyRoute.YouCredits.route -> listOf(
            "you are here. this page is for identity, privacy, exports, and reflection credits.",
            "you are here. your identity unlocks reflections, backups, and credit balance.",
            "you are here. data leaves this phone only when you choose export or reflection.",
            "you are here. credits buy reflections; writing itself stays free.",
        )
        else -> listOf("you are here.")
    }

private fun AnkyRoute.icon() =
    when (this) {
        AnkyRoute.Write -> Icons.Outlined.Edit
        AnkyRoute.Map -> Icons.Outlined.Map
        AnkyRoute.You -> Icons.Outlined.AccountCircle
        AnkyRoute.YouCredits -> Icons.Outlined.AccountCircle
        AnkyRoute.Reveal -> Icons.Outlined.Edit
        AnkyRoute.TagSessions -> Icons.Outlined.Map
    }

private fun AnkyRoute.isSelectedForRoute(currentRoute: String?): Boolean =
    when (this) {
        AnkyRoute.You -> currentRoute == AnkyRoute.You.route || currentRoute == AnkyRoute.YouCredits.route
        else -> currentRoute == route
    }

private tailrec fun Context.findFragmentActivity(): FragmentActivity? =
    when (this) {
        is FragmentActivity -> this
        is ContextWrapper -> baseContext.findFragmentActivity()
        else -> null
    }
