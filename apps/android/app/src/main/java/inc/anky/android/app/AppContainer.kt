package inc.anky.android.app

import android.content.Context
import android.graphics.BitmapFactory
import inc.anky.android.core.credits.CreditsClient
import inc.anky.android.core.credits.ReflectionCreditCache
import inc.anky.android.core.credits.RevenueCatCreditsClient
import inc.anky.android.core.credits.SharedPreferencesReflectionCreditCache
import inc.anky.android.core.gate.WritingAnchorStore
import inc.anky.android.core.gate.runtime.GateRuntime
import inc.anky.android.core.gate.runtime.UsageAccess
import inc.anky.android.core.level.AnkyFunnel
import inc.anky.android.core.level.LevelChapterArtifact
import inc.anky.android.core.level.LevelPaintingCoordinator
import inc.anky.android.core.level.LevelProgressStore
import inc.anky.android.core.level.LevelSessionStat
import inc.anky.android.core.identity.WriterIdentityStore
import inc.anky.android.core.level.LevelSyncClient
import inc.anky.android.core.level.PaintingAssetStore
import inc.anky.android.core.level.journey.JourneyCelebrationLedger
import inc.anky.android.core.level.journey.JourneySessionInput
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorConfiguration
import inc.anky.android.core.notifications.DailyReminderScheduler
import inc.anky.android.core.storage.ActiveDraftStore
import inc.anky.android.core.storage.AndroidEncryptedBackupStore
import inc.anky.android.core.storage.AppOpenStore
import inc.anky.android.core.storage.BackupImporter
import inc.anky.android.core.storage.Exporter
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.ReflectionRequestStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.AvatarStore
import inc.anky.android.core.subscription.EntitlementStore
import inc.anky.android.core.subscription.RevenueCatSubscriptionGateway
import inc.anky.android.core.subscription.SubscriptionBackend
import inc.anky.android.feature.painting.PaintingHomeDependencies
import inc.anky.android.feature.painting.PaintingHomeSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class AppContainer(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    val identityStore = WriterIdentityStore(appContext)
    val activeDraftStore = ActiveDraftStore(appContext)
    val archive = LocalAnkyArchive(appContext)
    val reflectionStore = ReflectionStore(appContext)
    val reflectionRequestStore = ReflectionRequestStore(appContext)
    val sessionIndexStore = SessionIndexStore(appContext)
    val appOpenStore = AppOpenStore(appContext)
    val settingsStore = UserSettingsStore(appContext)
    val reminderScheduler = DailyReminderScheduler(appContext)
    val gateRuntime = GateRuntime(appContext)
    val avatarStore = AvatarStore(appContext)
    val writingAnchorStore = WritingAnchorStore(gateRuntime.preferences)
    val levelProgressStore = LevelProgressStore(appContext)
    val paintingAssetStore = PaintingAssetStore(appContext)
    val levelSyncClient = LevelSyncClient(MirrorConfiguration().baseUrl)
    val ankyFunnel = AnkyFunnel(
        client = levelSyncClient,
        identityProvider = { runCatching { identityStore.loadOrCreate() }.getOrNull() },
        scope = appScope,
    )
    val creditsClient: CreditsClient = RevenueCatCreditsClient(appContext)
    val reflectionCreditCache: ReflectionCreditCache = SharedPreferencesReflectionCreditCache(appContext)
    val subscriptionPreferences = appContext.getSharedPreferences("anky-subscription", Context.MODE_PRIVATE)
    val entitlementStore = EntitlementStore(
        gateway = RevenueCatSubscriptionGateway(appContext) {
            runCatching { identityStore.loadOrCreate().accountId }.getOrNull()
        },
        backend = object : SubscriptionBackend {
            override suspend fun identify(appUserId: String): Boolean? =
                runCatching {
                    LevelSyncClient(MirrorConfiguration().baseUrl)
                        .identifySubscription(identityStore.loadOrCreate())
                        .entitled
                }.getOrNull()

            override suspend fun funnel(event: String, origin: String?) {
                runCatching {
                    LevelSyncClient(MirrorConfiguration().baseUrl)
                        .reportFunnelEvent(event, origin, identityStore.loadOrCreate())
                }
            }
        },
        preferences = subscriptionPreferences,
        scope = appScope,
    )
    val levelPaintingCoordinator = LevelPaintingCoordinator(
        progressStore = levelProgressStore,
        assetStore = paintingAssetStore,
        syncClient = levelSyncClient,
        funnel = ankyFunnel,
        identityProvider = { runCatching { identityStore.loadOrCreate() }.getOrNull() },
        sessionStats = { levelSessionStats() },
        chapterArtifacts = { chapterArtifacts() },
        scope = appScope,
    )
    val paintingHomeDependencies = PaintingHomeDependencies(
        levelProgressStore = levelProgressStore,
        paintingAssetStore = paintingAssetStore,
        coordinator = levelPaintingCoordinator,
        entitlementStore = entitlementStore,
        quickPassStore = gateRuntime.quickPassStore,
        gateStateStore = gateRuntime.stateStore,
        unlockStateStore = gateRuntime.unlockStateStore,
        funnel = ankyFunnel,
        celebrationLedger = JourneyCelebrationLedger(gateRuntime.preferences),
        loadAsset = { path -> runCatching { appContext.assets.open(path).use { it.readBytes() } }.getOrNull() },
        filesDir = appContext.filesDir,
        isGateAuthorized = { UsageAccess.hasUsageAccess(appContext) },
        writerName = { writingAnchorStore.writerName },
        avatar = {
            avatarStore.loadData()?.let { bytes ->
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
        },
        recentSessions = {
            sessionIndexStore.load()
                .filter { it.isComplete }
                .take(5)
                .map { summary ->
                    PaintingHomeSession(
                        hash = summary.hash,
                        createdAtMs = summary.createdAt.toEpochMilli(),
                        preview = summary.preview,
                        durationMs = summary.durationMs,
                    )
                }
        },
        journeySessions = {
            sessionIndexStore.load()
                .filter { it.isComplete }
                .map { JourneySessionInput(it.createdAt.toEpochMilli(), it.durationMs) }
        },
        backfillSessionStats = { levelSessionStats() },
    )
    val exporter = Exporter(appContext, archive, reflectionStore)
    val backupImporter = BackupImporter(
        appContext,
        archive,
        reflectionStore,
        sessionIndexStore,
        recordEarlierFirstOpenDate = { appOpenStore.recordEarlierFirstOpenDate(it) },
    )
    val encryptedBackupStore = AndroidEncryptedBackupStore(
        appContext,
        identityStore,
        exporter,
        backupImporter,
    )

    fun mirrorClient(baseUrl: String): MirrorClient =
        MirrorClient(MirrorConfiguration(baseUrl = baseUrl))

    private fun levelSessionStats(): List<LevelSessionStat> =
        sessionIndexStore.load()
            .filter { it.isComplete }
            .map { summary ->
                LevelSessionStat(
                    hash = summary.hash,
                    createdAtMs = summary.createdAt.toEpochMilli(),
                    durationMs = summary.durationMs,
                )
            }

    private fun chapterArtifacts(): List<LevelChapterArtifact> =
        archive.list()
            .filter { it.isComplete }
            .map { artifact ->
                LevelChapterArtifact(
                    createdAtMs = artifact.createdAt.toEpochMilli(),
                    reconstructedText = artifact.reconstructedText,
                )
            }
}
