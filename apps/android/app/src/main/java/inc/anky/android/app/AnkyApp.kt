package inc.anky.android.app

import android.content.Context
import android.content.ContextWrapper
import androidx.biometric.BiometricManager
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
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
import inc.anky.android.feature.map.MapScreen
import inc.anky.android.feature.map.MapViewModel
import inc.anky.android.feature.onboarding.AnkyOnboardingScreen
import inc.anky.android.feature.reveal.RevealScreen
import inc.anky.android.feature.reveal.RevealViewModel
import inc.anky.android.feature.reveal.TagSessionsScreen
import inc.anky.android.feature.write.WriteScreen
import inc.anky.android.feature.write.WriteViewModel
import inc.anky.android.feature.you.YouInitialPage
import inc.anky.android.feature.you.YouScreen
import inc.anky.android.feature.you.YouViewModel
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.core.storage.SingleAnkyImporter
import inc.anky.android.ui.components.AnkyPresenceOverlay
import inc.anky.android.ui.components.AnkyConversationPrompt
import inc.anky.android.ui.components.AnkySequenceName
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyTheme
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.launch

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
        val rootScope = rememberCoroutineScope()
        val biometricGate = remember(context) {
            DeviceBiometricGate { context.findFragmentActivity() }
        }
        val lifecycleOwner = LocalLifecycleOwner.current
        val lockState = remember { mutableStateOf(LockState.Locked) }
        val unlockAttempt = remember { mutableIntStateOf(0) }
        val failedAuthAttempts = remember { mutableIntStateOf(0) }
        val recoveryPhraseInput = remember { mutableStateOf("") }
        val recoveryError = remember { mutableStateOf<String?>(null) }
        val identityRecoveryNonce = remember { mutableIntStateOf(0) }
        val showsDeviceLockActivationPrompt = remember { mutableStateOf(false) }
        val skipNextAppLockAuthentication = remember { mutableStateOf(false) }

        if (settings == null) {
            Box(modifier = Modifier.fillMaxSize())
            return@AnkyTheme
        }
        val unlockDeviceLockReason = stringResource(R.string.unlock_device_lock_reason)
        val protectDeviceLockReason = stringResource(R.string.protect_device_lock_reason)

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
                if (skipNextAppLockAuthentication.value) {
                    skipNextAppLockAuthentication.value = false
                    failedAuthAttempts.intValue = 0
                    recoveryPhraseInput.value = ""
                    recoveryError.value = null
                    lockState.value = LockState.Unlocked
                } else {
                    lockState.value = LockState.Authenticating
                    if (biometricGate.authenticate(unlockDeviceLockReason)) {
                        failedAuthAttempts.intValue = 0
                        recoveryPhraseInput.value = ""
                        recoveryError.value = null
                        lockState.value = LockState.Unlocked
                    } else {
                        failedAuthAttempts.intValue += 1
                        lockState.value = LockState.Failed
                    }
                }
            } else {
                failedAuthAttempts.intValue = 0
                recoveryPhraseInput.value = ""
                recoveryError.value = null
                lockState.value = LockState.Unlocked
            }
        }

        if (settings.appLockEnabled && lockState.value != LockState.Unlocked) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black)
                    .clickable(enabled = lockState.value == LockState.Failed) {
                        recoveryError.value = null
                        unlockAttempt.intValue += 1
                    },
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    painter = painterResource(R.drawable.tellmewhoyouare),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            return@AnkyTheme
        }

        LaunchedEffect(lockState.value) {
            if (lockState.value == LockState.Unlocked) {
                runCatching { container.appOpenStore.loadOrCreate() }
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
        val isShowingYouExperience = remember { mutableStateOf(false) }
        val showsOnboarding = remember(settings.onboardingCompleted) { mutableStateOf(!settings.onboardingCompleted) }
        val importedCompletedHash = remember { mutableStateOf<String?>(null) }
        val pendingPostWriteRevealHash = remember { mutableStateOf<String?>(null) }
        val handledPostWriteHashes = remember { mutableSetOf<String>() }
        val postWriteCompletedHash = importedCompletedHash.value ?: writeState.completedHash
        val shouldShowOnboarding =
            showsOnboarding.value &&
                lockState.value == LockState.Unlocked &&
                (currentRoute == AnkyRoute.Write.route || currentRoute == null) &&
                !isShowingYouExperience.value

        fun openPostWriteReveal(hash: String) {
            if (!handledPostWriteHashes.add(hash)) return
            importedCompletedHash.value = null
            writeViewModelWithCurrentMirror.consumeCompletedHash()
            showsOnboarding.value = false
            mapViewModel.refresh()
            container.encryptedBackupStore.backUpIfEnabled()
            pendingPostWriteRevealHash.value = hash
            navController.navigate(AnkyRoute.Map.route) {
                launchSingleTop = true
                popUpTo(AnkyRoute.Write.route)
            }
        }

        LaunchedEffect(
            settings.deviceLockPromptCompleted,
            settings.appLockEnabled,
            lockState.value,
            shouldShowOnboarding,
            postWriteCompletedHash,
        ) {
            if (
                !settings.deviceLockPromptCompleted &&
                !settings.appLockEnabled &&
                lockState.value == LockState.Unlocked &&
                !shouldShowOnboarding &&
                canUseDeviceLock(context) &&
                container.sessionIndexStore.load().any { it.isComplete }
            ) {
                showsDeviceLockActivationPrompt.value = true
            }
        }

        LaunchedEffect(writeState.acceptedGlyphCount) {
            if (writeState.acceptedGlyphCount > 0) {
                showsOnboarding.value = false
            }
        }
        LaunchedEffect(postWriteCompletedHash) {
            val hash = postWriteCompletedHash
            if (hash != null) {
                openPostWriteReveal(hash)
            }
        }
        LaunchedEffect(writeViewModelWithCurrentMirror) {
            writeViewModelWithCurrentMirror.state
                .mapNotNull { it.completedHash }
                .distinctUntilChanged()
                .collect { hash -> openPostWriteReveal(hash) }
        }
        LaunchedEffect(currentRoute) {
            isShowingYouExperience.value = false
        }
        LaunchedEffect(currentRoute, pendingPostWriteRevealHash.value) {
            val hash = pendingPostWriteRevealHash.value ?: return@LaunchedEffect
            if (currentRoute == AnkyRoute.Map.route) {
                pendingPostWriteRevealHash.value = null
                navController.navigate(AnkyRoute.Reveal.route(hash)) {
                    launchSingleTop = true
                }
            }
        }

        fun beginRetryWriting() {
            importedCompletedHash.value = null
            writeViewModelWithCurrentMirror.consumeCompletedHash()
            writeViewModelWithCurrentMirror.clearCompletedSession()
            navController.navigate(AnkyRoute.Write.route) {
                launchSingleTop = true
                popUpTo(AnkyRoute.Write.route) { inclusive = false }
            }
            writeViewModelWithCurrentMirror.openWritingPortal()
        }

        fun beginContinuingWriting(artifact: SavedAnky) {
            importedCompletedHash.value = null
            writeViewModelWithCurrentMirror.consumeCompletedHash()
            if (!writeViewModelWithCurrentMirror.continueSession(artifact)) {
                beginRetryWriting()
                return
            }
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
                        !isShowingYouExperience.value &&
                        !shouldShowOnboarding
                    ) {
                        NavigationBar(
                            containerColor = AnkyColors.Ink.copy(alpha = 0.96f),
                            contentColor = AnkyColors.Paper,
                        ) {
                            tabs.forEach { tab ->
                                val tabLabel = stringResource(tab.labelRes)
                                NavigationBarItem(
                                    selected = tab.isSelectedForRoute(currentRoute),
                                    onClick = {
                                        navController.navigate(tab.route) {
                                            launchSingleTop = true
                                            popUpTo(AnkyRoute.Write.route)
                                        }
                                    },
                                    label = { Text(tabLabel) },
                                    icon = {
                                        Icon(
                                            imageVector = tab.icon(),
                                            contentDescription = tabLabel,
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
                            },
                            onCompleted = { hash -> openPostWriteReveal(hash) },
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
                            inputEnabled = !shouldShowOnboarding,
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
                            )
                        }
                        YouScreen(
                            viewModel = viewModel,
                            onOpenReveal = { hash -> navController.navigate(AnkyRoute.Reveal.route(hash)) },
                            onWriteRequested = { beginRetryWriting() },
                            onAccountDeleted = {
                                writeViewModelWithCurrentMirror.resetAfterAccountDeletion()
                                mapViewModel.refresh()
                            },
                            onAppLockChange = { enabled ->
                                rootScope.launch {
                                    if (enabled) {
                                        val confirmed = biometricGate.authenticate(protectDeviceLockReason)
                                        container.settingsStore.setDeviceLockPromptCompleted(true)
                                        if (confirmed) {
                                            skipNextAppLockAuthentication.value = true
                                            container.settingsStore.setAppLockEnabled(true)
                                        }
                                    } else {
                                        container.settingsStore.setAppLockEnabled(false)
                                    }
                                }
                            },
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
                            )
                        }
                        YouScreen(
                            viewModel = viewModel,
                            initialPage = YouInitialPage.Credits,
                            onInitialPageBack = { navController.popBackStack() },
                            onOpenReveal = { hash -> navController.navigate(AnkyRoute.Reveal.route(hash)) },
                            onWriteRequested = { beginRetryWriting() },
                            onAccountDeleted = {
                                writeViewModelWithCurrentMirror.resetAfterAccountDeletion()
                                mapViewModel.refresh()
                            },
                            onAppLockChange = { enabled ->
                                rootScope.launch {
                                    if (enabled) {
                                        val confirmed = biometricGate.authenticate(protectDeviceLockReason)
                                        container.settingsStore.setDeviceLockPromptCompleted(true)
                                        if (confirmed) {
                                            skipNextAppLockAuthentication.value = true
                                            container.settingsStore.setAppLockEnabled(true)
                                        }
                                    } else {
                                        container.settingsStore.setAppLockEnabled(false)
                                    }
                                }
                            },
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
                                reflectionCreditCache = container.reflectionCreditCache,
                                hasClaimedFreeCreditsProvider = {
                                    runCatching {
                                        container.reflectionCreditCache.hasClaimedFreeCredits(container.identityStore.loadOrCreate().accountId)
                                    }.getOrDefault(false)
                                },
                                markFreeCreditsClaimed = {
                                    runCatching {
                                        container.reflectionCreditCache.markFreeCreditsClaimed(container.identityStore.loadOrCreate().accountId)
                                    }
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
                            onTryAgain = { artifact -> beginContinuingWriting(artifact) },
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
            if (!isShowingYouExperience.value && !shouldShowOnboarding) {
                AnkyPresenceOverlay(
                    defaultSequence = presenceSequence(currentRoute, writeState.hasReachedRitualMark),
                    goldenGlow = currentRoute == AnkyRoute.Write.route && writeState.hasReachedRitualMark,
                    transformToSigil = currentRoute == AnkyRoute.Write.route && writeState.acceptedGlyphCount > 0 && !writeState.hasReachedRitualMark,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            if (
                shouldShowOnboarding
            ) {
                AnkyOnboardingScreen(
                    startWriting = {
                        showsOnboarding.value = false
                        rootScope.launch {
                            container.settingsStore.setOnboardingCompleted(true)
                        }
                        navController.navigate(AnkyRoute.Write.route) {
                            launchSingleTop = true
                            popUpTo(AnkyRoute.Write.route) { inclusive = false }
                        }
                        writeViewModelWithCurrentMirror.openWritingPortal()
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            } else if (
                currentRoute == AnkyRoute.Write.route &&
                writeState.errorMessage != null
            ) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
                    AnkyConversationPrompt(
                        message = writeState.errorMessage.orEmpty(),
                        onClose = writeViewModelWithCurrentMirror::dismissCurrentPrompt,
                        modifier = Modifier
                            .padding(start = 18.dp, end = 18.dp, bottom = 96.dp),
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
                            .padding(start = 18.dp, end = 18.dp, bottom = 96.dp),
                    )
                }
            }

            if (showsDeviceLockActivationPrompt.value && !shouldShowOnboarding && !isShowingYouExperience.value) {
                val deviceLockTitle = stringResource(R.string.activate_device_lock)
                val deviceLockReason = stringResource(R.string.protect_device_lock_reason)
                AlertDialog(
                    onDismissRequest = {
                        showsDeviceLockActivationPrompt.value = false
                        rootScope.launch {
                            container.settingsStore.setDeviceLockPromptCompleted(true)
                        }
                    },
                    title = { Text(deviceLockTitle) },
                    text = {
                        Text(stringResource(R.string.device_lock_prompt))
                    },
                    confirmButton = {
                        TextButton(
                            onClick = {
                                showsDeviceLockActivationPrompt.value = false
                                rootScope.launch {
                                    val confirmed = biometricGate.authenticate(deviceLockReason)
                                    container.settingsStore.setDeviceLockPromptCompleted(true)
                                    if (confirmed) {
                                        skipNextAppLockAuthentication.value = true
                                        container.settingsStore.setAppLockEnabled(true)
                                    }
                                }
                            },
                        ) {
                            Text(deviceLockTitle)
                        }
                    },
                    dismissButton = {
                        TextButton(
                            onClick = {
                                showsDeviceLockActivationPrompt.value = false
                                rootScope.launch {
                                    container.settingsStore.setDeviceLockPromptCompleted(true)
                                }
                            },
                        ) {
                            Text(stringResource(R.string.not_now))
                        }
                    },
                )
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

private fun presenceSequence(route: String?, writeRitualComplete: Boolean): AnkySequenceName =
    when (route) {
        AnkyRoute.Write.route, null -> if (writeRitualComplete) AnkySequenceName.Celebrate else AnkySequenceName.FindingThread
        AnkyRoute.Map.route -> AnkySequenceName.WalkRight
        AnkyRoute.You.route, AnkyRoute.YouCredits.route -> AnkySequenceName.WaveFront
        else -> AnkySequenceName.IdleFront
    }

private fun canUseDeviceLock(context: Context): Boolean =
    BiometricManager.from(context).canAuthenticate(
        BiometricManager.Authenticators.BIOMETRIC_WEAK or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL,
    ) == BiometricManager.BIOMETRIC_SUCCESS

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
