import XCTest
@testable import Anky

@MainActor
final class JourneyAnchorTests: XCTestCase {
    private let calendar = Calendar.ankyUTC
    private let fileURL = URL(fileURLWithPath: "/tmp/journey-anchor-test.anky")

    private func day(_ offset: Int) -> Date {
        calendar.date(
            byAdding: .day,
            value: offset,
            to: Date(timeIntervalSince1970: 1_770_000_000)
        )!
    }

    private func summary(day offset: Int, complete: Bool = true, hash: String? = nil) -> SessionSummary {
        SessionSummary(
            hash: hash ?? String(format: "%064d", offset + 1),
            createdAt: day(offset),
            localFileURL: fileURL,
            durationMs: complete ? 480_000 : 60_000,
            isComplete: complete,
            preview: "writing",
            hasReflection: false,
            reflectionTitle: nil
        )
    }

    private func journeyDay(nowOffset: Int, sessions: [SessionSummary]) -> Int {
        let state = JourneyState()
        state.refresh(summaries: sessions, now: day(nowOffset), calendar: calendar)
        return state.currentJourneyDay
    }

    func testFirstSealedWritingIsDayOne() {
        let sessions = [
            summary(day: -3, complete: false),
            summary(day: 0, complete: true),
        ]

        XCTAssertEqual(JourneyAnchor.firstSealedDay(in: sessions, calendar: calendar), calendar.startOfDay(for: day(0)))
        XCTAssertEqual(journeyDay(nowOffset: 0, sessions: sessions), 1)
    }

    func testJourneyBoundariesAroundDaysEightAndNine() {
        let sessions = [summary(day: 0)]

        XCTAssertEqual(journeyDay(nowOffset: 7, sessions: sessions), 8)
        XCTAssertEqual(journeyDay(nowOffset: 8, sessions: sessions), 9)
    }

    func testJourneyBoundariesAroundDaysTwelveAndThirteen() {
        let sessions = [summary(day: 0)]

        XCTAssertEqual(journeyDay(nowOffset: 11, sessions: sessions), 12)
        XCTAssertEqual(journeyDay(nowOffset: 12, sessions: sessions), 13)
    }

    func testJourneyBoundariesAroundDaysNinetyFiveAndNinetySix() {
        let sessions = [summary(day: 0)]

        XCTAssertEqual(journeyDay(nowOffset: 94, sessions: sessions), 95)
        XCTAssertEqual(journeyDay(nowOffset: 95, sessions: sessions), 96)
    }

    func testPostDayNinetySixHoldsAtCompletion() {
        let sessions = [summary(day: 0)]

        XCTAssertEqual(journeyDay(nowOffset: 96, sessions: sessions), 96)
        XCTAssertEqual(journeyDay(nowOffset: 400, sessions: sessions), 96)
    }

    func testNoProductionJourneyCodeUsesFirstAppOpenAnchoring() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "Anky/Features/Painting/Journey/JourneyTilePositions.swift",
            "Anky/Features/Map/MapViewModel.swift",
            "Anky/Features/Reveal/RevealViewModel.swift",
            "Anky/Features/You/YouView.swift",
        ]

        for file in files {
            let text = try String(contentsOf: repoRoot.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("AppOpenStore().loadOrCreate"), file)
            XCTAssertFalse(text.contains("appOpenStore.loadOrCreate"), file)
        }
    }
}
