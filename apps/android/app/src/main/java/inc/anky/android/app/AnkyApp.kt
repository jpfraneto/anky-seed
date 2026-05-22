package inc.anky.android.app

import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
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
import inc.anky.android.core.identity.DeviceBiometricGate
import inc.anky.android.feature.map.MapScreen
import inc.anky.android.feature.map.MapViewModel
import inc.anky.android.feature.reveal.RevealScreen
import inc.anky.android.feature.reveal.RevealViewModel
import inc.anky.android.feature.write.WriteScreen
import inc.anky.android.feature.write.WriteViewModel
import inc.anky.android.feature.you.YouScreen
import inc.anky.android.feature.you.YouViewModel
import inc.anky.android.core.storage.SingleAnkyImporter
import inc.anky.android.ui.components.AnkyPresenceOverlay
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
        val biometricGate = remember(context) {
            DeviceBiometricGate { context.findFragmentActivity() }
        }
        val freeCreditPromptPrefs = remember(context) {
            context.getSharedPreferences("anky-credit-prompt", Context.MODE_PRIVATE)
        }
        val lifecycleOwner = LocalLifecycleOwner.current
        val lockState = remember { mutableStateOf(LockState.Locked) }
        val unlockAttempt = remember { mutableIntStateOf(0) }

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
            lockState.value = if (settings.appLockEnabled) {
                LockState.Authenticating
                if (biometricGate.authenticate("Unlock ANKY.")) {
                    LockState.Unlocked
                } else {
                    LockState.Failed
                }
            } else {
                LockState.Unlocked
            }
        }

        if (settings.appLockEnabled && lockState.value != LockState.Unlocked) {
            Box(
                modifier = Modifier.fillMaxSize().background(Color.White),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    modifier = Modifier.padding(24.dp),
                ) {
                    if (lockState.value == LockState.Locked || lockState.value == LockState.Authenticating) {
                        CircularProgressIndicator(color = Color.Black)
                    } else {
                        Text(
                            "face id didn't work. you should not be here",
                            color = Color.Black,
                            textAlign = TextAlign.Center,
                        )
                        Button(
                            onClick = {
                                unlockAttempt.intValue += 1
                            },
                            shape = RoundedCornerShape(14.dp),
                        ) { Text("Try again") }
                    }
                }
            }
            return@AnkyTheme
        }

        LaunchedEffect(lockState.value) {
            if (lockState.value == LockState.Unlocked) {
                runCatching { container.identityStore.loadOrCreate() }
                runCatching { container.appOpenStore.loadOrCreate() }
            }
        }

        val writeViewModel = remember {
            WriteViewModel(
                activeDraftStore = container.activeDraftStore,
                archive = container.archive,
                reflectionStore = container.reflectionStore,
                indexStore = container.sessionIndexStore,
            )
        }
        val writeState = writeViewModel.state.collectAsStateWithLifecycle().value

        Box(Modifier.fillMaxSize()) {
            Scaffold(
                containerColor = AnkyColors.Background,
                bottomBar = {
                    if (currentRoute != AnkyRoute.Write.route && currentRoute != AnkyRoute.Reveal.route) {
                        NavigationBar(
                            containerColor = AnkyColors.Ink.copy(alpha = 0.96f),
                            contentColor = AnkyColors.Paper,
                        ) {
                            tabs.forEach { tab ->
                                NavigationBarItem(
                                    selected = currentRoute == tab.route,
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
                            viewModel = writeViewModel,
                            onReveal = { hash ->
                                navController.navigate(AnkyRoute.Map.route) {
                                    launchSingleTop = true
                                    popUpTo(AnkyRoute.Write.route)
                                }
                                navController.navigate(AnkyRoute.Reveal.route(hash))
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
                        val viewModel = remember {
                            MapViewModel(
                                archive = container.archive,
                                reflectionStore = container.reflectionStore,
                                indexStore = container.sessionIndexStore,
                                appOpenStore = container.appOpenStore,
                            )
                        }
                        MapScreen(
                            viewModel = viewModel,
                            onOpenReveal = { hash -> navController.navigate(AnkyRoute.Reveal.route(hash)) },
                        )
                    }
                    composable(AnkyRoute.You.route) {
                        val viewModel = remember {
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
                        YouScreen(viewModel)
                    }
                    composable(AnkyRoute.Reveal.route) { entry ->
                        val hash = entry.arguments?.getString("hash").orEmpty()
                        val viewModel = remember(hash, settings.mirrorBaseUrl) {
                            RevealViewModel(
                                hash = hash,
                                archive = container.archive,
                                reflectionStore = container.reflectionStore,
                                indexStore = container.sessionIndexStore,
                                identityStore = container.identityStore,
                                mirrorClientProvider = { container.mirrorClient(settings.mirrorBaseUrl) },
                                hasClaimedFreeCreditsProvider = {
                                    freeCreditPromptPrefs.getBoolean("hasClaimedFreeReflections", false)
                                },
                                markFreeCreditsClaimed = {
                                    freeCreditPromptPrefs.edit().putBoolean("hasClaimedFreeReflections", true).apply()
                                },
                            )
                        }
                        RevealScreen(viewModel = viewModel, onBack = { navController.popBackStack() })
                    }
                }
            }
            AnkyPresenceOverlay(
                defaultSequence = presenceSequence(currentRoute, writeState.hasReachedRitualMark),
                goldenGlow = currentRoute == AnkyRoute.Write.route && writeState.hasReachedRitualMark,
                transformToSigil = currentRoute == AnkyRoute.Write.route && writeState.acceptedGlyphCount > 0 && !writeState.hasReachedRitualMark,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

private enum class LockState {
    Locked,
    Authenticating,
    Unlocked,
    Failed,
}

private fun presenceSequence(route: String?, writeRitualComplete: Boolean): AnkySequenceName =
    when (route) {
        AnkyRoute.Write.route, null -> if (writeRitualComplete) AnkySequenceName.Celebrate else AnkySequenceName.FindingThread
        AnkyRoute.Map.route -> AnkySequenceName.WalkRight
        AnkyRoute.You.route -> AnkySequenceName.WaveFront
        else -> AnkySequenceName.IdleFront
    }

private fun AnkyRoute.icon() =
    when (this) {
        AnkyRoute.Write -> Icons.Outlined.Edit
        AnkyRoute.Map -> Icons.Outlined.Map
        AnkyRoute.You -> Icons.Outlined.AccountCircle
        AnkyRoute.Reveal -> Icons.Outlined.Edit
    }

private tailrec fun Context.findFragmentActivity(): FragmentActivity? =
    when (this) {
        is FragmentActivity -> this
        is ContextWrapper -> baseContext.findFragmentActivity()
        else -> null
    }
