import XCTest
@testable import AnkyCore

final class RevealRulesTests: XCTestCase {
    func testFragmentCanAskAnkyWhenNoReflectionExists() {
        XCTAssertTrue(MirrorEligibility.canAskAnky(isComplete: false, hasReflection: false))
    }

    func testCompleteShowsAskAnkyWhenNoReflectionExists() {
        XCTAssertTrue(MirrorEligibility.canAskAnky(isComplete: true, hasReflection: false))
    }

    func testCompleteDoesNotShowAskAnkyWhenReflectionExists() {
        XCTAssertFalse(MirrorEligibility.canAskAnky(isComplete: true, hasReflection: true))
    }

    func testReflectionPromptCopiesMasterPromptWithReconstructedWriting() {
        let prompt = AnkyReflectionPrompt.build(from: "dear diary")

        XCTAssertTrue(prompt.hasPrefix("Take a look at this stream-of-consciousness journal entry."))
        XCTAssertTrue(prompt.contains("Reply with pure markdown"))
        XCTAssertTrue(prompt.contains("---\n\ndear diary"))
    }
}
