import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class SignalStateTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
    }

    // MARK: - Signal percent

    func testSignalPercentGrowsWithStreakAndToday() {
        XCTAssertEqual(SignalCalculator.signalPercent(streakDays: 0, wroteToday: false), 0)
        XCTAssertEqual(SignalCalculator.signalPercent(streakDays: 1, wroteToday: true), 23)
        XCTAssertEqual(SignalCalculator.signalPercent(streakDays: 3, wroteToday: false), 33)
        XCTAssertEqual(SignalCalculator.signalPercent(streakDays: 8, wroteToday: true), 100)
        XCTAssertEqual(SignalCalculator.signalPercent(streakDays: 30, wroteToday: true), 100)
    }

    // MARK: - Streak

    func testStreakDaysCountsConsecutiveWritingDays() {
        XCTAssertEqual(SignalCalculator.streakDays(sessionDays: [], now: now, calendar: calendar), 0)

        XCTAssertEqual(
            SignalCalculator.streakDays(sessionDays: [now], now: now, calendar: calendar),
            1
        )

        XCTAssertEqual(
            SignalCalculator.streakDays(
                sessionDays: [now, daysAgo(1), daysAgo(2)],
                now: now,
                calendar: calendar
            ),
            3
        )
    }

    func testStreakEndingYesterdayStillCounts() {
        XCTAssertEqual(
            SignalCalculator.streakDays(
                sessionDays: [daysAgo(1), daysAgo(2)],
                now: now,
                calendar: calendar
            ),
            2
        )
    }

    func testStreakBrokenByGapResets() {
        XCTAssertEqual(
            SignalCalculator.streakDays(
                sessionDays: [daysAgo(2), daysAgo(3)],
                now: now,
                calendar: calendar
            ),
            0
        )

        XCTAssertEqual(
            SignalCalculator.streakDays(
                sessionDays: [now, daysAgo(2), daysAgo(3)],
                now: now,
                calendar: calendar
            ),
            1
        )
    }

    // MARK: - Snapshot

    func testSnapshotReflectsActiveUnlock() {
        let unlockedUntil = now.addingTimeInterval(15 * 60)
        let screenTimeState = WriteBeforeScrollScreenTimeState(
            selectedApplicationCount: 2,
            unlockTierRawValue: UnlockTier.quick.rawValue,
            unlockedUntil: unlockedUntil,
            shieldActive: false
        )

        let snapshot = SignalCalculator.snapshot(
            screenTimeState: screenTimeState,
            unlockState: UnlockState(grant: nil, lastWroteAt: now),
            events: [],
            sessionDays: [now],
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(snapshot.isGateConfigured)
        XCTAssertTrue(snapshot.isCurrentlyUnlocked)
        XCTAssertEqual(snapshot.unlockExpiresAt, unlockedUntil)
        XCTAssertEqual(snapshot.unlockTier, .quick)
        XCTAssertTrue(snapshot.wroteToday)
        XCTAssertEqual(snapshot.currentStreakDays, 1)
        XCTAssertEqual(snapshot.selectedApplicationCount, 2)
    }

    func testSnapshotExpiredUnlockIsLocked() {
        let screenTimeState = WriteBeforeScrollScreenTimeState(
            selectedApplicationCount: 1,
            unlockTierRawValue: UnlockTier.daily.rawValue,
            unlockedUntil: now.addingTimeInterval(-60),
            shieldActive: true
        )

        let snapshot = SignalCalculator.snapshot(
            screenTimeState: screenTimeState,
            unlockState: UnlockState(grant: nil, lastWroteAt: nil),
            events: [],
            sessionDays: [],
            now: now,
            calendar: calendar
        )

        XCTAssertFalse(snapshot.isCurrentlyUnlocked)
        XCTAssertNil(snapshot.unlockExpiresAt)
        XCTAssertNil(snapshot.unlockTier)
        XCTAssertTrue(snapshot.isShieldActive)
        XCTAssertFalse(snapshot.wroteToday)
        XCTAssertEqual(snapshot.signalPercent, 0)
    }

    func testSnapshotCountsOnlyTodaysUnlockGrantedEvents() {
        let events = [
            WriteBeforeScrollEvent(name: .unlockGranted, timestamp: now),
            WriteBeforeScrollEvent(name: .unlockGranted, timestamp: now.addingTimeInterval(-3600)),
            WriteBeforeScrollEvent(name: .unlockGranted, timestamp: daysAgo(1)),
            WriteBeforeScrollEvent(name: .writingStarted, timestamp: now)
        ]

        let snapshot = SignalCalculator.snapshot(
            screenTimeState: WriteBeforeScrollScreenTimeState(selectedApplicationCount: 1),
            unlockState: UnlockState(grant: nil, lastWroteAt: nil),
            events: events,
            sessionDays: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.gatesCompletedToday, 2)
    }

    func testSnapshotWroteTodayFromSessionDaysAlone() {
        let snapshot = SignalCalculator.snapshot(
            screenTimeState: WriteBeforeScrollScreenTimeState(),
            unlockState: UnlockState(grant: nil, lastWroteAt: nil),
            events: [],
            sessionDays: [now.addingTimeInterval(-120)],
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(snapshot.wroteToday)
        XCTAssertFalse(snapshot.isGateConfigured)
        XCTAssertEqual(snapshot.signalPercent, 23)
    }

    // MARK: - 8-Day Gate progress

    func testEightDayGateProgressStartsOnDayOne() {
        let progress = EightDayGateProgress()
        XCTAssertEqual(progress.currentDayNumber, 1)
        XCTAssertEqual(EightDayGate.title(forDay: progress.currentDayNumber), "Write before one app.")
        XCTAssertFalse(progress.isComplete)
        XCTAssertEqual(progress.completedDayCount, 0)
    }

    func testEightDayGateProgressAdvancesToFirstIncompleteDay() {
        var progress = EightDayGateProgress()
        progress.markCompleted(day: 1, at: now)
        progress.markCompleted(day: 2, at: now)
        progress.markCompleted(day: 4, at: now)

        XCTAssertEqual(progress.currentDayNumber, 3)
        XCTAssertEqual(progress.completedDayCount, 3)
        XCTAssertFalse(progress.isComplete)
    }

    func testEightDayGateCompletionDatesArePermanent() {
        var progress = EightDayGateProgress()
        progress.markCompleted(day: 1, at: now)
        progress.markCompleted(day: 1, at: now.addingTimeInterval(9999))

        XCTAssertEqual(progress.completionDate(for: 1), now)
        XCTAssertEqual(progress.completions.count, 1)
    }

    func testEightDayGateIgnoresInvalidDays() {
        var progress = EightDayGateProgress()
        progress.markCompleted(day: 0, at: now)
        progress.markCompleted(day: 9, at: now)
        XCTAssertEqual(progress.completedDayCount, 0)
    }

    func testEightDayGateStorePersistsAcrossLoads() throws {
        let suiteName = "eightDayGateStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = EightDayGateStore(defaults: defaults)

        store.markCompleted(day: 3, at: now)

        let reloaded = store.load()
        XCTAssertTrue(reloaded.isDayComplete(3))
        XCTAssertEqual(reloaded.completionDate(for: 3), now)
    }

    func testEightDayGateDerivesHonestlyTrackableDays() throws {
        let suiteName = "eightDayGateDeriveTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = EightDayGateStore(defaults: defaults)

        let progress = store.refreshDerivedCompletions(
            hasCompletedFirstGate: true,
            protectedTargetCount: 2,
            hasCompletedDailyUnlock: true,
            hasWrittenPastTarget: false,
            isGateOn: true,
            now: now
        )

        XCTAssertTrue(progress.isDayComplete(1))
        XCTAssertTrue(progress.isDayComplete(2))
        XCTAssertTrue(progress.isDayComplete(3))
        XCTAssertFalse(progress.isDayComplete(4), "archive echo is event-driven, not derived")
        XCTAssertFalse(progress.isDayComplete(5), "morning protection is scaffolded")
        XCTAssertFalse(progress.isDayComplete(6), "share is scaffolded")
        XCTAssertFalse(progress.isDayComplete(7))
        XCTAssertFalse(progress.isDayComplete(8), "requires days 1-7 first")
        XCTAssertEqual(progress.currentDayNumber, 4)
    }

    func testEightDayGateDayEightRequiresAllPriorDaysAndActiveGate() throws {
        let suiteName = "eightDayGateDayEightTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = EightDayGateStore(defaults: defaults)

        store.markCompleted(day: 4, at: now)
        store.markCompleted(day: 5, at: now)
        store.markCompleted(day: 6, at: now)

        let withoutGate = store.refreshDerivedCompletions(
            hasCompletedFirstGate: true,
            protectedTargetCount: 3,
            hasCompletedDailyUnlock: true,
            hasWrittenPastTarget: true,
            isGateOn: false,
            now: now
        )
        XCTAssertTrue(withoutGate.isDayComplete(7))
        XCTAssertFalse(withoutGate.isDayComplete(8))

        let withGate = store.refreshDerivedCompletions(
            hasCompletedFirstGate: true,
            protectedTargetCount: 3,
            hasCompletedDailyUnlock: true,
            hasWrittenPastTarget: true,
            isGateOn: true,
            now: now
        )
        XCTAssertTrue(withGate.isDayComplete(8))
        XCTAssertTrue(withGate.isComplete)
        XCTAssertEqual(withGate.currentDayNumber, 8)
    }

    // MARK: - Shield arrival message

    func testShieldArrivalMessageUsesAnchorWhenAvailable() throws {
        let suiteName = "signalArrivalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WritingAnchorStore(defaults: defaults)

        XCTAssertEqual(
            store.shieldArrivalMessage,
            "Write one true thing before the feed gets in."
        )

        store.save(writerName: "JP", anchorSentence: "I don't need to disappear right now.")
        XCTAssertEqual(
            store.shieldArrivalMessage,
            "JP, remember: “I don't need to disappear right now.”\nWrite one true sentence to unlock."
        )
    }

    // MARK: - Draft restore vs sealed immutability

    func testUnsealedDraftRestoresAndContinues() throws {
        var original = WritingSessionEngine()
        _ = original.accept("I am here", at: 1_770_000_000_000)

        var restored = try WritingSessionEngine(draftText: original.protocolText)
        XCTAssertFalse(restored.isClosed)
        XCTAssertEqual(restored.reconstructedText, "I am here")

        restored.prepareToResume(at: 1_770_000_030_000)
        XCTAssertEqual(restored.accept(".", at: 1_770_000_031_000), ["."])
        XCTAssertEqual(restored.reconstructedText, "I am here.")
    }

    func testSealedArtifactIsImmutable() throws {
        var original = WritingSessionEngine()
        _ = original.accept("I am here.", at: 1_770_000_000_000)
        original.closeWithTerminalSilence()
        let sealedText = original.protocolText

        XCTAssertEqual(original.accept("more", at: 1_770_000_060_000), [])
        XCTAssertEqual(original.protocolText, sealedText)

        var reloaded = try WritingSessionEngine(draftText: sealedText)
        XCTAssertTrue(reloaded.isClosed)
        XCTAssertEqual(reloaded.accept("x", at: 1_770_000_090_000), [])
        XCTAssertEqual(reloaded.protocolText, sealedText)
    }
}
