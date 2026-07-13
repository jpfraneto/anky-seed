import XCTest
@testable import AnkyCore

/// The explicit gate off-switch (2026-07-06): while the gate is off, no
/// reconcile or relock path may re-arm the shield — a foreground after the
/// off-switch leaves the shield down.
final class GateSwitchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "gate-switch-tests-\(UUID().uuidString)")!
    }

    func testGateSwitchStorePersistsAcrossInstances() {
        let defaults = freshDefaults()
        XCTAssertFalse(WriteBeforeScrollGateSwitchStore(defaults: defaults).isGateOff, "gate defaults to on")
        WriteBeforeScrollGateSwitchStore(defaults: defaults).setGateOff(true)
        XCTAssertTrue(WriteBeforeScrollGateSwitchStore(defaults: defaults).isGateOff, "extensions read the same flag")
        WriteBeforeScrollGateSwitchStore(defaults: defaults).setGateOff(false)
        XCTAssertFalse(WriteBeforeScrollGateSwitchStore(defaults: defaults).isGateOff)
    }

    func testForegroundReconcileWhileGateOffClearsInsteadOfArming() {
        // The exact regression the audit named: reconcileShield re-armed on
        // every foreground. With the gate off, the only legal move is clear
        // — even for a locked state that would otherwise re-shield.
        let lockedState = WriteBeforeScrollScreenTimeState(
            selectedApplicationCount: 3,
            shieldActive: false,
            updatedAt: now
        )
        XCTAssertEqual(
            WriteBeforeScrollShieldReconciler.decision(gateOff: true, state: lockedState, at: now),
            .clearShield
        )
    }

    func testReconcileWhileGateOnKeepsExistingBehavior() {
        let lockedState = WriteBeforeScrollScreenTimeState(
            selectedApplicationCount: 3,
            shieldActive: false,
            updatedAt: now
        )
        XCTAssertEqual(
            WriteBeforeScrollShieldReconciler.decision(gateOff: false, state: lockedState, at: now),
            .applyShield
        )

        var unlockedState = lockedState
        unlockedState.unlockedUntil = now.addingTimeInterval(600)
        XCTAssertEqual(
            WriteBeforeScrollShieldReconciler.decision(gateOff: false, state: unlockedState, at: now),
            .clearShield,
            "an active unlock still clears, as before"
        )
    }

    func testGateOffOutranksAnActiveUnlockWindow() {
        var state = WriteBeforeScrollScreenTimeState(selectedApplicationCount: 3, updatedAt: now)
        state.unlockedUntil = now.addingTimeInterval(-60)
        XCTAssertEqual(
            WriteBeforeScrollShieldReconciler.decision(gateOff: true, state: state, at: now),
            .clearShield,
            "an expired unlock (the relock moment) must not re-arm while the gate is off"
        )
    }
}
