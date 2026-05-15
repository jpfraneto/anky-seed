package inc.anky.android.app

import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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

@Composable
fun AnkyApp(container: AppContainer) {
    MaterialTheme {
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
        val unlocked = remember { mutableStateOf(false) }
        val unlockAttempt = remember { mutableStateOf(0) }

        if (settings == null) {
            Box(modifier = Modifier.fillMaxSize())
            return@MaterialTheme
        }

        LaunchedEffect(settings.appLockEnabled, unlockAttempt.value) {
            unlocked.value = if (settings.appLockEnabled) {
                biometricGate.authenticate("Unlock Anky")
            } else {
                true
            }
        }

        if (!unlocked.value) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Button(onClick = {
                    unlockAttempt.value += 1
                }) {
                    Text("Unlock Anky")
                }
            }
            return@MaterialTheme
        }

        LaunchedEffect(unlocked.value) {
            if (unlocked.value) {
                val identity = container.identityStore.loadOrCreate()
                container.creditsClient.configure(identity.publicKey)
                container.creditsClient.refresh()
            }
        }

        Scaffold(
            bottomBar = {
                if (currentRoute != AnkyRoute.Reveal.route) {
                    NavigationBar {
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
                                icon = { Text(tab.label.first().toString()) },
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
                    val viewModel = remember {
                        WriteViewModel(
                            activeDraftStore = container.activeDraftStore,
                            archive = container.archive,
                            reflectionStore = container.reflectionStore,
                            indexStore = container.sessionIndexStore,
                        )
                    }
                    WriteScreen(
                        viewModel = viewModel,
                        onReveal = { hash -> navController.navigate(AnkyRoute.Reveal.route(hash)) },
                    )
                }
                composable(AnkyRoute.Map.route) {
                    val viewModel = remember {
                        MapViewModel(
                            archive = container.archive,
                            reflectionStore = container.reflectionStore,
                            indexStore = container.sessionIndexStore,
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
                        )
                    }
                    RevealScreen(viewModel = viewModel, onBack = { navController.popBackStack() })
                }
            }
        }
    }
}

private tailrec fun Context.findFragmentActivity(): FragmentActivity? =
    when (this) {
        is FragmentActivity -> this
        is ContextWrapper -> baseContext.findFragmentActivity()
        else -> null
    }
