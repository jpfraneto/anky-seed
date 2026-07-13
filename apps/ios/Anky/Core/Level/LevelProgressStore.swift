import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

/// Phase of one level's painting, keyed by the level the painting celebrates
/// reaching. Mirrors the server's `level_state.phase`.
enum LevelPaintingPhase: String, Codable {
    case accumulating
    case generationPending
    case generated
    case ceremonyPending
    case ceremonyShown
}

/// A sealed session the server's ledger has not acknowledged yet.
/// Carries hash and seconds only — never writing.
struct LevelUnreportedSession: Codable, Equatable {
    let hash: String
    let seconds: Int
    let sealedAtMs: Int64
}

struct LevelProgressSnapshot: Codable, Equatable {
    var totalSeconds: Int = 0
    var pendingStrokeSeconds: Int = 0
    var unreported: [LevelUnreportedSession] = []
    var phaseByLevel: [String: LevelPaintingPhase] = [:]
    var didBackfill: Bool = false
    /// Phase-3 funnel: whether boundary_reached has been reported for this
    /// writer. One event per life, persisted so relaunches never repeat it.
    var didReportBoundary: Bool = false
    /// The moment the last ceremony was shown — the chapter boundary the
    /// next distillation reads from. Nil means "since the beginning".
    var lastLevelUpAtMs: Int64?
    /// Highest level whose unveiling has been witnessed (nil reads as 1:
    /// level 1 needs no ceremony — it is the beginning).
    var lastCeremonyShownLevel: Int?
    /// One-time migration guard: an adopted historical writer (or a reinstall)
    /// must land at their true level, not crawl one ceremony per app open.
    /// Once true, the ceremony pointer has been fast-forwarded through the
    /// shared static levels.
    var didReconcileCeremonyPointer: Bool = false
}

extension LevelProgressSnapshot {
    /// Resilient decode: every field is optional-with-default so a snapshot
    /// written by an older build (missing a key added later) still loads with
    /// its real data. Swift's synthesized decoder throws on any missing
    /// non-optional key, and `load()` treats a throw as a fresh-empty snapshot
    /// — which would silently WIPE a writer's lifetime seconds on update.
    /// Adding a field to this struct without this init is data loss.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.totalSeconds = try container.decodeIfPresent(Int.self, forKey: .totalSeconds) ?? 0
        self.pendingStrokeSeconds = try container.decodeIfPresent(Int.self, forKey: .pendingStrokeSeconds) ?? 0
        self.unreported = try container.decodeIfPresent([LevelUnreportedSession].self, forKey: .unreported) ?? []
        self.phaseByLevel = try container.decodeIfPresent([String: LevelPaintingPhase].self, forKey: .phaseByLevel) ?? [:]
        self.didBackfill = try container.decodeIfPresent(Bool.self, forKey: .didBackfill) ?? false
        self.didReportBoundary = try container.decodeIfPresent(Bool.self, forKey: .didReportBoundary) ?? false
        self.lastLevelUpAtMs = try container.decodeIfPresent(Int64.self, forKey: .lastLevelUpAtMs)
        self.lastCeremonyShownLevel = try container.decodeIfPresent(Int.self, forKey: .lastCeremonyShownLevel)
        self.didReconcileCeremonyPointer = try container.decodeIfPresent(Bool.self, forKey: .didReconcileCeremonyPointer) ?? false
    }
}

