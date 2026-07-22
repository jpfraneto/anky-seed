import XCTest
@testable import AnkyProtocol

final class AnkyWriterTests: XCTestCase {
    func testGeneratedAnkyCanBeParsedAndReconstructed() throws {
        var writer = AnkyWriter()

        XCTAssertTrue(writer.accept("h", at: 1_770_000_000_000))
        XCTAssertTrue(writer.accept("i", at: 1_770_000_000_042))
        // D3: the written sentinel is always the canonical 8000 symbol,
        // independent of the configured inactivity threshold passed here.
        writer.closeWithTerminalSilence(after: 1000)

        XCTAssertEqual(writer.text, """
        1770000000000 h
        42 i
        8000
        """)

        let parsed = try AnkyParser.parse(writer.text)
        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "hi")
        XCTAssertEqual(AnkyDuration.durationMs(parsed), 42)
        XCTAssertEqual(parsed.terminalSilenceMs, AnkyDuration.canonicalSentinelToken)
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

    func testReplaceSuffixRebuildsCurrentWordAsCharacterEvents() throws {
        var writer = AnkyWriter()

        writer.accept("t", at: 1_770_000_000_000)
        writer.accept("e", at: 1_770_000_000_030)
        writer.accept("h", at: 1_770_000_000_060)

        let accepted = writer.replaceSuffix(
            keepingPrefixCharacterCount: 0,
            with: "the",
            at: 1_770_000_000_090
        )

        XCTAssertEqual(accepted, ["t", "h", "e"])
        let parsed = try AnkyParser.parse(writer.text)
        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "the")
        XCTAssertEqual(parsed.events.map(\.character), ["t", "h", "e"])
        XCTAssertEqual(AnkyDuration.durationMs(parsed), 90)
    }

    func testReplaceSuffixPreservesPrefixAndInterpolatesCorrectedTail() throws {
        var writer = AnkyWriter()
        let text = "hello teh "
        for (index, character) in text.enumerated() {
            writer.accept(character, at: 1_770_000_000_000 + Int64(index * 20))
        }

        let accepted = writer.replaceSuffix(
            keepingPrefixCharacterCount: 6,
            with: "the ",
            at: 1_770_000_000_240
        )

        XCTAssertEqual(accepted, ["t", "h", "e", " "])
        let parsed = try AnkyParser.parse(writer.text)
        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "hello the ")
        XCTAssertEqual(parsed.events.map(\.character), Array("hello the "))
        XCTAssertEqual(AnkyDuration.durationMs(parsed), 240)
        XCTAssertFalse(writer.text.contains("teh"))
    }

    func testReplaceSuffixAfterResumeDoesNotStoreIdleGap() throws {
        var writer = AnkyWriter()

        writer.accept("a", at: 1_770_000_000_000)
        writer.prepareToResume(at: 1_770_000_090_000)

        let accepted = writer.replaceSuffix(
            keepingPrefixCharacterCount: 1,
            with: "b",
            at: 1_770_000_090_000
        )

        XCTAssertEqual(accepted, ["b"])
        let parsed = try AnkyParser.parse(writer.text)
        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "ab")
        XCTAssertEqual(parsed.events, [
            AnkyEvent(deltaMs: 0, character: "a"),
            AnkyEvent(deltaMs: 0, character: "b")
        ])
        XCTAssertEqual(AnkyDuration.durationMs(parsed), 0)
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
