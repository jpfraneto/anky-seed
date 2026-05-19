import XCTest
@testable import AnkyCore

final class PrivacyMessageTests: XCTestCase {
    func testFreeCreditMessageIncludesOnlyAllowedFields() {
        let message = FreeCreditMessage.make(publicKey: "PUBLIC_KEY", appVersion: "0.1 1")

        XCTAssertTrue(message.contains("PUBLIC_KEY"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("public identity"))
        XCTAssertTrue(message.contains("platform: ios"))
        XCTAssertTrue(message.contains("app version: 0.1 1"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains(".anky"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("dear diary"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("Here is what I saw"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("seed"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("private key"))
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
