import XCTest
@testable import Anky

final class QuoteSanitizerTests: XCTestCase {

    func testStripsLeadingBlockquoteAndWrappingQuotes() {
        XCTAssertEqual(QuoteSanitizer.sanitize("> \"text\""), "text")
    }

    func testNestedWrappersUnwrapUntilStable() {
        XCTAssertEqual(QuoteSanitizer.sanitize("\"> \"nested\"\""), "nested")
    }

    func testStripsCurlyWrappingQuotes() {
        XCTAssertEqual(QuoteSanitizer.sanitize("\u{201C}text\u{201D}"), "text")
        XCTAssertEqual(QuoteSanitizer.sanitize("\u{2018}text\u{2019}"), "text")
    }

    func testInternalQuotesArePreserved() {
        XCTAssertEqual(
            QuoteSanitizer.sanitize("  she said \"hello\" to me \n"),
            "she said \"hello\" to me"
        )
    }

    func testStripsMarkdownTokens() {
        XCTAssertEqual(QuoteSanitizer.sanitize("**bold** and _italic_"), "bold and italic")
        XCTAssertEqual(QuoteSanitizer.sanitize("# heading `code`"), "heading code")
    }

    func testRepeatedBlockquoteCarets() {
        XCTAssertEqual(QuoteSanitizer.sanitize("  >> > deep quote"), "deep quote")
    }

    func testTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(QuoteSanitizer.sanitize("\n\n  breath  \n"), "breath")
    }

    func testEmptyAndQuoteOnlyStringsReturnEmpty() {
        XCTAssertEqual(QuoteSanitizer.sanitize(""), "")
        XCTAssertEqual(QuoteSanitizer.sanitize("\"\""), "")
        XCTAssertEqual(QuoteSanitizer.sanitize("  \u{201C}\u{201D}  "), "")
    }

    func testSanitizeIsDeterministic() {
        let raw = "> \"**The** _same_ input\""
        XCTAssertEqual(QuoteSanitizer.sanitize(raw), QuoteSanitizer.sanitize(raw))
    }

    // MARK: - Clamp (the 350-character card budget)

    func testShortQuotePassesThroughClampUnchanged() {
        XCTAssertEqual(QuoteSanitizer.prepareForCard("short and sweet."), "short and sweet.")
    }

    func testLongQuoteTruncatesAtSentenceBoundary() {
        let sentence = "This sentence is exactly forty characters"
        let long = Array(repeating: sentence + ".", count: 12).joined(separator: " ")
        let clamped = QuoteSanitizer.prepareForCard(long)

        XCTAssertLessThanOrEqual(clamped.count, QuoteSanitizer.cardLimit)
        XCTAssertTrue(clamped.hasSuffix("."))
    }

    func testLongQuoteWithoutSentenceBoundaryGetsEllipsis() {
        let long = Array(repeating: "word", count: 120).joined(separator: " ")
        let clamped = QuoteSanitizer.prepareForCard(long)

        XCTAssertLessThanOrEqual(clamped.count, QuoteSanitizer.cardLimit)
        XCTAssertTrue(clamped.hasSuffix("\u{2026}"))
    }
}
