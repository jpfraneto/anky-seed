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

        XCTAssertEqual(state, .freeGift(1))
        XCTAssertEqual(ReflectionCreditPresentation.message(for: state), "1 reflection available on this device")
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

    func testClaimedFreeCreditWithoutLoadedBalanceStartsUnavailable() {
        let unavailable = ReflectionCreditPresentation.state(
            creditsRemaining: nil,
            hasClaimedFreeCredits: true
        )

        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertEqual(ReflectionCreditPresentation.message(for: unavailable), "No reflections left")
    }

    func testReflectionCreditCacheStoresAccountScopedBalanceAndClaimedState() {
        let defaults = UserDefaults(suiteName: "RevealRulesTests.creditCache.\(UUID().uuidString)")!
        defer {
            ReflectionCreditCache.clear(defaults: defaults)
        }

        XCTAssertNil(ReflectionCreditCache.balance(accountId: "account-a", defaults: defaults))
        XCTAssertFalse(ReflectionCreditCache.hasClaimedFreeCredits(accountId: "account-a", defaults: defaults))

        ReflectionCreditCache.storeBalance(0, accountId: "account-a", defaults: defaults)
        ReflectionCreditCache.markFreeCreditsClaimed(accountId: "account-a", defaults: defaults)

        XCTAssertEqual(ReflectionCreditCache.balance(accountId: "account-a", defaults: defaults), 0)
        XCTAssertTrue(ReflectionCreditCache.hasClaimedFreeCredits(accountId: "account-a", defaults: defaults))
        XCTAssertNil(ReflectionCreditCache.balance(accountId: "account-b", defaults: defaults))
        XCTAssertTrue(ReflectionCreditCache.hasClaimedFreeCredits(accountId: "account-b", defaults: defaults))
    }
}
