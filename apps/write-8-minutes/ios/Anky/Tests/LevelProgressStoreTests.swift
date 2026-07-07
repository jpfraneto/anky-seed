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
        // 480s closes level 1; another 778s closes level 2 → real level 3.
        store.creditSealedSession(hash: hash(31), durationMs: 480_000)
        store.creditSealedSession(hash: hash(32), durationMs: 800_000)
        XCTAssertEqual(store.progress.level, 3)

        let held = store.presentedProgress(entitled: false)
        XCTAssertEqual(held.level, 2)
        XCTAssertEqual(held.percent, 1.0)
        XCTAssertEqual(held.secondsIntoLevel, held.secondsRequired)
        // Nothing lost: the true total is carried through the veil.
        XCTAssertEqual(held.totalSeconds, store.progress.totalSeconds)

        XCTAssertEqual(store.presentedProgress(entitled: true).level, 3)
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
        store.creditSealedSession(hash: hash(35), durationMs: 800_000)
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
