import XCTest
@testable import AnkyCore

final class AdaptiveTargetPolicyTests: XCTestCase {
    private let calendar = Calendar.current
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 14))! }
    private var firstOpen: Date { calendar.date(byAdding: .day, value: -30, to: now)! }

    private func session(daysAgo: Int, minutes: Double) -> SessionSummary {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let createdAt = calendar.date(byAdding: .hour, value: 10, to: day)!
        return SessionSummary(
            hash: UUID().uuidString,
            createdAt: createdAt,
            localFileURL: URL(fileURLWithPath: "/tmp/test.anky"),
            durationMs: Int64(minutes * 60_000),
            isComplete: minutes >= 8,
            preview: "test",
            hasReflection: false,
            reflectionTitle: nil
        )
    }

    private func evaluate(_ sessions: [SessionSummary], target: Int = 8) -> AdaptiveTargetOffer? {
        AdaptiveTargetPolicy.evaluate(
            sessions: sessions,
            currentTargetMinutes: target,
            firstOpenDate: firstOpen,
            now: now,
            calendar: calendar
        )
    }

    func testTwoConsecutiveMissesOfferLowerTarget() {
        let sessions = [
            session(daysAgo: 3, minutes: 8),   // hit — ends the run
            session(daysAgo: 2, minutes: 3),   // missed
            session(daysAgo: 1, minutes: 2),   // missed
        ]
        let offer = evaluate(sessions)
        XCTAssertNotNil(offer)
        XCTAssertEqual(offer?.currentTargetMinutes, 8)
        XCTAssertEqual(offer?.suggestedTargetMinutes, 4)
    }

    func testSingleMissIsNotAnEpisode() {
        let sessions = [
            session(daysAgo: 2, minutes: 8),
            session(daysAgo: 1, minutes: 3),
        ]
        XCTAssertNil(evaluate(sessions))
    }

    func testTodayIsNeverJudged() {
        // Missed yesterday and wrote nothing yet today: run length is 1.
        let sessions = [
            session(daysAgo: 2, minutes: 8),
            session(daysAgo: 1, minutes: 1),
        ]
        XCTAssertNil(evaluate(sessions))
    }

    func testDaysWithNoWritingCountAsMissed() {
        // Wrote 4 days ago, then silence — yesterday and the day before are
        // missing entirely, which is still a missed run of >= 2.
        let sessions = [session(daysAgo: 4, minutes: 8)]
        let offer = evaluate(sessions)
        XCTAssertNotNil(offer)
    }

    func testMultipleShortSessionsDoNotSumIntoAHit() {
        // Daily Unlock needs one session at the target; three 3-minute
        // sessions do not open the door, so the day is missed.
        let shortDay2 = [session(daysAgo: 2, minutes: 3), session(daysAgo: 2, minutes: 3), session(daysAgo: 2, minutes: 3)]
        let sessions = shortDay2 + [session(daysAgo: 1, minutes: 3)]
        XCTAssertNotNil(evaluate(sessions))
    }

    func testEpisodeKeyIsStableWhileRunGrows() {
        let base = [
            session(daysAgo: 3, minutes: 2),
            session(daysAgo: 2, minutes: 2),
        ]
        let earlier = calendar.date(byAdding: .day, value: -1, to: now)!
        let offerEarlier = AdaptiveTargetPolicy.evaluate(
            sessions: base,
            currentTargetMinutes: 8,
            firstOpenDate: firstOpen,
            now: earlier,
            calendar: calendar
        )
        let offerLater = evaluate(base + [session(daysAgo: 1, minutes: 2)])
        XCTAssertNotNil(offerEarlier)
        XCTAssertEqual(offerEarlier?.episodeKey, offerLater?.episodeKey)
    }

    func testHitDayStartsAFreshEpisodeKey() {
        let firstEpisode = evaluate([
            session(daysAgo: 5, minutes: 2),
            session(daysAgo: 4, minutes: 2),
        ])
        let secondEpisode = evaluate([
            session(daysAgo: 5, minutes: 2),
            session(daysAgo: 4, minutes: 2),
            session(daysAgo: 3, minutes: 8),   // hit — episode over
            session(daysAgo: 2, minutes: 2),
            session(daysAgo: 1, minutes: 2),
        ])
        XCTAssertNotNil(firstEpisode)
        XCTAssertNotNil(secondEpisode)
        XCTAssertNotEqual(firstEpisode?.episodeKey, secondEpisode?.episodeKey)
    }

    func testSuggestionFloorsAtOneMinute() {
        XCTAssertEqual(AdaptiveTargetPolicy.suggestedMinutes(halving: 8), 4)
        XCTAssertEqual(AdaptiveTargetPolicy.suggestedMinutes(halving: 5), 3)
        XCTAssertEqual(AdaptiveTargetPolicy.suggestedMinutes(halving: 2), 1)
    }

    func testNoOfferAtOneMinuteTarget() {
        let sessions = [
            session(daysAgo: 2, minutes: 0.2),
            session(daysAgo: 1, minutes: 0.2),
        ]
        XCTAssertNil(evaluate(sessions, target: 1))
    }

    func testNoOfferForSomeoneWhoNeverWrote() {
        XCTAssertNil(evaluate([]))
    }

    func testOfferStoreShowsOncePerEpisode() {
        let suiteName = "adaptive-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AdaptiveTargetOfferStore(defaults: defaults)

        XCTAssertFalse(store.hasShown(episodeKey: "2026-07-03"))
        store.markShown(episodeKey: "2026-07-03")
        XCTAssertTrue(store.hasShown(episodeKey: "2026-07-03"))
        XCTAssertFalse(store.hasShown(episodeKey: "2026-07-06"))
    }
}
