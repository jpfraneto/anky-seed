import XCTest
@testable import AnkyProtocol

final class ReconstructionTests: XCTestCase {
    func testParserKeepsAcceptedSpaces() throws {
        let parsed = try AnkyParser.parse("1770000000000 h\n0042  \n8000")

        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "h ")
    }

    func testFragmentAndCompleteDurationBoundaries() throws {
        let fragment = try AnkyParser.parse("""
        1770000000000 a
        471999 b
        8000
        """)

        let complete = try AnkyParser.parse("""
        1770000000000 a
        472000 b
        8000
        """)

        XCTAssertEqual(AnkyDuration.writingDurationMs(fragment), 471999)
        XCTAssertEqual(AnkyDuration.durationMs(fragment), 479999)
        XCTAssertFalse(AnkyDuration.isComplete(fragment))

        XCTAssertEqual(AnkyDuration.writingDurationMs(complete), 472000)
        XCTAssertEqual(AnkyDuration.durationMs(complete), 480000)
        XCTAssertTrue(AnkyDuration.isComplete(complete))
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
