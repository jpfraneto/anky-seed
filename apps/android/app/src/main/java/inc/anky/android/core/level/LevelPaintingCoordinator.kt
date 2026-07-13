package inc.anky.android.core.level

import inc.anky.android.core.identity.WriterIdentity
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The client half of the painting state machine:
 * accumulating → generationPending → generated → ceremonyPending → ceremonyShown.
 *
 * Local state (LevelProgressStore) is the source of truth for what the UI
 * does next; the server ledger mirrors it and is the recovery source after
 * reinstall. Every transition here is persisted synchronously before the
 * UI is allowed to move — the ceremony survives app kill by construction.
 */
class LevelPaintingCoordinator(
    private val progressStore: LevelProgressStore,
    private val assetStore: PaintingAssetStore,
    private val syncClient: LevelSyncing,
    private val funnel: AnkyFunnel,
    private val identityProvider: suspend () -> WriterIdentity?,
    private val sessionStats: suspend () -> List<LevelSessionStat>,
    private val chapterArtifacts: suspend () -> List<LevelChapterArtifact>,
    private val scope: CoroutineScope,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val ceremonyPollDelayMs: Long = 3_000,
    private val ceremonyPollAttempts: Int = 40, // up to ~2 minutes of quiet breathing
) {
    /** The level whose unveiling should play at the next unhurried moment. */
    private val _owedCeremonyLevel = MutableStateFlow<Int?>(null)
    val owedCeremonyLevel: StateFlow<Int?> = _owedCeremonyLevel.asStateFlow()

    /** True once the owed ceremony's package is cached and ready to bloom. */
    private val _owedCeremonyAssetsReady = MutableStateFlow(false)
    val owedCeremonyAssetsReady: StateFlow<Boolean> = _owedCeremonyAssetsReady.asStateFlow()

    private val isPreparing = AtomicBoolean(false)
    private val isRefreshing = AtomicBoolean(false)

    /**
     * Phase-3: whether the writer is entitled. Kept fresh by the app root
     * from the entitlement store. Defaults to false so the client fails
     * closed the same way the server does — generation beyond the free
     * boundary never fires without a subscription, it just waits behind
     * the veil.
     */
    @Volatile
    var entitledForGating: Boolean = false

    init {
        refreshOwedCeremony()
    }

    // MARK: Signals from the app

    /**
     * After every sealed session: re-evaluate the pre-generation trigger
     * and whether a ceremony is now owed.
     */
    fun handleSealCompleted() {
        refreshOwedCeremony()
        scope.launch { withContext(ioDispatcher) { evaluatePreparationTrigger() } }
    }

    /**
     * On app foreground / launch: reconcile with the server ledger and
     * prefetch any generated package.
     */
    fun refreshOnForeground() {
        refreshOwedCeremony()
        if (!isRefreshing.compareAndSet(false, true)) return
        scope.launch {
            try {
                withContext(ioDispatcher) {
                    LevelSyncClient.flushUnreported(
                        store = progressStore,
                        identity = loadIdentity(),
                        client = syncClient,
                    )
                    reconcileWithServer()
                    downloadOwedPackageIfNeeded()
                }
                refreshOwedCeremony()
                withContext(ioDispatcher) { evaluatePreparationTrigger() }
            } finally {
                isRefreshing.set(false)
            }
        }
    }

    /**
     * The ceremony may only fire in an unhurried context: a Daily Unlock
     * session end, or a normal app open — never mid-Quick-Pass.
     *
     * Phase-3 boundary: past the one free ceremony, an unentitled writer's
     * next unveiling holds — unless its painting was already generated
     * (lapse grace: a delivered painting always gets its ceremony).
     */
    fun presentableCeremonyLevel(unhurried: Boolean): Int? {
        if (!unhurried) return null
        val owed = _owedCeremonyLevel.value ?: return null
        if (owed > LevelProgressStore.FreeBoundaryLevel &&
            !entitledForGating &&
            assetStore.installedPackage(owed) == null
        ) {
            return null
        }
        return owed
    }

    /**
     * After a purchase or restore is confirmed server-side: the held
     * generation may fire now. pay → server-confirmed → generate → ceremony;
     * the ceremony's waiting poll covers the synchronous path.
     */
    fun handleEntitlementConfirmed() {
        refreshOwedCeremony()
        scope.launch { withContext(ioDispatcher) { evaluatePreparationTrigger() } }
    }

    /** Closes the unveiling: local first (kill-safe), then the ledger. */
    fun markCeremonyShown(level: Int) {
        progressStore.markCeremonyShown(level)
        refreshOwedCeremony()
        if (level == LevelProgressStore.FreeBoundaryLevel) {
            funnel.report(AnkyFunnel.CeremonyOneShown)
        }
        scope.launch {
            val identity = loadIdentity() ?: return@launch
            runCatching { syncClient.reportCeremonyShown(level, identity) }
        }
    }

    /**
     * Packages for the ceremony's two paintings. The completed one is the
     * painting of the level just closed; the glimpse is the next level's.
     */
    fun ceremonyPackages(level: Int): Pair<PaintingPackage?, PaintingPackage?> {
        val completed = assetStore.installedPackage(level - 1)
            ?: assetStore.installedLevels().lastOrNull { it < level }?.let { assetStore.installedPackage(it) }
        return completed to assetStore.installedPackage(level)
    }

    suspend fun paintingGenerationExcerpts(limit: Int = 4): List<String> =
        LevelTriggerTuning.loadingExcerpts(
            artifacts = chapterArtifacts(),
            sinceMs = progressStore.lastLevelUpAtMs,
            limit = limit,
        )

    // MARK: Machine internals

    private fun refreshOwedCeremony() {
        val owed = progressStore.owedCeremonyLevel
        _owedCeremonyLevel.value = owed
        _owedCeremonyAssetsReady.value = owed?.let { assetStore.installedPackage(it) != null } ?: false
        if (progressStore.claimBoundaryReport(entitled = entitledForGating)) {
            funnel.report(AnkyFunnel.BoundaryReached)
        }
    }

    /**
     * §3.2 trigger: prepare the next level's painting when the writer is
     * within one strong day of crossing (or at 90% without history).
     */
    private suspend fun evaluatePreparationTrigger() {
        val progress = progressStore.progress
        val nextLevel = progress.level + 1

        // Also cover an owed level whose painting was never generated
        // (the writer outran pre-generation).
        val targetLevel = progressStore.owedCeremonyLevel ?: nextLevel
        if (assetStore.installedPackage(targetLevel) != null) {
            return
        }
        // Phase-3 boundary: generation costs real money. Beyond the one free
        // ceremony's painting, nothing is spent — client-side here, and
        // enforced again server-side on /level/prepare.
        if (targetLevel > LevelProgressStore.FreeBoundaryLevel && !entitledForGating) {
            return
        }
        if (progressStore.phase(targetLevel) != LevelPaintingPhase.Accumulating) {
            return
        }

        val owed = progressStore.owedCeremonyLevel != null
        if (!owed) {
            val history = LevelTriggerTuning.dailySecondsHistory(sessionStats())
            if (!LevelTriggerTuning.shouldPrepareNextPainting(progress, history)) {
                return
            }
        }
        startPreparation(targetLevel)
    }

    private suspend fun startPreparation(level: Int) {
        if (!isPreparing.compareAndSet(false, true)) return
        try {
            val text = LevelTriggerTuning.distillText(
                artifacts = chapterArtifacts(),
                sinceMs = progressStore.lastLevelUpAtMs,
            )
            if (text.length < 80) {
                return // not enough writing in the chapter yet
            }
            progressStore.setPhase(LevelPaintingPhase.GenerationPending, level)
            val identity = loadIdentity()
            if (identity == null) {
                progressStore.setPhase(LevelPaintingPhase.Accumulating, level)
                return
            }
            runCatching { syncClient.prepare(level, text, identity) }
                .onFailure { progressStore.setPhase(LevelPaintingPhase.Accumulating, level) }
            // Generation runs server-side; the package lands on a later
            // refresh (or the ceremony's waiting poll).
            downloadOwedPackageIfNeeded()
            refreshOwedCeremony()
        } finally {
            isPreparing.set(false)
        }
    }

    private suspend fun reconcileWithServer() {
        val identity = loadIdentity() ?: return
        val status = runCatching { syncClient.fetchStatus(identity) }.getOrNull() ?: return
        progressStore.adoptServerTotalIfHigher(status.totalSeconds)
        if (status.nextPaintingPhase == LevelPaintingPhase.Generated ||
            status.nextPaintingPhase == LevelPaintingPhase.CeremonyPending
        ) {
            progressStore.setPhase(status.nextPaintingPhase, status.nextLevel)
        }
        status.pendingCeremonyLevel?.let { pending ->
            progressStore.setPhase(LevelPaintingPhase.CeremonyPending, pending)
        }
    }

    /**
     * Prefetch: as soon as a package exists server-side, cache it forever.
     * Tries the owed level first, then the next level's pre-generation.
     */
    private suspend fun downloadOwedPackageIfNeeded() {
        val progress = progressStore.progress
        val candidates = buildList {
            progressStore.owedCeremonyLevel?.let { add(it) }
            add(progress.level + 1)
        }
        for (level in candidates) {
            if (assetStore.installedPackage(level) != null) continue
            val phase = progressStore.phase(level)
            if (phase != LevelPaintingPhase.Generated &&
                phase != LevelPaintingPhase.CeremonyPending &&
                phase != LevelPaintingPhase.GenerationPending
            ) {
                continue
            }
            val identity = loadIdentity() ?: continue
            val installed = runCatching { assetStore.downloadPackage(level, syncClient, identity) }.getOrNull()
            if (installed != null) {
                progressStore.setPhase(
                    if (progressStore.owedCeremonyLevel == level) {
                        LevelPaintingPhase.CeremonyPending
                    } else {
                        LevelPaintingPhase.Generated
                    },
                    level,
                )
            }
        }
    }

    /**
     * The ceremony's waiting poll: the writer outran generation, the
     * darkness breathes while anky paints. Checks every few seconds.
     */
    suspend fun waitForCeremonyPackage(level: Int): PaintingPackage? {
        repeat(ceremonyPollAttempts) {
            assetStore.installedPackage(level)?.let { pkg ->
                _owedCeremonyAssetsReady.value = true
                return pkg
            }
            withContext(ioDispatcher) { downloadOwedPackageIfNeeded() }
            delay(ceremonyPollDelayMs)
        }
        return null
    }

    private suspend fun loadIdentity(): WriterIdentity? =
        runCatching { identityProvider() }.getOrNull()
}
