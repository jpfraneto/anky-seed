import XCTest
@testable import Anky

/// The contextual decisions (in-place completion pass, 2026-08-18): every one
/// of them is binary, at most one stands at a time, and the writing is never
/// touched by the asking.
@MainActor
final class WritingDecisionTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "anky.tests.decisions.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeViewModel() -> WriteViewModel {
        WriteViewModel(preferencesStore: WritingPreferencesStore(defaults: defaults))
    }

    private func startedViewModel() -> WriteViewModel {
        let viewModel = makeViewModel()
        viewModel.accept("h")
        viewModel.accept("i")
        return viewModel
    }

    // MARK: Backspace (spec §2)

    func testNewWritingBeginsWithBackspaceDisabled() {
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.backspaceEnabled)
        XCTAssertNil(viewModel.pendingDecision)
        XCTAssertEqual(viewModel.uiState, .active)
    }

    func testFirstBackspaceAttemptAsksInTheKeyboardsPlace() {
        let viewModel = startedViewModel()

        XCTAssertTrue(viewModel.requestBackspaceDecision())

        XCTAssertEqual(viewModel.pendingDecision, .enableBackspace)
        XCTAssertEqual(viewModel.uiState, .decision(.enableBackspace))
        // The asking never touches the writing.
        XCTAssertEqual(viewModel.displayedText, "hi")
        // ...and the keys are not accepting input behind the question.
        XCTAssertFalse(viewModel.canAcceptInput)
    }

    func testEnablingBackspaceKeepsItOnAndNeverAsksAgain() {
        let viewModel = startedViewModel()
        XCTAssertTrue(viewModel.requestBackspaceDecision())

        viewModel.enableBackspaceFromDecision()

        XCTAssertTrue(viewModel.backspaceEnabled)
        XCTAssertTrue(WritingPreferencesStore(defaults: defaults).load().backspaceAllowed)
        XCTAssertNil(viewModel.pendingDecision)
        XCTAssertEqual(viewModel.uiState, .active)
        XCTAssertFalse(viewModel.requestBackspaceDecision())
    }

    func testKeepingBackspaceDisabledDoesNotAskAgainInTheSameWriting() {
        let viewModel = startedViewModel()
        XCTAssertTrue(viewModel.requestBackspaceDecision())

        viewModel.keepBackspaceDisabled()

        XCTAssertFalse(viewModel.backspaceEnabled)
        XCTAssertNil(viewModel.pendingDecision)
        XCTAssertEqual(viewModel.displayedText, "hi")
        XCTAssertFalse(viewModel.requestBackspaceDecision())
    }

    func testABlankPageNeverAsksAboutBackspace() {
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.requestBackspaceDecision())
        XCTAssertNil(viewModel.pendingDecision)
    }

    // MARK: The 8 second rule (spec §3)

    func testTheRuleIsInForceOnAFreshInstall() {
        XCTAssertTrue(makeViewModel().eightSecondRuleActive)
    }

    func testDisablingTheRuleRetiresItForGoodAndReturnsToWriting() {
        let viewModel = startedViewModel()
        XCTAssertTrue(viewModel.requestBackspaceDecision())
        viewModel.keepBackspaceDisabled()

        viewModel.setEightSecondRuleEnabled(false)

        XCTAssertFalse(viewModel.eightSecondRuleActive)
        XCTAssertFalse(WritingPreferencesStore(defaults: defaults).load().eightSecondRuleEnabled)
        XCTAssertNil(viewModel.pendingDecision)
        XCTAssertNil(viewModel.completedArtifact)
        XCTAssertEqual(viewModel.displayedText, "hi")
    }

    // MARK: The ∞ duration (spec §4)

    func testInfiniteDurationStandsDownTheRule() {
        let viewModel = startedViewModel()

        viewModel.chooseInfiniteDuration()

        XCTAssertTrue(viewModel.durationIsInfinite)
        // Nothing may end an ∞ session but the writer.
        XCTAssertFalse(viewModel.eightSecondRuleActive)
    }

    func testChoosingMinutesLeavesInfiniteBehind() {
        let viewModel = startedViewModel()
        viewModel.chooseInfiniteDuration()

        viewModel.chooseDuration(minutes: 5)

        XCTAssertFalse(viewModel.durationIsInfinite)
        XCTAssertTrue(viewModel.eightSecondRuleActive)
    }

    // MARK: The way out (spec §6)

    func testTheWayOutAsksBeforeItEndsALiveWriting() {
        let viewModel = startedViewModel()

        XCTAssertTrue(viewModel.requestEndWritingDecision())

        XCTAssertEqual(viewModel.pendingDecision, .endWriting)
        XCTAssertEqual(viewModel.displayedText, "hi")
    }

    func testKeepingWritingRestoresTheLiveSurfaceUntouched() {
        let viewModel = startedViewModel()
        XCTAssertTrue(viewModel.requestEndWritingDecision())

        viewModel.keepWritingFromDecision()

        XCTAssertNil(viewModel.pendingDecision)
        XCTAssertEqual(viewModel.uiState, .active)
        XCTAssertTrue(viewModel.canAcceptInput)
        XCTAssertEqual(viewModel.displayedText, "hi")
    }

    func testABlankPageHasNothingToEnd() {
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.requestEndWritingDecision())
        XCTAssertNil(viewModel.pendingDecision)
    }

    func testOnlyOneDecisionEverStands() {
        let viewModel = startedViewModel()
        XCTAssertTrue(viewModel.requestEndWritingDecision())

        // A second question can never stack on the first.
        XCTAssertFalse(viewModel.requestBackspaceDecision())
        XCTAssertEqual(viewModel.pendingDecision, .endWriting)
    }

    // MARK: Immutability of what is already written (spec §10)

    func testAnArchivedWritingCannotBeReopenedForEditing() {
        let viewModel = makeViewModel()
        let archived = SavedAnky(
            url: URL(fileURLWithPath: "/dev/null"),
            hash: "deadbeef",
            text: "1770000000000 h\n250 i\n8000",
            reconstructedText: "hi",
            durationMs: AnkyDuration.completeRitualMs,
            isComplete: true,
            createdAt: Date(timeIntervalSince1970: 1_770_000_000),
            inputStats: .empty
        )

        XCTAssertFalse(viewModel.continueSession(from: archived))
        XCTAssertEqual(viewModel.displayedText, "")
        XCTAssertFalse(viewModel.hasStarted)
    }
}
