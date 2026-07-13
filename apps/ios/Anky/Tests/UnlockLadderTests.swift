import XCTest
@testable import AnkyCore

/// The per-keystroke unlock ladder resolution (Fixes 3 and 4 of the
/// 2026-07-06 pre-submission audit): the Daily Unlock is never discarded
/// because a Quick Pass already opened the shield, and organic sessions
/// never surface or spend a Quick Pass.
final class UnlockLadderTests: XCTestCase {
    private let ladder = WriteBeforeScrollUnlockLadder()
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func quickGrant(startingAt grantedAt: Date) -> UnlockGrant {
        UnlockGrant(
            tier: .quick,
            unlockedUntil: grantedAt.addingTimeInterval(UnlockPolicy.quickPassUnlockSeconds),
            grantedAt: grantedAt
        )
    }

    private func dailyGrant(at grantedAt: Date) -> UnlockGrant {
        UnlockGrant(
            tier: .daily,
            unlockedUntil: grantedAt.addingTimeInterval(6 * 60 * 60),
            grantedAt: grantedAt
        )
    }

    private var lockedState: UnlockState {
        UnlockState(grant: nil, lastWroteAt: nil)
    }

    private var activeQuickPassState: UnlockState {
        UnlockState(grant: quickGrant(startingAt: now.addingTimeInterval(-60)), lastWroteAt: now)
    }

    private var expiredQuickPassState: UnlockState {
        UnlockState(
            grant: quickGrant(startingAt: now.addingTimeInterval(-UnlockPolicy.quickPassUnlockSeconds - 120)),
            lastWroteAt: now
        )
    }

    // MARK: The daily unlock applies the moment the target is crossed
    // (feedback 2026-07-08 — never "stop to unlock")

    func testDailyGrantAppliesOnTheSpotWhileLocked() {
        let grant = dailyGrant(at: now)
        let action = ladder.action(
            grant: grant,
            unlockState: lockedState,
            isGateOriginatedSession: true,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            at: now
        )
        XCTAssertEqual(action, .upgradeToDaily(grant), "crossing the target opens the day mid-keystroke")
    }

    func testDailyGrantUpgradesInPlaceWhileQuickPassIsActive() {
        let grant = dailyGrant(at: now)
        let action = ladder.action(
            grant: grant,
            unlockState: activeQuickPassState,
            isGateOriginatedSession: true,
            hasAppliedPassiveQuickUnlock: true,
            hasAppliedDailyUnlockUpgrade: false,
            at: now
        )
        XCTAssertEqual(action, .upgradeToDaily(grant))
    }

    func testDailyGrantAppliesWhenQuickPassExpiredMidSession() {
        // The 15-minute window lapsed while the writer kept going: the
        // target crossing must reopen the day immediately, not at seal —
        // this was the "I finished writing and NOW my apps are locked"
        // inversion.
        let grant = dailyGrant(at: now)
        let action = ladder.action(
            grant: grant,
            unlockState: expiredQuickPassState,
            isGateOriginatedSession: true,
            hasAppliedPassiveQuickUnlock: true,
            hasAppliedDailyUnlockUpgrade: false,
            at: now
        )
        XCTAssertEqual(action, .upgradeToDaily(grant))
    }

    func testDailyUpgradeIsIdempotentWithinASession() {
        let grant = dailyGrant(at: now)
        let action = ladder.action(
            grant: grant,
            unlockState: activeQuickPassState,
            isGateOriginatedSession: true,
            hasAppliedPassiveQuickUnlock: true,
            hasAppliedDailyUnlockUpgrade: true,
            at: now
        )
        XCTAssertEqual(action, .offer(grant), "a second crossing must not re-apply the upgrade")
    }

    func testDailyUpgradeIsIdempotentAcrossSessionsInOneDay() {
        // Second session of the day: the daily unlock is already active.
        let grant = dailyGrant(at: now)
        let dailyUnlockedState = UnlockState(
            grant: dailyGrant(at: now.addingTimeInterval(-3_600)),
            lastWroteAt: now
        )
        let action = ladder.action(
            grant: grant,
            unlockState: dailyUnlockedState,
            isGateOriginatedSession: false,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            at: now
        )
        XCTAssertEqual(action, .offer(grant), "an active daily unlock is never upgraded again")
    }

    // MARK: Fix 4 — organic sessions never surface or spend a Quick Pass

    func testOrganicSessionWithdrawsQuickGrantWhileLocked() {
        let action = ladder.action(
            grant: quickGrant(startingAt: now),
            unlockState: lockedState,
            isGateOriginatedSession: false,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            at: now
        )
        XCTAssertEqual(action, .withdraw, "an organic session must not trigger the passive pass spend")
    }

    func testOrganicSessionWithdrawsQuickGrantWhileUnlocked() {
        let action = ladder.action(
            grant: quickGrant(startingAt: now),
            unlockState: activeQuickPassState,
            isGateOriginatedSession: false,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            at: now
        )
        XCTAssertEqual(action, .withdraw)
    }

    func testOrganicSessionStillEarnsTheDailyUnlock() {
        // Organic writing counts toward the daily target; only Quick Passes
        // are gate-exclusive. The daily unlock applies on the spot here too.
        let grant = dailyGrant(at: now)
        let action = ladder.action(
            grant: grant,
            unlockState: lockedState,
            isGateOriginatedSession: false,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            at: now
        )
        XCTAssertEqual(action, .upgradeToDaily(grant))
    }

