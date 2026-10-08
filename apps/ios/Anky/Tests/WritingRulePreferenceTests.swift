import XCTest
@testable import AnkyCore

/// The two switches the writing surface can flip on the writer's behalf — the
/// 8 second rule and the ∞ duration — must never change what an older install
/// already meant.
final class WritingRulePreferenceTests: XCTestCase {
    func testPreferencesWrittenBeforeTheRuleWasSwitchableKeepTheirMeaning() throws {
        let legacy = Data("""
        {
          "backspaceAllowed": false,
          "autocorrectEnabled": true,
          "fontChoice": "quill",
          "textSize": "medium",
          "terminalSilenceMs": 8000
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(WritingPreferences.self, from: legacy)

        // The rule was always in force, and every session was a finite one.
        XCTAssertTrue(decoded.eightSecondRuleEnabled)
        XCTAssertFalse(decoded.durationIsInfinite)
        XCTAssertFalse(decoded.backspaceAllowed)
        XCTAssertEqual(decoded.effectiveTerminalSilenceMs, 8000)
    }

    func testRitualDefaultKeepsTheRuleAndAFiniteDuration() {
        XCTAssertTrue(WritingPreferences.ritualDefault.eightSecondRuleEnabled)
        XCTAssertFalse(WritingPreferences.ritualDefault.durationIsInfinite)
        XCTAssertFalse(WritingPreferences.ritualDefault.backspaceAllowed)
    }

    func testRetiredRuleAndInfiniteDurationSurviveARoundTrip() throws {
        var preferences = WritingPreferences.ritualDefault
        preferences.eightSecondRuleEnabled = false
        preferences.durationIsInfinite = true
        preferences.backspaceAllowed = true

        let restored = try JSONDecoder().decode(
            WritingPreferences.self,
            from: try JSONEncoder().encode(preferences)
        )

        XCTAssertFalse(restored.eightSecondRuleEnabled)
        XCTAssertTrue(restored.durationIsInfinite)
        XCTAssertTrue(restored.backspaceAllowed)
    }

    func testStoreRoundTripsTheNewSwitches() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WritingPreferencesStore(defaults: defaults)

        XCTAssertTrue(store.load().eightSecondRuleEnabled)

        store.update { $0.eightSecondRuleEnabled = false }
        XCTAssertFalse(store.load().eightSecondRuleEnabled)

        store.update { $0.durationIsInfinite = true }
        XCTAssertTrue(store.load().durationIsInfinite)
        XCTAssertFalse(store.load().eightSecondRuleEnabled)
    }
}
