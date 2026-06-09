import XCTest
@testable import AnkyProtocol

final class AnkyWriterTests: XCTestCase {
    func testGeneratedAnkyCanBeParsedAndReconstructed() throws {
        var writer = AnkyWriter()

        XCTAssertTrue(writer.accept("h", at: 1_770_000_000_000))
        XCTAssertTrue(writer.accept("i", at: 1_770_000_000_042))
        writer.closeWithTerminalSilence()

        XCTAssertEqual(writer.text, """
        1770000000000 h
        42 i
        8000
        """)

        let parsed = try AnkyParser.parse(writer.text)
        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "hi")
        XCTAssertEqual(AnkyDuration.durationMs(parsed), 42)
    }

    func testGeneratedAnkyStoresSpacesAsCanonicalSpaceToken() throws {
        var writer = AnkyWriter()

        XCTAssertTrue(writer.accept("h", at: 1_770_000_000_000))
        XCTAssertTrue(writer.accept(" ", at: 1_770_000_000_042))
        XCTAssertTrue(writer.accept("i", at: 1_770_000_000_090))

        XCTAssertEqual(writer.text, """
        1770000000000 h
        42 SPACE
        48 i
        """)

        let parsed = try AnkyParser.parse(writer.text)
        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "h i")
    }

    func testRejectsCharactersThatCannotLiveInLineProtocol() {
        var writer = AnkyWriter()

        XCTAssertFalse(writer.accept("\n", at: 1_770_000_000_000))
        XCTAssertFalse(writer.accept("\r", at: 1_770_000_000_000))
        XCTAssertEqual(writer.text, "")
    }

    func testFirstAcceptedCharacterStartsSession() throws {
        var writer = AnkyWriter()

        writer.accept("a", at: 1_770_000_000_000)

        let parsed = try AnkyParser.parse(writer.text)
        XCTAssertEqual(parsed.startEpochMs, 1_770_000_000_000)
        XCTAssertEqual(parsed.events, [AnkyEvent(deltaMs: 0, character: "a")])
    }

    func testResumeAfterFrozenSilenceDoesNotStoreIdleGap() throws {
        var writer = AnkyWriter()

        writer.accept("a", at: 1_770_000_000_000)
        writer.prepareToResume(at: 1_770_000_030_000)
        writer.accept("b", at: 1_770_000_030_000)

        let parsed = try AnkyParser.parse(writer.text)
        XCTAssertEqual(parsed.events, [
            AnkyEvent(deltaMs: 0, character: "a"),
            AnkyEvent(deltaMs: 0, character: "b")
        ])
        XCTAssertNil(parsed.terminalSilenceMs)
    }

    func testUtcDayProgressGrowsWithTheDay() {
        XCTAssertEqual(AnkyDuration.utcDayProgress(at: Date(timeIntervalSince1970: 6 * 60 * 60)), 0.25, accuracy: 0.001)
        XCTAssertEqual(AnkyDuration.utcDayProgress(at: Date(timeIntervalSince1970: 12 * 60 * 60)), 0.50, accuracy: 0.001)
        XCTAssertEqual(AnkyDuration.utcDayProgress(at: Date(timeIntervalSince1970: 18 * 60 * 60)), 0.75, accuracy: 0.001)
    }

    func testClockFormatsPostRitualWritingTime() {
        XCTAssertEqual(AnkyDuration.clock(480_000), "8:00")
        XCTAssertEqual(AnkyDuration.clock(481_000), "8:01")
        XCTAssertEqual(AnkyDuration.clock(552_000), "9:12")
    }

    func testRitualClockNeverShowsPastEightMinutes() {
        XCTAssertEqual(AnkyDuration.ritualClock(480_000), "8:00")
        XCTAssertEqual(AnkyDuration.ritualClock(481_000), "8:00")
        XCTAssertEqual(AnkyDuration.ritualClock(552_000), "8:00")
    }
}