/// The client-side counter of record for lifetime seconds written.
///
/// Every sealed session credits its exact seconds here, synchronously, before
/// any UI transition — the number is offline-correct and never waits on the
/// network. The server ledger (`POST /level/sessions`) is reconciled from the
/// `unreported` queue whenever connectivity allows.
struct LevelProgressStore {
    private let url: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(url: base.appendingPathComponent("Anky/level-progress.json"), fileManager: fileManager)
    }

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func load() -> LevelProgressSnapshot {
        guard let data = try? Data(contentsOf: url) else {
            return LevelProgressSnapshot()
        }
        return (try? JSONDecoder().decode(LevelProgressSnapshot.self, from: data)) ?? LevelProgressSnapshot()
    }

    func save(_ snapshot: LevelProgressSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        try? data.write(to: url, options: [.atomic])
    }

    var progress: AnkyLevel.Progress {
        AnkyLevel.progress(forTotalSeconds: load().totalSeconds)
    }

    // MARK: Phase-3 boundary

    /// Levels 1–8 are shared static default paintings with no generation
    /// cost (decision 2026-07-08), so the free tier deepens all the way
    /// through them and holds at 8 — dynamic per-writer paintings start at
    /// level 9 and belong to the subscription. Presentation never advances
    /// past this level unentitled. Mirrors the backend's STATIC_LEVEL_MAX /
    /// FREE_GENERATION_MAX_LEVEL.
    static let freeBoundaryLevel = 8

    /// What the UI shows. Entitled writers see the true curve; a free writer
    /// past the boundary sees level 8 serenely complete at 100%. The counter
    /// underneath keeps every second — nothing is ever lost, and the true
    /// level reappears the moment entitlement does.
    func presentedProgress(entitled: Bool) -> AnkyLevel.Progress {
        let real = progress
        guard !entitled, real.level > Self.freeBoundaryLevel else {
            return real
        }
        let required = AnkyLevel.requirementSeconds(forLevel: Self.freeBoundaryLevel)
        return AnkyLevel.Progress(
            level: Self.freeBoundaryLevel,
            secondsIntoLevel: required,
            secondsRequired: required,
            percent: 1.0,
            totalSeconds: real.totalSeconds
        )
    }

    /// True while a free writer stands at the held-100% moment.
    func isAtBoundary(entitled: Bool) -> Bool {
        !entitled && progress.level > Self.freeBoundaryLevel
    }

    /// Claims the one boundary_reached funnel report. Returns true exactly
    /// once, when the writer first stands at the boundary.
    func claimBoundaryReport(entitled: Bool) -> Bool {
        guard isAtBoundary(entitled: entitled) else {
            return false
        }
        var snapshot = load()
        guard !snapshot.didReportBoundary else {
            return false
        }
        snapshot.didReportBoundary = true
        save(snapshot)
        return true
    }

    /// Credits a sealed session. When the session replaced a continued
    /// artifact, only the newly written delta is credited (the replaced
    /// artifact's seconds were already counted under its own hash).
    @discardableResult
    func creditSealedSession(
        hash: String,
        durationMs: Int64,
        replacedDurationMs: Int64? = nil,
        sealedAt: Date = Date()
    ) -> AnkyLevel.Progress {
        var snapshot = load()
        let sessionSeconds = Int(durationMs / 1000)
        let replacedSeconds = Int((replacedDurationMs ?? 0) / 1000)
        let creditSeconds = max(0, sessionSeconds - replacedSeconds)
        guard creditSeconds > 0, !snapshot.unreported.contains(where: { $0.hash == hash }) else {
            return AnkyLevel.progress(forTotalSeconds: snapshot.totalSeconds)
        }
        snapshot.totalSeconds += creditSeconds
        snapshot.pendingStrokeSeconds += creditSeconds
        snapshot.unreported.append(
            LevelUnreportedSession(
                hash: hash,
                seconds: creditSeconds,
                sealedAtMs: Int64(sealedAt.timeIntervalSince1970 * 1000)
            )
        )
        save(snapshot)
        return AnkyLevel.progress(forTotalSeconds: snapshot.totalSeconds)
    }

    /// One-time adoption of history that predates the level system: sums the
    /// session index and queues every artifact for the server ledger.
    func backfillIfNeeded(from summaries: [SessionSummary]) {
        var snapshot = load()
        guard !snapshot.didBackfill else {
            return
        }
        snapshot.didBackfill = true
        for summary in summaries {
            let seconds = Int(summary.durationMs / 1000)
            guard seconds > 0, !snapshot.unreported.contains(where: { $0.hash == summary.hash }) else {
                continue
            }
            snapshot.totalSeconds += seconds
            snapshot.unreported.append(
                LevelUnreportedSession(
                    hash: summary.hash,
                    seconds: seconds,
                    sealedAtMs: Int64(summary.createdAt.timeIntervalSince1970 * 1000)
                )
            )
        }
        // Land the adopted writer at their true level with every shared static
        // painting already revealed — no crawl through past ceremonies.
        fastForwardCeremonyPointer(&snapshot)
        save(snapshot)
    }

    /// Adopted historical writers, reinstalls, and anyone updating into the
    /// level system after already writing must appear at the level they have
    /// earned — the shared static paintings (≤ 8) simply hang revealed, and
    /// only the custom levels (≥ 9) are unveiled one ritual at a time. Runs
    /// exactly once per install.
    func reconcileCeremonyPointerIfNeeded() {
        var snapshot = load()
        guard !snapshot.didReconcileCeremonyPointer else {
            return
        }
        fastForwardCeremonyPointer(&snapshot)
        save(snapshot)
    }

    /// Advances the ceremony pointer to the highest already-earned static
    /// level, so no backlog of past unveilings queues up. Custom levels are
    /// deliberately left owed — their paintings are summoned by the writer.
    private func fastForwardCeremonyPointer(_ snapshot: inout LevelProgressSnapshot) {
        snapshot.didReconcileCeremonyPointer = true
        let reached = AnkyLevel.level(forTotalSeconds: snapshot.totalSeconds)
        let shown = snapshot.lastCeremonyShownLevel ?? 1
        let fastForwarded = max(shown, min(reached, Self.freeBoundaryLevel))
        guard fastForwarded > shown else {
            return
        }
        snapshot.lastCeremonyShownLevel = fastForwarded
        // Every static level up to here is now revealed, not owed.
        for level in 2...max(2, fastForwarded) where level <= fastForwarded {
            snapshot.phaseByLevel[String(level)] = .ceremonyShown
        }
    }

    /// The strokes owed to the next visit of the painting page.
    func consumePendingStrokeSeconds() -> Int {
        var snapshot = load()
        let pending = snapshot.pendingStrokeSeconds
        guard pending > 0 else {
            return 0
        }
        snapshot.pendingStrokeSeconds = 0
        save(snapshot)
        return pending
    }

    func peekPendingStrokeSeconds() -> Int {
        load().pendingStrokeSeconds
    }

    func phase(forLevel level: Int) -> LevelPaintingPhase {
        load().phaseByLevel[String(level)] ?? .accumulating
    }

    var lastCeremonyShownLevel: Int {
        load().lastCeremonyShownLevel ?? 1
    }

    var lastLevelUpAtMs: Int64? {
        load().lastLevelUpAtMs
    }

    /// The lowest level whose unveiling is owed: the writer has reached it,
    /// but its ceremony has not been witnessed. Replay-safe across app kill —
    /// this is pure persisted state, recomputed on every ask.
    var owedCeremonyLevel: Int? {
        let snapshot = load()
        let reached = AnkyLevel.level(forTotalSeconds: snapshot.totalSeconds)
        let shown = snapshot.lastCeremonyShownLevel ?? 1
        guard reached > shown else {
            return nil
        }
        return shown + 1
    }

    /// Closes one unveiling. Persisted synchronously before any UI moves on —
    /// it must be impossible to permanently miss (or repeat) your own ceremony.
    func markCeremonyShown(level: Int, at date: Date = Date()) {
        var snapshot = load()
        let shown = snapshot.lastCeremonyShownLevel ?? 1
        guard level > shown else {
            return
        }
        snapshot.lastCeremonyShownLevel = level
        snapshot.lastLevelUpAtMs = Int64(date.timeIntervalSince1970 * 1000)
        snapshot.phaseByLevel[String(level)] = .ceremonyShown
        save(snapshot)
    }

    func setPhase(_ phase: LevelPaintingPhase, forLevel level: Int) {
        var snapshot = load()
        snapshot.phaseByLevel[String(level)] = phase
        save(snapshot)
    }

    func unreportedSessions(limit: Int = 500) -> [LevelUnreportedSession] {
        Array(load().unreported.prefix(limit))
    }

    func markReported(hashes: [String]) {
        guard !hashes.isEmpty else {
            return
        }
        var snapshot = load()
        let reported = Set(hashes)
        snapshot.unreported.removeAll { reported.contains($0.hash) }
        save(snapshot)
    }

    /// Reinstall recovery: the server ledger may know sessions this install
    /// never saw. The counter is monotonic, so adopt the higher total.
    func adoptServerTotalIfHigher(_ serverTotalSeconds: Int) {
        var snapshot = load()
        guard serverTotalSeconds > snapshot.totalSeconds else {
            return
        }
        snapshot.totalSeconds = serverTotalSeconds
        save(snapshot)
    }
}
