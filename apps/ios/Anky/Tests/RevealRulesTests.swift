import XCTest
@testable import AnkyCore

final class RevealRulesTests: XCTestCase {
    func testFragmentDoesNotShowAskAnky() {
        XCTAssertFalse(MirrorEligibility.canAskAnky(isComplete: false, hasReflection: false))
    }

    func testCompleteShowsAskAnkyWhenNoReflectionExists() {
        XCTAssertTrue(MirrorEligibility.canAskAnky(isComplete: true, hasReflection: false))
    }

    func testCompleteDoesNotShowAskAnkyWhenReflectionExists() {
        XCTAssertFalse(MirrorEligibility.canAskAnky(isComplete: true, hasReflection: true))
    }
}
