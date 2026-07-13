import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

/// The client half of the painting state machine:
/// accumulating → generationPending → generated → ceremonyPending → ceremonyShown.
///
/// Local state (LevelProgressStore) is the source of truth for what the UI
/// does next; the server ledger mirrors it and is the recovery source after
/// reinstall. Every transition here is persisted synchronously before the
/// UI is allowed to move — the ceremony survives app kill by construction.
@MainActor
final class LevelPaintingCoordinator: ObservableObject {
    /// The level whose unveiling should play at the next unhurried moment.
    @Published private(set) var owedCeremonyLevel: Int?
    /// True once the owed ceremony's package is cached and ready to bloom.
    @Published private(set) var owedCeremonyAssetsReady = false
    /// True while a writer-summoned custom painting (level 9+) is generating.
    @Published private(set) var isPaintingRitualInFlight = false

    private let progressStore: LevelProgressStore
    private let assetStore: PaintingAssetStore
    private let sessionIndexStore: SessionIndexStore
    private let archive: LocalAnkyArchive
    private let identityStore: WriterIdentityStore
    private var isPreparing = false
    private var isRefreshing = false

    /// Phase-3: whether the writer is entitled. Kept fresh by AppRoot from
    /// EntitlementStore. Defaults to false so the client fails closed the
    /// same way the server does — generation beyond the free boundary never
    /// fires without a subscription, it just waits behind the veil.
    var entitledForGating = false

    init(
        progressStore: LevelProgressStore = LevelProgressStore(),
        assetStore: PaintingAssetStore = PaintingAssetStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        identityStore: WriterIdentityStore = WriterIdentityStore()
    ) {
        self.progressStore = progressStore
        self.assetStore = assetStore
        self.sessionIndexStore = sessionIndexStore
        self.archive = archive
        self.identityStore = identityStore
        // Adopted writers land at their true level before the first ask.
        progressStore.reconcileCeremonyPointerIfNeeded()
        refreshOwedCeremony()
    }

    // MARK: Signals from the app

    /// After every sealed session: re-evaluate the pre-generation trigger
    /// and whether a ceremony is now owed.
    func handleSealCompleted() {
        refreshOwedCeremony()
        evaluatePreparationTrigger()
    }

