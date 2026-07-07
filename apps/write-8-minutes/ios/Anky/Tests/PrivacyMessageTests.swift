import XCTest
@testable import AnkyCore

final class PrivacyMessageTests: XCTestCase {
    func testPrivacyLockDisclosureTogglesExpandedState() {
        var disclosure = PrivacyLockDisclosure()

        XCTAssertFalse(disclosure.isExpanded)
        disclosure.toggle()
        XCTAssertTrue(disclosure.isExpanded)
        disclosure.toggle()
        XCTAssertFalse(disclosure.isExpanded)
    }
}
