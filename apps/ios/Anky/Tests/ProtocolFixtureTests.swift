import XCTest
@testable import AnkyProtocol

final class ProtocolFixtureTests: XCTestCase {
    // These tiny fixtures are copied from protocol/fixtures for now.
    // Later, wire Xcode/SwiftPM to load the shared fixture files directly.
    private let validFragment = """
    1770000000000 h
    0042 e
    0091 l
    0035 l
    0048 o
    """

    private let validComplete = """
    1770000000000 h
    100000 e
    100000 l
    100000 l
    100000 o
    72000 !
    8000
    """

    func testValidatesAndReconstructsFragmentFixture() throws {
        let validation = AnkyValidator.validate(validFragment)

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.kind, .fragment)
        XCTAssertFalse(validation.isComplete)
        XCTAssertEqual(validation.durationMs, 216)

        let parsed = try XCTUnwrap(validation.parsed)
        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "hello")
    }

    func testValidatesAndReconstructsCompleteFixture() throws {
        let validation = AnkyValidator.validate(validComplete)

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.kind, .complete)
        XCTAssertTrue(validation.isComplete)
        XCTAssertEqual(validation.durationMs, 480000)

        let parsed = try XCTUnwrap(validation.parsed)
        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "hello!")
    }
}
