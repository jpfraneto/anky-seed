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
        XCTAssertEqual(AnkyDuration.durationMs(parsed), 8042)
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
}
