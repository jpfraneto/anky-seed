import XCTest
@testable import AnkyCore

final class PrivacyMessageTests: XCTestCase {
    func testFreeCreditMessageIncludesOnlyAllowedFields() {
        let accountId = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        let message = FreeCreditMessage.make(accountId: accountId, appVersion: "0.1 1")

        XCTAssertTrue(message.contains(accountId))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("Anky address"))
        XCTAssertTrue(message.contains("platform: ios"))
        XCTAssertTrue(message.contains("app version: 0.1 1"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains(".anky"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("dear diary"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("Here is what I saw"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("seed"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("private key"))
    }

    func testRevenueCatCreditIdentityUsesAccountId() throws {
        let fixture = try AnkyIdentityFixtureLoader.mainnet()
        let identity = try WriterIdentity(
            recoveryPhrase: try RecoveryPhrase(text: fixture.mnemonic),
            chainId: fixture.chainId
        )

        XCTAssertEqual(CreditIdentity.appUserID(for: identity), fixture.accountId)
    }

    func testPrivacyLockDisclosureTogglesExpandedState() {
        var disclosure = PrivacyLockDisclosure()

        XCTAssertFalse(disclosure.isExpanded)
        disclosure.toggle()
        XCTAssertTrue(disclosure.isExpanded)
        disclosure.toggle()
        XCTAssertFalse(disclosure.isExpanded)
    }
}
