import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class LevelProgressStoreTests: XCTestCase {
    private func temporaryStore() -> LevelProgressStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anky-tests-\(UUID().uuidString)")
            .appendingPathComponent("level-progress.json")
        return LevelProgressStore(url: url)
    }

    private func hash(_ seed: Int) -> String {
        String(repeating: "0", count: 64 - String(seed).count) + String(seed)
    }

    func testCreditAccumulatesAndQueuesReport() {
        let store = temporaryStore()
        let progress = store.creditSealedSession(hash: hash(1), durationMs: 480_000)
        XCTAssertEqual(progress.level, 2)
        XCTAssertEqual(progress.totalSeconds, 480)
        XCTAssertEqual(store.peekPendingStrokeSeconds(), 480)
        XCTAssertEqual(store.unreportedSessions().count, 1)
        XCTAssertEqual(store.unreportedSessions().first?.seconds, 480)
    }

    func testCreditIsIdempotentPerHash() {
        let store = temporaryStore()
        store.creditSealedSession(hash: hash(2), durationMs: 60_000)
        store.creditSealedSession(hash: hash(2), durationMs: 60_000)
        XCTAssertEqual(store.progress.totalSeconds, 60)
        XCTAssertEqual(store.unreportedSessions().count, 1)
    }

    func testContinuedSessionCreditsOnlyTheDelta() {
        let store = temporaryStore()
        store.creditSealedSession(hash: hash(3), durationMs: 120_000)
        store.creditSealedSession(hash: hash(4), durationMs: 300_000, replacedDurationMs: 120_000)
        XCTAssertEqual(store.progress.totalSeconds, 120 + 180)
        XCTAssertEqual(store.unreportedSessions().map(\.seconds), [120, 180])
    }

    func testSubSecondSessionsDoNotCredit() {
        let store = temporaryStore()
        store.creditSealedSession(hash: hash(5), durationMs: 900)
        XCTAssertEqual(store.progress.totalSeconds, 0)
        XCTAssertTrue(store.unreportedSessions().isEmpty)
    }

    // MARK: Phase-3 boundary

    func testPresentedProgressHoldsAtBoundaryForFreeWriters() {
        let store = temporaryStore()
        // Bank lifetime seconds past level 9 — the first dynamically
        // generated level now that 1–8 ship as shared static defaults
        // (decision 2026-07-08); the free display holds at 8.
        let pastBoundaryMs = Int64(AnkyLevel.thresholdSeconds(forLevel: 9) + 60) * 1000
        store.creditSealedSession(hash: hash(31), durationMs: pastBoundaryMs)
        XCTAssertEqual(store.progress.level, 9)

        let held = store.presentedProgress(entitled: false)
        XCTAssertEqual(held.level, 8)
        XCTAssertEqual(held.percent, 1.0)
        XCTAssertEqual(held.secondsIntoLevel, held.secondsRequired)
        // Nothing lost: the true total is carried through the veil.
        XCTAssertEqual(held.totalSeconds, store.progress.totalSeconds)

        XCTAssertEqual(store.presentedProgress(entitled: true).level, 9)
        XCTAssertTrue(store.isAtBoundary(entitled: false))
        XCTAssertFalse(store.isAtBoundary(entitled: true))
    }

    func testPresentedProgressIsRealBeforeTheBoundary() {
        let store = temporaryStore()
        store.creditSealedSession(hash: hash(33), durationMs: 480_000)
        XCTAssertEqual(store.progress.level, 2)
        let presented = store.presentedProgress(entitled: false)
        XCTAssertEqual(presented, store.progress)
        XCTAssertFalse(store.isAtBoundary(entitled: false))
    }

    func testBoundaryReportClaimsExactlyOnce() {
        let store = temporaryStore()
        store.creditSealedSession(hash: hash(34), durationMs: 480_000)
        XCTAssertFalse(store.claimBoundaryReport(entitled: false), "not at boundary yet")
        let pastBoundaryMs = Int64(AnkyLevel.thresholdSeconds(forLevel: 9) + 60) * 1000
        store.creditSealedSession(hash: hash(35), durationMs: pastBoundaryMs)
        XCTAssertFalse(store.claimBoundaryReport(entitled: true), "entitled writers have no boundary")
        XCTAssertTrue(store.claimBoundaryReport(entitled: false))
        XCTAssertFalse(store.claimBoundaryReport(entitled: false), "one report per life")
    }

    func testPendingStrokeSecondsConsumeOnce() {
        let store = temporaryStore()
        store.creditSealedSession(hash: hash(6), durationMs: 90_000)
        XCTAssertEqual(store.consumePendingStrokeSeconds(), 90)
        XCTAssertEqual(store.consumePendingStrokeSeconds(), 0)
    }

    func testBackfillRunsOnce() {
        let store = temporaryStore()
        let summaries = [
            makeSummary(hash: hash(7), durationMs: 240_000),
            makeSummary(hash: hash(8), durationMs: 240_000),
        ]
        store.backfillIfNeeded(from: summaries)
        store.backfillIfNeeded(from: summaries)
        XCTAssertEqual(store.progress.totalSeconds, 480)
        XCTAssertEqual(store.unreportedSessions().count, 2)
        // Backfill never owes strokes — the paintings begin from the present.
        XCTAssertEqual(store.peekPendingStrokeSeconds(), 0)
    }

    func testMarkReportedDrainsQueue() {
        let store = temporaryStore()
        store.creditSealedSession(hash: hash(9), durationMs: 60_000)
        store.creditSealedSession(hash: hash(10), durationMs: 60_000)
        store.markReported(hashes: [hash(9)])
        XCTAssertEqual(store.unreportedSessions().map(\.hash), [hash(10)])
        XCTAssertEqual(store.progress.totalSeconds, 120)
    }

    func testAdoptServerTotalOnlyIfHigher() {
        let store = temporaryStore()
        store.creditSealedSession(hash: hash(11), durationMs: 100_000)
        store.adoptServerTotalIfHigher(50)
        XCTAssertEqual(store.progress.totalSeconds, 100)
        store.adoptServerTotalIfHigher(700)
        XCTAssertEqual(store.progress.totalSeconds, 700)
    }

    func testPhasePersistsPerLevel() {
        let store = temporaryStore()
        XCTAssertEqual(store.phase(forLevel: 2), .accumulating)
        store.setPhase(.generated, forLevel: 2)
        XCTAssertEqual(store.phase(forLevel: 2), .generated)
        XCTAssertEqual(store.phase(forLevel: 3), .accumulating)
    }

    func testLoadingExcerptsComeFromCurrentChapterWriting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anky-excerpts-\(UUID().uuidString)", isDirectory: true)
        let archive = LocalAnkyArchive(directoryURL: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let old = try archive.save("1770000000000 o\n0 l\n0 d\n8000")
        let currentOne = try archive.save("1770000100000 T\n0 h\n0 i\n0 s\n0 SPACE\n0 i\n0 s\n0 SPACE\n0 t\n0 h\n0 e\n0 SPACE\n0 f\n0 i\n0 r\n0 s\n0 t\n0 SPACE\n0 p\n0 a\n0 i\n0 n\n0 t\n0 i\n0 n\n0 g\n0 SPACE\n0 s\n0 e\n0 e\n0 d\n0 .\n8000")
        let currentTwo = try archive.save("1770000200000 A\n0 n\n0 o\n0 t\n0 h\n0 e\n0 r\n0 SPACE\n0 p\n0 i\n0 e\n0 c\n0 e\n0 SPACE\n0 f\n0 r\n0 o\n0 m\n0 SPACE\n0 t\n0 h\n0 e\n0 SPACE\n0 c\n0 h\n0 a\n0 p\n0 t\n0 e\n0 r\n0 .\n8000")

        let excerpts = LevelTriggerTuning.loadingExcerpts(
            artifacts: [old, currentTwo, currentOne],
            sinceMs: Int64(old.createdAt.addingTimeInterval(1).timeIntervalSince1970 * 1000),
            limit: 3
        )

        XCTAssertFalse(excerpts.contains { $0.contains("old") })
        XCTAssertTrue(excerpts.contains { $0.contains("first painting seed") })
        XCTAssertTrue(excerpts.contains { $0.contains("Another piece") })
    }

    // MARK: No ceremony crawl for adopted writers

    func testBackfillLandsAtTrueLevelWithNoCeremonyBacklog() {
        let store = temporaryStore()
        // A writer who wrote past level 4 before the level system existed.
        let toLevelFour = Int64(AnkyLevel.thresholdSeconds(forLevel: 4) + 30) * 1000
        store.backfillIfNeeded(from: [makeSummary(hash: hash(40), durationMs: toLevelFour)])

        XCTAssertEqual(store.progress.level, 4)
        // No crawl: the shared static paintings are revealed at once, not one
        // ceremony per app open.
        XCTAssertNil(store.owedCeremonyLevel)
        XCTAssertEqual(store.lastCeremonyShownLevel, 4)
        XCTAssertEqual(store.phase(forLevel: 3), .ceremonyShown)
    }

    func testReconcileClearsAStuckCeremonyBacklog() {
        let store = temporaryStore()
        // Simulate an install that already banked seconds (past level system
        // versions credited without fast-forwarding the pointer).
        let toLevelFour = Int64(AnkyLevel.thresholdSeconds(forLevel: 4) + 30) * 1000
        store.creditSealedSession(hash: hash(41), durationMs: toLevelFour)
        XCTAssertEqual(store.owedCeremonyLevel, 2) // the crawl, before repair

        store.reconcileCeremonyPointerIfNeeded()
        XCTAssertNil(store.owedCeremonyLevel)
        XCTAssertEqual(store.lastCeremonyShownLevel, 4)

        // Idempotent: a second pass does nothing.
        store.reconcileCeremonyPointerIfNeeded()
        XCTAssertNil(store.owedCeremonyLevel)
    }

    func testCustomLevelStaysOwedToInviteTheRitual() {
        let store = temporaryStore()
        // A Pro writer already past the static boundary (level 9+).
        let toLevelNine = Int64(AnkyLevel.thresholdSeconds(forLevel: 9) + 30) * 1000
        store.creditSealedSession(hash: hash(42), durationMs: toLevelNine)
        store.reconcileCeremonyPointerIfNeeded()

        // Static levels are settled at the boundary; the custom level 9 stays
        // owed so the writer can summon its painting through the ritual.
        XCTAssertEqual(store.lastCeremonyShownLevel, 8)
        XCTAssertEqual(store.owedCeremonyLevel, 9)
    }

    func testHealReopensACustomLevelWhosePaintingWasLost() {
        let store = temporaryStore()
        // A Pro writer who reached level 9, witnessed its ceremony, then lost
        // the canvas (reinstall / purge / updated into the ritual feature).
        let toLevelNine = Int64(AnkyLevel.thresholdSeconds(forLevel: 9) + 30) * 1000
        store.creditSealedSession(hash: hash(43), durationMs: toLevelNine)
        store.markCeremonyShown(level: 9)
        XCTAssertEqual(store.lastCeremonyShownLevel, 9)
        XCTAssertNil(store.owedCeremonyLevel)
        XCTAssertEqual(store.phase(forLevel: 9), .ceremonyShown)

        // No level-9 package on disk → heal rolls the pointer back so the
        // ritual can summon it again, instead of hanging level 8 at 100%.
        XCTAssertTrue(store.healOrphanedCustomCeremonies { _ in false })
        XCTAssertEqual(store.lastCeremonyShownLevel, 8)
        XCTAssertEqual(store.owedCeremonyLevel, 9)
        XCTAssertEqual(store.phase(forLevel: 9), .accumulating)

        // Idempotent once healed.
        XCTAssertFalse(store.healOrphanedCustomCeremonies { _ in false })
    }

    func testHealLeavesAnInstalledCustomPaintingAlone() {
        let store = temporaryStore()
        let toLevelNine = Int64(AnkyLevel.thresholdSeconds(forLevel: 9) + 30) * 1000
        store.creditSealedSession(hash: hash(44), durationMs: toLevelNine)
        store.markCeremonyShown(level: 9)

        // Its canvas is present → nothing to heal.
        XCTAssertFalse(store.healOrphanedCustomCeremonies { $0 == 9 })
        XCTAssertEqual(store.lastCeremonyShownLevel, 9)
        XCTAssertNil(store.owedCeremonyLevel)
    }

    func testHealIsANoOpInsideTheStaticLevels() {
        let store = temporaryStore()
        let toLevelFour = Int64(AnkyLevel.thresholdSeconds(forLevel: 4) + 30) * 1000
        store.backfillIfNeeded(from: [makeSummary(hash: hash(45), durationMs: toLevelFour)])
        XCTAssertEqual(store.lastCeremonyShownLevel, 4)

        // Static levels ship as shared defaults with no package requirement.
        XCTAssertFalse(store.healOrphanedCustomCeremonies { _ in false })
        XCTAssertEqual(store.lastCeremonyShownLevel, 4)
    }

    func testHealStopsAtTheFirstGapAboveInstalledCustomPaintings() {
        let store = temporaryStore()
        // A writer at level 11 who has witnessed ceremonies 9, 10 and 11 but
        // whose level-10 canvas went missing.
        let toLevelEleven = Int64(AnkyLevel.thresholdSeconds(forLevel: 11) + 30) * 1000
        store.creditSealedSession(hash: hash(46), durationMs: toLevelEleven)
        store.markCeremonyShown(level: 9)
        store.markCeremonyShown(level: 10)
        store.markCeremonyShown(level: 11)

        // Only level 9 is on disk → the pointer rolls back to 9 so level 10 is
        // re-summoned first; level 11 reopens too and follows in turn.
        XCTAssertTrue(store.healOrphanedCustomCeremonies { $0 == 9 })
        XCTAssertEqual(store.lastCeremonyShownLevel, 9)
        XCTAssertEqual(store.owedCeremonyLevel, 10)
        XCTAssertEqual(store.phase(forLevel: 10), .accumulating)
        XCTAssertEqual(store.phase(forLevel: 11), .accumulating)
    }

    func testLegacySnapshotMissingNewFieldsLoadsWithoutDataLoss() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anky-tests-\(UUID().uuidString)")
            .appendingPathComponent("level-progress.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // A snapshot as an older build wrote it: no didReconcileCeremonyPointer,
        // no didReportBoundary. Decoding must NOT throw (which would reset the
        // writer's lifetime seconds to zero).
        let legacy = #"{"totalSeconds":5000,"pendingStrokeSeconds":0,"unreported":[],"phaseByLevel":{},"didBackfill":true,"lastCeremonyShownLevel":3}"#
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        let store = LevelProgressStore(url: url)
        XCTAssertEqual(store.progress.totalSeconds, 5000)
        XCTAssertEqual(store.lastCeremonyShownLevel, 3)
    }

    func testReconcileIsANoOpForABrandNewWriter() {
        let store = temporaryStore()
        store.reconcileCeremonyPointerIfNeeded()
        XCTAssertNil(store.owedCeremonyLevel)
        XCTAssertEqual(store.lastCeremonyShownLevel, 1)
    }

    private func makeSummary(hash: String, durationMs: Int64) -> SessionSummary {
        SessionSummary(
            hash: hash,
            createdAt: Date(),
            localFileURL: URL(fileURLWithPath: "/tmp/\(hash).anky"),
            durationMs: durationMs,
            isComplete: durationMs >= AnkyDuration.completeRitualMs,
            preview: "preview",
            hasReflection: false,
            reflectionTitle: nil
        )
    }
}