    func testGateSessionAppliesQuickPassPassively() {
        let grant = quickGrant(startingAt: now)
        let action = ladder.action(
            grant: grant,
            unlockState: lockedState,
            isGateOriginatedSession: true,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            at: now
        )
        XCTAssertEqual(action, .applyQuickPassively(grant))
    }

    func testGateSessionNeverAppliesQuickPassTwice() {
        let grant = quickGrant(startingAt: now)
        let action = ladder.action(
            grant: grant,
            unlockState: expiredQuickPassState,
            isGateOriginatedSession: true,
            hasAppliedPassiveQuickUnlock: true,
            hasAppliedDailyUnlockUpgrade: false,
            at: now
        )
        XCTAssertEqual(action, .offer(grant), "a re-earned quick grant is offered, never auto-spent again")
    }

    func testNoGrantWithdraws() {
        let action = ladder.action(
            grant: nil,
            unlockState: lockedState,
            isGateOriginatedSession: true,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            at: now
        )
        XCTAssertEqual(action, .withdraw)
    }
}

/// The free-tier target moment (decision 2026-07-06, option C): a free or
/// lapsed writer's target crossing surfaces the moment screen once per day;
/// subscriber behavior is untouched.
extension UnlockLadderTests {
    func testFreeWriterAtTargetGetsTheMomentScreen() {
        let action = ladder.action(
            grant: nil,
            unlockState: lockedState,
            isGateOriginatedSession: false,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            dailyUnlockEntitled: false,
            hasReachedDailyTarget: true,
            hasOfferedFreeTargetMoment: false,
            at: now
        )
        XCTAssertEqual(action, .offerFreeTargetMoment)
    }

    func testFreeWriterAtTargetWithActiveQuickPassStillGetsTheMoment() {
        // The common shape: gate session, pass applied at ~6 words, target
        // crossed minutes later while the window is open.
        let action = ladder.action(
            grant: quickGrant(startingAt: now),
            unlockState: activeQuickPassState,
            isGateOriginatedSession: true,
            hasAppliedPassiveQuickUnlock: true,
            hasAppliedDailyUnlockUpgrade: false,
            dailyUnlockEntitled: false,
            hasReachedDailyTarget: true,
            hasOfferedFreeTargetMoment: false,
            at: now
        )
        XCTAssertEqual(action, .offerFreeTargetMoment)
    }

    func testSubscriberAtTargetIsUnchangedByTheMomentBranch() {
        // Entitled + reached target: the daily unlock applies on the spot,
        // whatever the moment flags say.
        let grant = dailyGrant(at: now)
        let upgraded = ladder.action(
            grant: grant,
            unlockState: activeQuickPassState,
            isGateOriginatedSession: true,
            hasAppliedPassiveQuickUnlock: true,
            hasAppliedDailyUnlockUpgrade: false,
            dailyUnlockEntitled: true,
            hasReachedDailyTarget: true,
            hasOfferedFreeTargetMoment: false,
            at: now
        )
        XCTAssertEqual(upgraded, .upgradeToDaily(grant))

        let applied = ladder.action(
            grant: grant,
            unlockState: lockedState,
            isGateOriginatedSession: false,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            dailyUnlockEntitled: true,
            hasReachedDailyTarget: true,
            hasOfferedFreeTargetMoment: false,
            at: now
        )
        XCTAssertEqual(applied, .upgradeToDaily(grant))
    }

    func testFreeWriterSecondCrossingSameDayShowsNoRepeat() {
        // hasOfferedFreeTargetMoment carries both the session flag and the
        // once-per-day ledger — either suppresses a repeat.
        let action = ladder.action(
            grant: nil,
            unlockState: lockedState,
            isGateOriginatedSession: false,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            dailyUnlockEntitled: false,
            hasReachedDailyTarget: true,
            hasOfferedFreeTargetMoment: true,
            at: now
        )
        XCTAssertEqual(action, .withdraw)
    }

    func testLapsedWriterIsTreatedAsFree() {
        // A lapse narrows dailyUnlockEntitled to false — the same flag the
        // moment branch reads, so lapsed and never-subscribed are identical.
        let action = ladder.action(
            grant: quickGrant(startingAt: now),
            unlockState: activeQuickPassState,
            isGateOriginatedSession: true,
            hasAppliedPassiveQuickUnlock: true,
            hasAppliedDailyUnlockUpgrade: false,
            dailyUnlockEntitled: false,
            hasReachedDailyTarget: true,
            hasOfferedFreeTargetMoment: false,
            at: now
        )
        XCTAssertEqual(action, .offerFreeTargetMoment)
    }

    func testFreeWriterBelowTargetNeverSeesTheMoment() {
        let action = ladder.action(
            grant: nil,
            unlockState: lockedState,
            isGateOriginatedSession: false,
            hasAppliedPassiveQuickUnlock: false,
            hasAppliedDailyUnlockUpgrade: false,
            dailyUnlockEntitled: false,
            hasReachedDailyTarget: false,
            hasOfferedFreeTargetMoment: false,
            at: now
        )
        XCTAssertEqual(action, .withdraw)
    }

    func testFreeTargetMomentLedgerIsOncePerDay() {
        let defaults = UserDefaults(suiteName: "unlock-ladder-tests-\(UUID().uuidString)")!
        let ledger = FreeTargetMomentLedger(defaults: defaults)
        XCTAssertFalse(ledger.wasShown(on: now))
        ledger.markShown(on: now)
        XCTAssertTrue(ledger.wasShown(on: now))
        XCTAssertTrue(ledger.wasShown(on: now.addingTimeInterval(3_600)))
        XCTAssertFalse(ledger.wasShown(on: now.addingTimeInterval(48 * 3_600)), "a new day starts a new clock")
    }
}
