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

    func testFirstFreeCreditStateShowsGiftUntilClaimed() {
        let state = ReflectionCreditPresentation.state(
            creditsRemaining: nil,
            hasClaimedFreeCredits: false
        )

        XCTAssertEqual(state, .freeGift(8))
        XCTAssertEqual(ReflectionCreditPresentation.message(for: state), "Anky gives you 8 free reflections")
    }

    func testCreditPromptShowsBalanceAndUnavailableState() {
        let available = ReflectionCreditPresentation.state(
            creditsRemaining: 2,
            hasClaimedFreeCredits: true
        )
        let unavailable = ReflectionCreditPresentation.state(
            creditsRemaining: 0,
            hasClaimedFreeCredits: true
        )

        XCTAssertEqual(available, .available(2))
        XCTAssertEqual(ReflectionCreditPresentation.message(for: available), "You have 2 reflections left")
        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertEqual(ReflectionCreditPresentation.message(for: unavailable), "No reflections left")
    }

    func testUnknownCreditStateDoesNotImplyANetworkCheck() {
        let unknown = ReflectionCreditPresentation.state(
            creditsRemaining: nil,
            hasClaimedFreeCredits: true
        )

        XCTAssertEqual(unknown, .unknown)
        XCTAssertEqual(ReflectionCreditPresentation.message(for: unknown), "Reflection balance updates after mirroring")
    }
}
