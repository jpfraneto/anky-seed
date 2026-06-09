import XCTest
@testable import AnkyProtocol

final class ReconstructionTests: XCTestCase {
    func testParserKeepsCanonicalSpaceToken() throws {
        let parsed = try AnkyParser.parse("1770000000000 h\n0042 SPACE\n8000")

        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "h ")
    }

    func testParserRejectsLiteralTrailingSpacePayload() {
        XCTAssertThrowsError(try AnkyParser.parse("1770000000000 h\n0042  \n8000")) { error in
            XCTAssertEqual(error as? AnkyParseError, .nonCanonicalSpace)
        }
    }

    func testFragmentAndCompleteDurationBoundaries() throws {
        let fragment = try AnkyParser.parse("""
        1770000000000 a
        479999 b
        """)

        let complete = try AnkyParser.parse("""
        1770000000000 a
        480000 b
        """)

        XCTAssertEqual(AnkyDuration.writingDurationMs(fragment), 479999)
        XCTAssertEqual(AnkyDuration.durationMs(fragment), 479999)
        XCTAssertFalse(AnkyDuration.isComplete(fragment))

        XCTAssertEqual(AnkyDuration.writingDurationMs(complete), 480000)
        XCTAssertEqual(AnkyDuration.durationMs(complete), 480000)
        XCTAssertTrue(AnkyDuration.isComplete(complete))
    }

    func testTerminalSilenceDoesNotMakeAFragmentComplete() throws {
        let parsed = try AnkyParser.parse("""
        1770000000000 a
        472000 b
        8000
        """)

        XCTAssertEqual(AnkyDuration.writingDurationMs(parsed), 472000)
        XCTAssertEqual(AnkyDuration.durationMs(parsed), 472000)
        XCTAssertFalse(AnkyDuration.isComplete(parsed))
    }

    func testHashIsStableForExactBytes() {
        let text = "1770000000000 h\n0042 e\n"
        let data = Data(text.utf8)

        XCTAssertEqual(AnkyHasher.sha256Hex(text), AnkyHasher.sha256Hex(data))
        XCTAssertEqual(AnkyHasher.sha256Hex(text).count, 64)
        XCTAssertNotEqual(
            AnkyHasher.sha256Hex(text),
            AnkyHasher.sha256Hex(text.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }
}
