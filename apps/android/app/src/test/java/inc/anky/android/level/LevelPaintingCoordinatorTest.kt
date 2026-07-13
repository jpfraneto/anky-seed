package inc.anky.android.level

import inc.anky.android.core.identity.RecoveryPhrase
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.level.AnkyFunnel
import inc.anky.android.core.level.LevelChapterArtifact
import inc.anky.android.core.level.LevelPaintingCoordinator
import inc.anky.android.core.level.LevelPaintingPhase
import inc.anky.android.core.level.LevelProgressStore
import inc.anky.android.core.level.LevelServerStatus
import inc.anky.android.core.level.LevelSessionStat
import inc.anky.android.core.level.LevelSyncing
import inc.anky.android.core.level.LevelUnreportedSession
import inc.anky.android.core.level.PaintingAssetStore
import inc.anky.android.core.level.SubscriptionServerState
import java.io.File
import java.util.UUID
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeLevelSync : LevelSyncing {
    val preparedLevels = mutableListOf<Pair<Int, String>>()
    val ceremonyShownLevels = mutableListOf<Int>()
    val funnelEvents = mutableListOf<String>()
    val reportedBatches = mutableListOf<List<LevelUnreportedSession>>()
    var status: LevelServerStatus? = null
    var assetsAvailableForLevel: Int? = null

    override suspend fun reportSessions(
        sessions: List<LevelUnreportedSession>,
        identity: WriterIdentity,
    ): LevelServerStatus {
        reportedBatches.add(sessions)
        return status ?: throw IllegalStateException("no status")
    }

    override suspend fun fetchStatus(identity: WriterIdentity): LevelServerStatus =
        status ?: throw IllegalStateException("no status")

    override suspend fun prepare(level: Int, text: String, identity: WriterIdentity): String {
        preparedLevels.add(level to text)
        return "generationPending"
    }

    override suspend fun reportCeremonyShown(level: Int, identity: WriterIdentity) {
        ceremonyShownLevels.add(level)
    }

    override suspend fun fetchAsset(level: Int, file: String, identity: WriterIdentity): ByteArray {
        if (assetsAvailableForLevel != level) throw IllegalStateException("no asset")
        return if (file == "meta.json") {
            """{"title":"T","palette":["#000000"],"level":$level,"thresholdSeconds":0}"""
                .toByteArray(Charsets.UTF_8)
        } else {
            byteArrayOf(0x1)
        }
    }

    override suspend fun reportEmergencyUnlock(identity: WriterIdentity) = Unit

    override suspend fun identifySubscription(identity: WriterIdentity): SubscriptionServerState =
        SubscriptionServerState(false, null, null, null, null)

    override suspend fun reportFunnelEvent(event: String, origin: String?, identity: WriterIdentity) {
        funnelEvents.add(event)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class LevelPaintingCoordinatorTest {
    private val identity = WriterIdentity.fromRecoveryPhrase(
        RecoveryPhrase.parse(
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
        ),
    )

    private fun tempDir(): File =
        File(System.getProperty("java.io.tmpdir"), "anky-coord-${UUID.randomUUID()}").also { it.mkdirs() }

    private fun hash(seed: Int): String = "0".repeat(64 - seed.toString().length) + seed.toString()

    private val longChapter = listOf(
        LevelChapterArtifact(
            createdAtMs = System.currentTimeMillis(),
            reconstructedText = "chapter ".repeat(30), // ≥ 80 characters
        ),
    )

    private fun installFake(assetStore: PaintingAssetStore, level: Int) {
        assetStore.install(
            level = level,
            finalPng = byteArrayOf(0x1),
            underdrawingPng = byteArrayOf(0x1),
            revealMapPng = byteArrayOf(0x1),
            metaJson = """{"title":"T","palette":["#000000"],"level":$level,"thresholdSeconds":0}"""
                .toByteArray(Charsets.UTF_8),
        )
    }

    @Test
    fun owedCeremonySurvivesRestartAndClosesOnce() = runTest {
        val dir = tempDir()
        val store = LevelProgressStore(File(dir, "level-progress.json"))
        store.creditSealedSession(hash = hash(1), durationMs = 480_000)
        val sync = FakeLevelSync()
        val assetStore = PaintingAssetStore(File(dir, "Paintings"))

        val coordinator = makeCoordinator(store, assetStore, sync)
        advanceUntilIdle()
        // Kill-safe replay: owed level derived purely from persisted state.
        assertEquals(2, coordinator.owedCeremonyLevel.value)
        assertEquals(2, coordinator.presentableCeremonyLevel(unhurried = true))
        assertNull(coordinator.presentableCeremonyLevel(unhurried = false))

        coordinator.markCeremonyShown(2)
        advanceUntilIdle()
        assertNull(coordinator.owedCeremonyLevel.value)
        assertEquals(listOf(2), sync.ceremonyShownLevels)
        assertTrue(AnkyFunnel.CeremonyOneShown in sync.funnelEvents)

        // A fresh coordinator over the same files owes nothing.
        val rebooted = makeCoordinator(store, assetStore, sync)
        advanceUntilIdle()
        assertNull(rebooted.owedCeremonyLevel.value)
    }

    @Test
    fun boundaryHoldsUnentitledCeremonyUnlessPaintingWasDelivered() = runTest {
        val dir = tempDir()
        val store = LevelProgressStore(File(dir, "level-progress.json"))
        store.creditSealedSession(hash = hash(2), durationMs = 480_000)
        store.creditSealedSession(hash = hash(3), durationMs = 800_000) // real level 3
        store.markCeremonyShown(2)
        val sync = FakeLevelSync()
        val assetStore = PaintingAssetStore(File(dir, "Paintings"))

        val coordinator = makeCoordinator(store, assetStore, sync)
        advanceUntilIdle()
        assertEquals(3, coordinator.owedCeremonyLevel.value)
        // Free writer past the boundary: level 3's unveiling holds.
        assertNull(coordinator.presentableCeremonyLevel(unhurried = true))
        // boundary_reached fires exactly once.
        assertEquals(listOf(AnkyFunnel.BoundaryReached), sync.funnelEvents)

        // Lapse grace: a delivered painting always gets its ceremony.
        installFake(assetStore, 3)
        assertEquals(3, coordinator.presentableCeremonyLevel(unhurried = true))

        coordinator.entitledForGating = true
        assertEquals(3, coordinator.presentableCeremonyLevel(unhurried = true))
    }

    @Test
    fun sealTriggersPreparationOnlyPastTheFallbackFraction() = runTest {
        val dir = tempDir()
        val store = LevelProgressStore(File(dir, "level-progress.json"))
        val sync = FakeLevelSync()
        val assetStore = PaintingAssetStore(File(dir, "Paintings"))
        val coordinator = makeCoordinator(store, assetStore, sync)

        store.creditSealedSession(hash = hash(4), durationMs = 100_000)
        coordinator.handleSealCompleted()
        advanceUntilIdle()
        assertTrue(sync.preparedLevels.isEmpty()) // 100/480 — far from the trigger

        store.creditSealedSession(hash = hash(5), durationMs = 350_000) // 450/480 ≈ 94%
        coordinator.handleSealCompleted()
        advanceUntilIdle()
        assertEquals(1, sync.preparedLevels.size)
        assertEquals(2, sync.preparedLevels.first().first)
        assertEquals(LevelPaintingPhase.GenerationPending, store.phase(2))
    }

    @Test
    fun unentitledWritersNeverPrepareBeyondTheFreeBoundary() = runTest {
        val dir = tempDir()
        val store = LevelProgressStore(File(dir, "level-progress.json"))
        store.creditSealedSession(hash = hash(6), durationMs = 480_000)
        store.creditSealedSession(hash = hash(7), durationMs = 800_000) // owed level 2 shown, real 3
        store.markCeremonyShown(2, atMs = 1_000) // chapter boundary before the test corpus
        val sync = FakeLevelSync()
        val assetStore = PaintingAssetStore(File(dir, "Paintings"))
        val coordinator = makeCoordinator(store, assetStore, sync)

        coordinator.handleSealCompleted()
        advanceUntilIdle()
        assertTrue(sync.preparedLevels.isEmpty())

        coordinator.entitledForGating = true
        coordinator.handleEntitlementConfirmed()
        advanceUntilIdle()
        assertEquals(listOf(3), sync.preparedLevels.map { it.first })
    }

    @Test
    fun foregroundRefreshFlushesReconcilesAndDownloads() = runTest {
        val dir = tempDir()
        val store = LevelProgressStore(File(dir, "level-progress.json"))
        store.creditSealedSession(hash = hash(8), durationMs = 480_000) // owed level 2
        val sync = FakeLevelSync()
        sync.assetsAvailableForLevel = 2
        sync.status = LevelServerStatus(
            totalSeconds = 700,
            level = 2,
            secondsIntoLevel = 220,
            secondsRequired = 778,
            percent = 0.28,
            nextLevel = 2,
            nextPaintingPhase = LevelPaintingPhase.Generated,
            nextPaintingTitle = null,
            nextPalette = null,
            pendingCeremonyLevel = 2,
        )
        val assetStore = PaintingAssetStore(File(dir, "Paintings"))
        val coordinator = makeCoordinator(store, assetStore, sync)

        coordinator.refreshOnForeground()
        advanceUntilIdle()

        assertEquals(1, sync.reportedBatches.size) // queue flushed
        assertTrue(store.unreportedSessions().isEmpty())
        assertEquals(700L, store.progress.totalSeconds) // server total adopted
        assertNotNull(assetStore.installedPackage(2)) // owed package downloaded
        assertEquals(LevelPaintingPhase.CeremonyPending, store.phase(2))
        assertTrue(coordinator.owedCeremonyAssetsReady.value)
    }

    @Test
    fun waitForCeremonyPackagePollsUntilTheAssetLands() = runTest {
        val dir = tempDir()
        val store = LevelProgressStore(File(dir, "level-progress.json"))
        store.creditSealedSession(hash = hash(9), durationMs = 480_000)
        store.setPhase(LevelPaintingPhase.GenerationPending, 2)
        val sync = FakeLevelSync()
        val assetStore = PaintingAssetStore(File(dir, "Paintings"))
        val coordinator = makeCoordinator(store, assetStore, sync)

        sync.assetsAvailableForLevel = 2
        val pkg = coordinator.waitForCeremonyPackage(2)
        assertNotNull(pkg)
        assertEquals(2, pkg?.level)
        assertTrue(coordinator.owedCeremonyAssetsReady.value)
    }

    @Test
    fun waitForCeremonyPackageGivesUpAfterTheBudget() = runTest {
        val dir = tempDir()
        val store = LevelProgressStore(File(dir, "level-progress.json"))
        val sync = FakeLevelSync()
        val assetStore = PaintingAssetStore(File(dir, "Paintings"))
        val coordinator = makeCoordinator(store, assetStore, sync)

        assertNull(coordinator.waitForCeremonyPackage(2))
    }

    private fun kotlinx.coroutines.test.TestScope.makeCoordinator(
        store: LevelProgressStore,
        assetStore: PaintingAssetStore,
        sync: FakeLevelSync,
        stats: List<LevelSessionStat> = emptyList(),
    ): LevelPaintingCoordinator =
        LevelPaintingCoordinator(
            progressStore = store,
            assetStore = assetStore,
            syncClient = sync,
            funnel = AnkyFunnel(sync, { identity }, this),
            identityProvider = { identity },
            sessionStats = { stats },
            chapterArtifacts = { longChapter },
            scope = this,
            ioDispatcher = kotlinx.coroutines.test.UnconfinedTestDispatcher(testScheduler),
            ceremonyPollDelayMs = 1,
            ceremonyPollAttempts = 3,
        )
}