    /// On app foreground / launch: reconcile with the server ledger and
    /// prefetch any generated package.
    func refreshOnForeground() {
        refreshOwedCeremony()
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            await LevelSyncClient.flushUnreported(store: progressStore, identityStore: identityStore)
            await reconcileWithServer()
            await downloadOwedPackageIfNeeded()
            refreshOwedCeremony()
            evaluatePreparationTrigger()
        }
    }

    /// The ceremony may only fire in an unhurried context: a Daily Unlock
    /// session end, or a normal app open — never mid-Quick-Pass.
    ///
    /// A custom level (9+) has no ceremony until its painting exists: the
    /// writer summons it through the ritual, and only a delivered canvas is
    /// unveiled. This covers both the free writer at the boundary (never a
    /// package) and the Pro writer who hasn't performed the ritual yet.
    func presentableCeremonyLevel(unhurried: Bool) -> Int? {
        guard unhurried, let owed = owedCeremonyLevel else { return nil }
        if owed > LevelProgressStore.freeBoundaryLevel,
           assetStore.installedPackage(forLevel: owed) == nil {
            return nil
        }
        return owed
    }

    /// The custom level (9+) whose painting the writer may summon right now by
    /// offering their chapter — nil unless entitled, past the static boundary,
    /// with no painting yet and nothing already generating. This is the ritual
    /// that replaces automatic generation past level 8.
    func pendingRitualLevel() -> Int? {
        guard entitledForGating, let owed = owedCeremonyLevel else { return nil }
        guard owed > LevelProgressStore.freeBoundaryLevel else { return nil }
        guard assetStore.installedPackage(forLevel: owed) == nil else { return nil }
        guard progressStore.phase(forLevel: owed) == .accumulating else { return nil }
        return owed
    }

    /// The writer offers their chapter: begin generating the owed custom
    /// painting, then hold the in-flight flag until the canvas lands (at which
    /// point `owedCeremonyAssetsReady` flips and the unveiling can play).
    func beginPaintingRitual() {
        guard !isPaintingRitualInFlight, let level = pendingRitualLevel() else { return }
        isPaintingRitualInFlight = true
        startPreparation(level: level)
        Task {
            _ = await waitForCeremonyPackage(level: level, attempts: 80)
            isPaintingRitualInFlight = false
            refreshOwedCeremony()
        }
    }

    /// After a purchase or restore is confirmed server-side: the held
    /// generation may fire now. pay → server-confirmed → generate → ceremony;
    /// the ceremony's waiting poll covers the synchronous path.
    func handleEntitlementConfirmed() {
        refreshOwedCeremony()
        evaluatePreparationTrigger()
    }

    /// Closes the unveiling: local first (kill-safe), then the ledger.
    func markCeremonyShown(_ level: Int) {
        progressStore.markCeremonyShown(level: level)
        refreshOwedCeremony()
        if level == LevelProgressStore.freeBoundaryLevel {
            AnkyFunnel.report(AnkyFunnel.ceremonyOneShown)
        }
        Task.detached(priority: .utility) { [identityStore] in
            guard let identity = try? identityStore.loadOrCreate() else { return }
            try? await LevelSyncClient().reportCeremonyShown(level: level, identity: identity)
        }
    }

    /// Packages for the ceremony's two paintings. The completed one is the
    /// painting of the level just closed; the glimpse is the next level's.
    func ceremonyPackages(forLevel level: Int) -> (completed: PaintingPackage?, glimpse: PaintingPackage?) {
        let completedPackage = assetStore.installedPackage(forLevel: level - 1)
            ?? assetStore.installedLevels().filter { $0 < level }.last.flatMap {
                assetStore.installedPackage(forLevel: $0)
            }
        return (completedPackage, assetStore.installedPackage(forLevel: level))
    }

    func paintingGenerationExcerpts(limit: Int = 4) -> [String] {
        LevelTriggerTuning.loadingExcerpts(
            artifacts: archive.list(),
            sinceMs: progressStore.lastLevelUpAtMs,
            limit: limit
        )
    }

    // MARK: Machine internals

    private func refreshOwedCeremony() {
        let owed = progressStore.owedCeremonyLevel
        owedCeremonyLevel = owed
        owedCeremonyAssetsReady = owed.map { assetStore.installedPackage(forLevel: $0) != nil } ?? false
        if progressStore.claimBoundaryReport(entitled: entitledForGating) {
            AnkyFunnel.report(AnkyFunnel.boundaryReached)
        }
    }

    /// §3.2 trigger: prepare the next level's painting when the writer is
    /// within one strong day of crossing (or at 90% without history).
    private func evaluatePreparationTrigger() {
        let progress = progressStore.progress
        let nextLevel = progress.level + 1

        // Also cover an owed level whose painting was never generated
        // (the writer outran pre-generation).
        let targetLevel = progressStore.owedCeremonyLevel ?? nextLevel
        guard assetStore.installedPackage(forLevel: targetLevel) == nil else {
            return
        }
        // Static levels (≤ 8) pre-generate their shared default so the
        // ceremony is ready the moment it's crossed. Custom levels (≥ 9) are
        // never automatic — the writer summons them through the ritual
        // (`beginPaintingRitual`); automatic generation there was unreliable
        // and stripped the moment of its intention.
        guard targetLevel <= LevelProgressStore.freeBoundaryLevel else {
            return
        }
        let phase = progressStore.phase(forLevel: targetLevel)
        guard phase == .accumulating else {
            return
        }

        let owed = progressStore.owedCeremonyLevel != nil
        if !owed {
            let history = LevelTriggerTuning.dailySecondsHistory(from: sessionIndexStore.load())
            guard LevelTriggerTuning.shouldPrepareNextPainting(
                progress: progress,
                dailySecondsHistory: history
            ) else {
                return
            }
        }
        startPreparation(level: targetLevel)
    }

    private func startPreparation(level: Int) {
        guard !isPreparing else { return }
        let text = LevelTriggerTuning.distillText(
            artifacts: archive.list(),
            sinceMs: progressStore.lastLevelUpAtMs
        )
        guard text.count >= 80 else {
            return // not enough writing in the chapter yet
        }
        isPreparing = true
        progressStore.setPhase(.generationPending, forLevel: level)
        Task {
            defer { isPreparing = false }
            guard let identity = try? identityStore.loadOrCreate() else {
                progressStore.setPhase(.accumulating, forLevel: level)
                return
            }
            do {
                _ = try await LevelSyncClient().prepare(level: level, text: text, identity: identity)
                // Generation runs server-side; the package lands on a later
                // refresh (or the ceremony's waiting poll).
            } catch {
                progressStore.setPhase(.accumulating, forLevel: level)
            }
            await downloadOwedPackageIfNeeded()
            refreshOwedCeremony()
        }
    }

    private func reconcileWithServer() async {
        guard let identity = try? identityStore.loadOrCreate(),
              let status = try? await LevelSyncClient().fetchStatus(identity: identity) else {
            return
        }
        progressStore.adoptServerTotalIfHigher(status.totalSeconds)
        if status.nextPaintingPhase == .generated || status.nextPaintingPhase == .ceremonyPending {
            progressStore.setPhase(status.nextPaintingPhase, forLevel: status.nextLevel)
        }
        if let pending = status.pendingCeremonyLevel {
            progressStore.setPhase(.ceremonyPending, forLevel: pending)
        }
    }

    /// Prefetch: as soon as a package exists server-side, cache it forever.
    /// Tries the owed level first, then the next level's pre-generation.
    private func downloadOwedPackageIfNeeded() async {
        let progress = progressStore.progress
        var candidates = [progress.level + 1]
        if let owed = progressStore.owedCeremonyLevel {
            candidates.insert(owed, at: 0)
        }
        for level in candidates where assetStore.installedPackage(forLevel: level) == nil {
            let phase = progressStore.phase(forLevel: level)
            guard phase == .generated || phase == .ceremonyPending || phase == .generationPending else {
                continue
            }
            if (try? await assetStore.downloadPackage(level: level, identityStore: identityStore)) != nil {
                progressStore.setPhase(
                    progressStore.owedCeremonyLevel == level ? .ceremonyPending : .generated,
                    forLevel: level
                )
            }
        }
    }

    /// The ceremony's waiting poll: the writer outran generation, the
    /// darkness breathes while anky paints. Checks every few seconds; the
    /// caller bounds the wait — the ceremony must never hold the writer.
    func waitForCeremonyPackage(level: Int, attempts: Int = 40) async -> PaintingPackage? {
        for _ in 0..<max(1, attempts) {
            if let package = assetStore.installedPackage(forLevel: level) {
                owedCeremonyAssetsReady = true
                return package
            }
            await downloadOwedPackageIfNeeded()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
        return nil
    }
}
