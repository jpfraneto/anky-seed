import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class WriteBeforeScrollTests: XCTestCase {
    func testWritingSessionEngineKeepsAnkyWriterProtocolAsPrimitive() throws {
        var engine = WritingSessionEngine()

        XCTAssertEqual(engine.accept("Hi.", at: 1_770_000_000_000), ["H", "i", "."])

        XCTAssertEqual(engine.reconstructedText, "Hi.")
        XCTAssertEqual(engine.protocolText, """
        1770000000000 H
        0 i
        0 .
        """)
        XCTAssertEqual(try AnkyParser.parse(engine.protocolText).events.map(\.character), ["H", "i", "."])
        XCTAssertTrue(engine.snapshot.hasCompletedSentence)
    }

    func testQuickSentenceTriggersOnPunctuationOrWordCount() {
        // Terminal punctuation fires first.
        XCTAssertTrue(UnlockPolicy.hasCompletedQuickSentence(in: "I am here."))
        // ~5-7 words fire without punctuation, whichever comes first.
        XCTAssertTrue(UnlockPolicy.hasCompletedQuickSentence(in: "one two three four five six"))
        // Below both thresholds: not yet.
        XCTAssertFalse(UnlockPolicy.hasCompletedQuickSentence(in: "one two three four five"))
        XCTAssertFalse(UnlockPolicy.hasCompletedQuickSentence(in: "..."))
        // Gibberish passes — the cap is the limiter, not the content.
        XCTAssertTrue(UnlockPolicy.hasCompletedQuickSentence(in: "asdf jkl qwer uiop zxcv bnm"))
    }

    func testWritingSessionEngineIgnoresNewlinesInBatchInput() {
        var engine = WritingSessionEngine()

        XCTAssertEqual(engine.accept("a\nb\rc", at: 1_770_000_000_000), ["a", "b", "c"])

        XCTAssertEqual(engine.reconstructedText, "abc")
    }

    func testWritingSessionEngineExpandsMultiCharacterAppendIntoSyntheticCharacterEvents() throws {
        var engine = WritingSessionEngine()

        _ = engine.accept("a", at: 1_770_000_000_000)
        XCTAssertEqual(engine.accept("xyz", at: 1_770_000_000_090), ["x", "y", "z"])

        XCTAssertEqual(engine.reconstructedText, "axyz")
        XCTAssertEqual(engine.protocolText, """
        1770000000000 a
        30 x
        30 y
        30 z
        """)
        let parsed = try AnkyParser.parse(engine.protocolText)
        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "axyz")
        XCTAssertEqual(AnkyDuration.durationMs(parsed), 90)
    }

    func testWritingSessionEngineUsesSmallestProtocolDeltaForTinyBatchAppendWindow() throws {
        var engine = WritingSessionEngine()

        _ = engine.accept("a", at: 1_770_000_000_000)
        _ = engine.accept("xyz", at: 1_770_000_000_001)

        XCTAssertEqual(engine.protocolText, """
        1770000000000 a
        1 x
        0 y
        0 z
        """)
        XCTAssertEqual(try AnkyParser.parse(engine.protocolText).events, [
            AnkyEvent(deltaMs: 0, character: "a"),
            AnkyEvent(deltaMs: 1, character: "x"),
            AnkyEvent(deltaMs: 0, character: "y"),
            AnkyEvent(deltaMs: 0, character: "z")
        ])
    }

    func testUnlockPolicyGrantsQuickPassForCompletedSentence() throws {
        var engine = WritingSessionEngine()
        _ = engine.accept("One sentence.", at: 1_770_000_000_000)
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        let grant = try XCTUnwrap(UnlockPolicy().grant(for: engine.snapshot, at: now))

        XCTAssertEqual(grant.tier, .quick)
        XCTAssertEqual(grant.tier.displayName, "quick pass")
        XCTAssertEqual(grant.unlockedUntil.timeIntervalSince(now), 15 * 60, accuracy: 0.001)
    }

    func testUnlockPolicyWithholdsQuickPassWhenPassesExhausted() {
        var engine = WritingSessionEngine()
        _ = engine.accept("I am here.", at: 1_770_000_000_000)
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        XCTAssertNil(UnlockPolicy().grant(for: engine.snapshot, at: now, quickPassesRemaining: 0))
    }

    func testUnlockPolicyGrantsDailyUnlockPastTargetEvenWithoutPasses() throws {
        var engine = WritingSessionEngine()
        _ = engine.accept("just letters", at: 1_770_000_000_000)
        _ = engine.accept("b", at: 1_770_000_180_000)
        let now = Date(timeIntervalSince1970: 1_770_000_180)

        let grant = try XCTUnwrap(UnlockPolicy().grant(
            for: engine.snapshot,
            at: now,
            dailyTargetMs: 3 * 60_000,
            quickPassesRemaining: 0
        ))

        XCTAssertEqual(grant.tier, .daily)
    }

    // Phase-3: the Daily Unlock is part of the subscription. A free writer
    // past their target earns a Quick Pass (protection and passes are free
    // forever), never the day.
    func testUnlockPolicyWithholdsDailyUnlockWhenNotEntitled() throws {
        var engine = WritingSessionEngine()
        _ = engine.accept("I wrote all the way to my target today.", at: 1_770_000_000_000)
        _ = engine.accept("b", at: 1_770_000_180_000)
        let now = Date(timeIntervalSince1970: 1_770_000_180)

        let grant = try XCTUnwrap(UnlockPolicy().grant(
            for: engine.snapshot,
            at: now,
            dailyTargetMs: 3 * 60_000,
            dailyUnlockEntitled: false
        ))
        XCTAssertEqual(grant.tier, .quick)

        XCTAssertNil(UnlockPolicy().grant(
            for: engine.snapshot,
            at: now,
            dailyTargetMs: 3 * 60_000,
            quickPassesRemaining: 0,
            dailyUnlockEntitled: false
        ))
    }

    func testFirstGateStoreTracksCompletionAndPaywallHook() throws {
        let suiteName = "firstGateStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FirstGateStore(defaults: defaults)

        XCTAssertFalse(store.hasCompletedFirstGate)
        XCTAssertFalse(store.shouldShowPostFirstGatePaywall)

        store.markFirstGateCompleted()
        XCTAssertTrue(store.hasCompletedFirstGate)
        XCTAssertTrue(store.shouldShowPostFirstGatePaywall)

        store.markPostFirstGatePaywallSeen()
        XCTAssertTrue(store.hasCompletedFirstGate)
        XCTAssertFalse(store.shouldShowPostFirstGatePaywall)
    }

    func testWritingAnchorStorePersistsAndNormalizesLocally() throws {
        let suiteName = "writingAnchorStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WritingAnchorStore(defaults: defaults)

        XCTAssertEqual(store.writerName, "You")
        XCTAssertNil(store.anchorSentence)
        XCTAssertNil(store.anchorReminderLine)

        store.save(writerName: "  JP  ", anchorSentence: " I don't need to disappear right now. ")
        XCTAssertEqual(store.writerName, "JP")
        XCTAssertEqual(store.anchorSentence, "I don't need to disappear right now.")
        XCTAssertEqual(
            store.anchorReminderLine,
            "JP, remember: “I don't need to disappear right now.”"
        )

        store.save(writerName: "   ", anchorSentence: "Stay here.")
        XCTAssertEqual(store.writerName, "You")
        XCTAssertEqual(store.anchorReminderLine, "You, remember: “Stay here.”")

        store.save(writerName: nil, anchorSentence: nil)
        XCTAssertEqual(store.writerName, "You")
        XCTAssertNil(store.anchorSentence)
        XCTAssertNil(store.anchorReminderLine)
    }

    func testSealedSessionContainsExactlyOneTerminalSilenceSentinel() throws {
        var engine = WritingSessionEngine()
        _ = engine.accept("I am here.", at: 1_770_000_000_000)

        engine.closeWithTerminalSilence()

        let sentinelLines = engine.protocolText
            .split(separator: "\n")
            .filter { $0 == "\(AnkyDuration.terminalSilenceMs)" }
        XCTAssertEqual(sentinelLines.count, 1)
        XCTAssertTrue(engine.isClosed)

        let validation = AnkyValidator.validate(engine.protocolText)
        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.parsed?.terminalSilenceMs, AnkyDuration.terminalSilenceMs)
    }

    func testRepeatedSealingDoesNotDuplicateTerminalSilenceSentinel() {
        var engine = WritingSessionEngine()
        _ = engine.accept("I am here.", at: 1_770_000_000_000)

        engine.closeWithTerminalSilence()
        let sealedText = engine.protocolText
        engine.closeWithTerminalSilence()

        XCTAssertEqual(engine.protocolText, sealedText)
        XCTAssertEqual(
            engine.protocolText
                .split(separator: "\n")
                .filter { $0 == "\(AnkyDuration.terminalSilenceMs)" }
                .count,
            1
        )
    }

    func testIncompleteSealedSessionCanBeReopenedForContinuation() throws {
        var engine = WritingSessionEngine()
        _ = engine.accept("I am here.", at: 1_770_000_000_000)
        _ = engine.accept(" Still here.", at: 1_770_000_030_000)
        engine.closeWithTerminalSilence()

        let sealedText = engine.protocolText
        XCTAssertTrue(try WritingSessionEngine(draftText: sealedText).isClosed)

        let reopenedText = LocalAnkyArchive.reopenableDraftText(from: sealedText)
        var reopened = try WritingSessionEngine(draftText: reopenedText)

        XCTAssertFalse(reopened.isClosed)
        XCTAssertEqual(reopened.reconstructedText, "I am here. Still here.")
        XCTAssertEqual(reopened.elapsedMs, 30_000)

        reopened.prepareToResume(at: 1_770_000_040_000)
        _ = reopened.accept(" More.", at: 1_770_000_041_000)
        reopened.closeWithTerminalSilence()

        XCTAssertEqual(
            reopened.protocolText
                .split(separator: "\n")
                .filter { $0 == "\(AnkyDuration.terminalSilenceMs)" }
                .count,
            1
        )
        XCTAssertEqual(reopened.reconstructedText, "I am here. Still here. More.")
    }

    func testUnlockPolicyDoesNotGrantSentenceUnlockForFirstCharacter() {
        var engine = WritingSessionEngine()
        _ = engine.accept("x", at: 1_770_000_000_000)
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        XCTAssertFalse(engine.snapshot.hasCompletedSentence)
        XCTAssertNil(UnlockPolicy().grant(for: engine.snapshot, at: now))
    }

    func testUnlockPolicyGrantsSentenceUnlockOnlyForCompletedSentences() throws {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let policy = UnlockPolicy()

        for text in ["I am here.", "I do not need to disappear right now.", "Why am I opening this?", "Enough!"] {
            var engine = WritingSessionEngine()
            _ = engine.accept(text, at: 1_770_000_000_000)
            let grant = try XCTUnwrap(policy.grant(for: engine.snapshot, at: now), "expected unlock for \(text)")
            XCTAssertEqual(grant.tier, .quick, "expected quick pass for \(text)")
            XCTAssertEqual(grant.unlockedUntil.timeIntervalSince(now), 15 * 60, accuracy: 0.001)
        }

        for text in ["h", "hello", "hello ", ".", "...", "!?", "     .", "I"] {
            var engine = WritingSessionEngine()
            _ = engine.accept(text, at: 1_770_000_000_000)
            XCTAssertFalse(engine.snapshot.hasCompletedSentence, "expected no completed sentence for \(text)")
            XCTAssertNil(policy.grant(for: engine.snapshot, at: now), "expected no unlock for \(text)")
        }
    }

    func testUnlockPolicyGrantsNothingForNonSentenceWritingBelowTarget() {
        var engine = WritingSessionEngine()
        _ = engine.accept("just letters no punctuation", at: 1_770_000_000_000)
        _ = engine.accept("b", at: 1_770_000_088_000)
        let now = Date(timeIntervalSince1970: 1_770_000_088)

        XCTAssertNil(UnlockPolicy().grant(for: engine.snapshot, at: now))
    }

    func testUnlockPolicyCompletedSentenceBelowTargetGrantsQuickPass() throws {
        var engine = WritingSessionEngine()
        _ = engine.accept("I am here.", at: 1_770_000_000_000)
        _ = engine.accept(" And more.", at: 1_770_000_030_000)
        let now = Date(timeIntervalSince1970: 1_770_000_030)

        let grant = try XCTUnwrap(UnlockPolicy().grant(for: engine.snapshot, at: now))

        XCTAssertEqual(grant.tier, .quick)
    }

    func testUnlockPolicyDailyUnlockBeatsQuickPassAtTarget() throws {
        var engine = WritingSessionEngine()
        _ = engine.accept("I am here.", at: 1_770_000_000_000)
        _ = engine.accept("b", at: 1_770_000_120_000)
        let now = Date(timeIntervalSince1970: 1_770_000_120)

        let grant = try XCTUnwrap(UnlockPolicy().grant(
            for: engine.snapshot,
            at: now,
            dailyTargetMs: 2 * 60_000
        ))

        XCTAssertEqual(grant.tier, .daily)
    }

    func testUnlockPolicyGrantsDailyUnlockUntilEndOfLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -4 * 60 * 60) ?? .current
        var engine = WritingSessionEngine()
        _ = engine.accept("a", at: 1_770_000_000_000)
        _ = engine.accept("b", at: 1_770_000_480_000)
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let expectedEndOfDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        )

        let grant = UnlockPolicy(calendar: calendar).grant(for: engine.snapshot, at: now)

        XCTAssertEqual(grant?.tier, .daily)
        XCTAssertEqual(grant?.tier.displayName, "daily unlock")
        XCTAssertEqual(grant?.unlockedUntil, expectedEndOfDay)
    }

    func testUnlockPolicyHonorsCustomDailyTarget() throws {
        var engine = WritingSessionEngine()
        _ = engine.accept("a", at: 1_770_000_000_000)
        _ = engine.accept("b", at: 1_770_000_180_000)
        let now = Date(timeIntervalSince1970: 1_770_000_180)

        let grant = try XCTUnwrap(UnlockPolicy().grant(
            for: engine.snapshot,
            at: now,
            dailyTargetMs: 3 * 60_000
        ))
        XCTAssertEqual(grant.tier, .daily)

        XCTAssertNil(UnlockPolicy().grant(
            for: engine.snapshot,
            at: now,
            dailyTargetMs: 4 * 60_000
        ))
    }

    func testUnlockTierOrdering() {
        XCTAssertLessThan(UnlockTier.quick.unlockRank, UnlockTier.daily.unlockRank)
    }

    func testMetricsTrackerDoesNotMarkSentenceUnlockForSingleCharacter() {
        var engine = WritingSessionEngine()
        var tracker = WriteBeforeScrollSessionMetricTracker()
        let start = Date(timeIntervalSince1970: 1_770_000_000)

        let accepted = engine.accept("h", at: 1_770_000_000_000)
        let update = tracker.recordAcceptedCharacters(
            count: accepted.count,
            snapshot: engine.snapshot,
            at: start
        )

        XCTAssertNil(update.availableGrant)
        XCTAssertNil(update.metrics.firstUnlockTier)
        XCTAssertFalse(update.metrics.hasQuickPassAvailable)
        XCTAssertFalse(update.events.contains(.sentenceUnlockAvailable))
    }

    func testMetricsTrackerMarksSentenceUnlockAfterCompletedSentence() throws {
        var engine = WritingSessionEngine()
        var tracker = WriteBeforeScrollSessionMetricTracker()
        let start = Date(timeIntervalSince1970: 1_770_000_000)

        _ = tracker.recordAcceptedCharacters(
            count: engine.accept("I am here", at: 1_770_000_000_000).count,
            snapshot: engine.snapshot,
            at: start
        )
        XCTAssertFalse(tracker.metrics.hasQuickPassAvailable)

        let update = tracker.recordAcceptedCharacters(
            count: engine.accept(".", at: 1_770_000_002_000).count,
            snapshot: engine.snapshot,
            at: start.addingTimeInterval(2)
        )

        XCTAssertEqual(update.availableGrant?.tier, .quick)
        XCTAssertEqual(update.metrics.firstUnlockTier, .quick)
        XCTAssertTrue(update.metrics.hasQuickPassAvailable)
        XCTAssertTrue(update.events.contains(.sentenceUnlockAvailable))
    }

    func testContinuedWritingAfterUnlockDetection() throws {
        var engine = WritingSessionEngine()
        var tracker = WriteBeforeScrollSessionMetricTracker()
        let start = Date(timeIntervalSince1970: 1_770_000_000)

        let firstBatch = engine.accept("One sentence.", at: 1_770_000_000_000)
        var update = tracker.recordAcceptedCharacters(
            count: firstBatch.count,
            snapshot: engine.snapshot,
            at: start
        )

        XCTAssertEqual(update.availableGrant?.tier, .quick)
        XCTAssertEqual(update.metrics.firstUnlockTier, .quick)
        XCTAssertFalse(update.metrics.continuedWritingAfterUnlockAvailable)
        XCTAssertEqual(update.metrics.charactersAfterUnlockAvailable, 0)

        let nextBatch = engine.accept(" more", at: 1_770_000_005_000)
        update = tracker.recordAcceptedCharacters(
            count: nextBatch.count,
            snapshot: engine.snapshot,
            at: start.addingTimeInterval(5)
        )

        XCTAssertTrue(update.metrics.continuedWritingAfterUnlockAvailable)
        XCTAssertEqual(update.metrics.charactersAfterUnlockAvailable, 5)
        XCTAssertEqual(update.metrics.secondsWritingAfterUnlockAvailable, 5, accuracy: 0.001)
        XCTAssertTrue(update.events.contains(.continuedWritingAfterUnlockAvailable))
    }

    func testExpirationLogicAndForceTransitions() {
        var state = WriteBeforeScrollScreenTimeState(
            selectedApplicationCount: 1,
            shieldActive: true
        )
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let grant = UnlockGrant(
            tier: .quick,
            unlockedUntil: now.addingTimeInterval(60),
            grantedAt: now
        )

        state = WriteBeforeScrollUnlockStateMachine.applyingUnlock(
            tierRawValue: grant.tier.rawValue,
            unlockedUntil: grant.unlockedUntil,
            source: .test,
            to: state
        )

        XCTAssertEqual(state.unlockTierRawValue, UnlockTier.quick.rawValue)
        XCTAssertEqual(state.unlockSourceRawValue, WriteBeforeScrollUnlockSource.test.rawValue)
        XCTAssertFalse(state.shieldActive)
        XCTAssertTrue(state.isUnlocked(at: now.addingTimeInterval(59)))
        XCTAssertFalse(state.isUnlocked(at: now.addingTimeInterval(60)))

        state = WriteBeforeScrollUnlockStateMachine.forcingLock(state, at: now.addingTimeInterval(30))

        XCTAssertNil(state.unlockTierRawValue)
        XCTAssertNil(state.unlockedUntil)
        XCTAssertNil(state.unlockSourceRawValue)
        XCTAssertTrue(state.shieldActive)
        XCTAssertEqual(state.lastRelockedAt, now.addingTimeInterval(30))
    }

    func testMultiCharacterAppendCountsTowardDailyTarget() throws {
        var engine = WritingSessionEngine()
        var tracker = WriteBeforeScrollSessionMetricTracker()
        let now = Date(timeIntervalSince1970: 1_770_000_088)

        let first = engine.accept("a", at: 1_770_000_000_000)
        _ = tracker.recordAcceptedCharacters(
            count: first.count,
            snapshot: engine.snapshot,
            at: Date(timeIntervalSince1970: 1_770_000_000),
            dailyTargetMs: 88_000
        )

        let batch = engine.accept("xyz", at: 1_770_000_088_000)
        let update = tracker.recordAcceptedCharacters(
            count: batch.count,
            snapshot: engine.snapshot,
            at: now,
            dailyTargetMs: 88_000
        )

        XCTAssertEqual(AnkyDuration.durationMs(try AnkyParser.parse(engine.protocolText)), 88_000)
        XCTAssertEqual(update.availableGrant?.tier, .daily)
        XCTAssertTrue(update.metrics.hasDailyUnlockAvailable)
        XCTAssertTrue(update.events.contains(.dailyTargetReached))
        XCTAssertEqual(update.metrics.totalAcceptedCharacters, 4)
    }

    func testMetricsTrackerWithholdsQuickPassWhenPassesExhausted() {
        var engine = WritingSessionEngine()
        var tracker = WriteBeforeScrollSessionMetricTracker()
        let start = Date(timeIntervalSince1970: 1_770_000_000)

        let update = tracker.recordAcceptedCharacters(
            count: engine.accept("I am here.", at: 1_770_000_000_000).count,
            snapshot: engine.snapshot,
            at: start,
            quickPassesRemaining: 0
        )

        XCTAssertNil(update.availableGrant)
        XCTAssertFalse(update.metrics.hasQuickPassAvailable)
        XCTAssertFalse(update.events.contains(.sentenceUnlockAvailable))
    }

    func testUnlockStateStorePersistsGrantAndWroteToday() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UnlockStateStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let grant = UnlockGrant(
            tier: .quick,
            unlockedUntil: now.addingTimeInterval(900),
            grantedAt: now
        )

        store.apply(grant)

        let state = store.load()
        XCTAssertEqual(state.grant, grant)
        XCTAssertTrue(state.isUnlocked(at: now.addingTimeInterval(899)))
        XCTAssertFalse(state.isUnlocked(at: now.addingTimeInterval(900)))
        XCTAssertTrue(state.wroteToday(at: now))
    }

    func testPendingQuickPassStaysUnlockedUntilItStartsOnExit() {
        let earnedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let exitedAt = earnedAt.addingTimeInterval(20 * 60)
        let grant = UnlockGrant(
            tier: .quick,
            unlockedUntil: earnedAt.addingTimeInterval(UnlockPolicy.quickPassUnlockSeconds),
            grantedAt: earnedAt
        )

        let pendingGrant = grant.waitingForExit()
        let pendingState = UnlockState(grant: pendingGrant, lastWroteAt: earnedAt)
        let startedGrant = pendingGrant.startingWindow(at: exitedAt)

        XCTAssertTrue(pendingGrant.startsCountingOnExit)
        XCTAssertTrue(pendingState.isUnlocked(at: exitedAt))
        XCTAssertFalse(startedGrant.startsCountingOnExit)
        XCTAssertEqual(startedGrant.grantedAt, exitedAt)
        XCTAssertEqual(
            startedGrant.unlockedUntil.timeIntervalSince(exitedAt),
            UnlockPolicy.quickPassUnlockSeconds,
            accuracy: 0.001
        )
    }

    func testScreenTimeStateMachineTracksPendingExitStartedQuickPass() {
        var state = WriteBeforeScrollScreenTimeState(
            selectedApplicationCount: 1,
            shieldActive: true
        )
        let earnedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let nominalExpiration = earnedAt.addingTimeInterval(UnlockPolicy.quickPassUnlockSeconds)

        state = WriteBeforeScrollUnlockStateMachine.applyingUnlock(
            tierRawValue: UnlockTier.quick.rawValue,
            unlockedUntil: nominalExpiration,
            startsCountingOnExit: true,
            source: .writing,
            to: state
        )

        XCTAssertFalse(state.shieldActive)
        XCTAssertTrue(state.unlockStartsCountingOnExit)
        XCTAssertTrue(state.isUnlocked(at: nominalExpiration.addingTimeInterval(60)))

        state = WriteBeforeScrollUnlockStateMachine.applyingUnlock(
            tierRawValue: UnlockTier.quick.rawValue,
            unlockedUntil: nominalExpiration,
            startsCountingOnExit: false,
            source: .writing,
            to: state
        )

        XCTAssertFalse(state.unlockStartsCountingOnExit)
        XCTAssertFalse(state.isUnlocked(at: nominalExpiration))
    }

    func testUnlockOfferPolicySuppressesCTAWhileAppsAreUnlocked() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let state = UnlockState(
            grant: UnlockGrant(
                tier: .quick,
                unlockedUntil: now.addingTimeInterval(900),
                grantedAt: now
            ),
            lastWroteAt: now
        )

        XCTAssertFalse(WriteBeforeScrollUnlockOfferPolicy().shouldOfferUnlock(for: state, at: now.addingTimeInterval(60)))
    }

    func testUnlockOfferPolicyAllowsCTAAfterTemporaryUnlockExpires() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let state = UnlockState(
            grant: UnlockGrant(
                tier: .quick,
                unlockedUntil: now.addingTimeInterval(1_800),
                grantedAt: now
            ),
            lastWroteAt: now
        )

        XCTAssertTrue(WriteBeforeScrollUnlockOfferPolicy().shouldOfferUnlock(for: state, at: now.addingTimeInterval(1_801)))
    }

    func testUnlockOfferPolicyAllowsCTAWhenNoUnlockExists() {
        let state = UnlockState(grant: nil, lastWroteAt: nil)

        XCTAssertTrue(WriteBeforeScrollUnlockOfferPolicy().shouldOfferUnlock(for: state, at: Date()))
    }

    func testQuickPassStoreGrantsThreePassesAndTracksNumbers() throws {
        let suiteName = "quickPassTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = QuickPassStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        XCTAssertEqual(store.remainingPasses(now: now), 3)
        XCTAssertEqual(store.consumePass(now: now), 1)
        XCTAssertEqual(store.consumePass(now: now), 2)
        XCTAssertEqual(store.remainingPasses(now: now), 1)
        XCTAssertEqual(store.consumePass(now: now), 3)
        XCTAssertEqual(store.remainingPasses(now: now), 0)
        XCTAssertNil(store.consumePass(now: now))
    }

    func testQuickPassStoreResetsAtLocalMidnight() throws {
        let suiteName = "quickPassResetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = QuickPassStore(defaults: defaults)
        let today = Date(timeIntervalSince1970: 1_770_000_000)
        let tomorrow = today.addingTimeInterval(24 * 60 * 60)

        _ = store.consumePass(now: today)
        _ = store.consumePass(now: today)
        _ = store.consumePass(now: today)
        XCTAssertEqual(store.remainingPasses(now: today), 0)

        XCTAssertEqual(store.remainingPasses(now: tomorrow), 3)
        XCTAssertEqual(store.consumePass(now: tomorrow), 1)
    }

    func testDailyTargetStoreDefaultsToEightMinutes() throws {
        let suiteName = "dailyTargetDefaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DailyTargetStore(defaults: defaults)

        XCTAssertEqual(store.effectiveTargetMinutes(), 8)
        XCTAssertEqual(store.effectiveTargetMs(), 480_000)
    }

    func testDailyTargetStoreInitialSetAppliesImmediatelyAndClamps() throws {
        let suiteName = "dailyTargetInitialTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DailyTargetStore(defaults: defaults)

        store.setInitialTarget(3)
        XCTAssertEqual(store.effectiveTargetMinutes(), 3)

        store.setInitialTarget(0)
        XCTAssertEqual(store.effectiveTargetMinutes(), 1)

        store.setInitialTarget(99)
        XCTAssertEqual(store.effectiveTargetMinutes(), 8)
    }

    func testDailyTargetStoreEditsTakeEffectNextDay() throws {
        let suiteName = "dailyTargetEditTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DailyTargetStore(defaults: defaults)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = utc.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))
            .addingTimeInterval(9 * 3600)
        let laterToday = today.addingTimeInterval(3600)
        let tomorrow = today.addingTimeInterval(24 * 60 * 60)

        store.setInitialTarget(8)
        let change = store.requestTargetChange(to: 3, now: today, calendar: utc)
        XCTAssertEqual(change.oldMinutes, 8)
        XCTAssertEqual(change.newMinutes, 3)

        XCTAssertEqual(store.effectiveTargetMinutes(now: laterToday, calendar: utc), 8, "edit must not apply mid-day")
        XCTAssertEqual(store.pendingTargetMinutes(now: laterToday, calendar: utc), 3)

        XCTAssertEqual(store.effectiveTargetMinutes(now: tomorrow, calendar: utc), 3, "edit applies the next day")
        XCTAssertNil(store.pendingTargetMinutes(now: tomorrow, calendar: utc))
    }

    func testDailyTargetStoreRequestingCurrentValueCancelsPendingChange() throws {
        let suiteName = "dailyTargetCancelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DailyTargetStore(defaults: defaults)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = utc.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))
            .addingTimeInterval(9 * 3600)
        let tomorrow = today.addingTimeInterval(24 * 60 * 60)

        store.setInitialTarget(8)
        store.requestTargetChange(to: 3, now: today, calendar: utc)
        store.requestTargetChange(to: 8, now: today, calendar: utc)

        XCTAssertNil(store.pendingTargetMinutes(now: today, calendar: utc))
        XCTAssertEqual(store.effectiveTargetMinutes(now: tomorrow, calendar: utc), 8)
    }

    func testShieldCopyShowsPassesAndExhaustionFraming() throws {
        let suiteName = "shieldCopyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WriteBeforeScrollLaunchBridgeStore(defaults: defaults)

        let withPasses = store.copy(
            bridgeMode: .notification,
            fallbackState: .initial,
            quickPassesRemaining: 2,
            attemptedAppName: "Instagram"
        )
        XCTAssertTrue(withPasses.subtitle.contains("quick pass — one sentence · 2 left today"))
        XCTAssertTrue(withPasses.subtitle.contains("Instagram is waiting behind the door."))

        let exhausted = store.copy(
            bridgeMode: .notification,
            fallbackState: .initial,
            quickPassesRemaining: 0
        )
        XCTAssertTrue(exhausted.subtitle.contains("I've opened the door three times today. Write with me first."))
        XCTAssertFalse(exhausted.subtitle.contains("left today\n"))

        let gateExhausted = store.copy(
            bridgeMode: .directOpen,
            fallbackState: .initial,
            quickPassesRemaining: 0
        )
        XCTAssertEqual(gateExhausted.title, "I've opened the door three times today. Write with me first.")
    }

    func testBlockedAppSelectionStorePersistsOpaqueSelectionBoundary() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BlockedAppSelectionStore(defaults: defaults)
        let snapshot = BlockedAppSelectionSnapshot(
            encodedSelectionData: Data([1, 2, 3]),
            selectedApplicationCount: 2,
            selectedCategoryCount: 1,
            updatedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
        XCTAssertTrue(try XCTUnwrap(store.load()).hasSelection)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testLaunchBridgeCopyResolver() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WriteBeforeScrollLaunchBridgeStore(defaults: defaults)

        XCTAssertEqual(
            store.copy(bridgeMode: .directOpen, fallbackState: .initial).primaryButton,
            "Write"
        )
        XCTAssertEqual(
            store.copy(bridgeMode: .notification, fallbackState: .initial).primaryButton,
            "Send notification"
        )
        XCTAssertEqual(
            store.copy(bridgeMode: .notification, fallbackState: .notificationSent).primaryButton,
            "Didn't receive the notification? Try again"
        )
        XCTAssertEqual(
            store.copy(bridgeMode: .notification, fallbackState: .notificationsDisabled).title,
            "Open Anky manually"
        )
    }

    func testLaunchBridgeStoreRoundTripNotificationAndConsumed() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WriteBeforeScrollLaunchBridgeStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        let intent = store.savePendingIntent(
            bridgeMode: .notification,
            attemptedAppDisplayName: "X",
            now: now
        )

        XCTAssertEqual(store.loadPendingIntent()?.id, intent.id)
        XCTAssertEqual(store.loadPendingIntent()?.attemptedAppDisplayName, "X")
        XCTAssertEqual(store.currentFallbackShieldState(now: now), .initial)

        store.markNotificationSent(intentID: intent.id, at: now.addingTimeInterval(1))

        let notifiedIntent = try XCTUnwrap(store.loadPendingIntent())
        XCTAssertEqual(notifiedIntent.notificationSentAt, now.addingTimeInterval(1))
        XCTAssertEqual(notifiedIntent.notificationDeliveryCount, 1)
        XCTAssertEqual(store.currentFallbackShieldState(now: now.addingTimeInterval(2)), .notificationSent)
        XCTAssertFalse(store.canSendNotification(for: intent.id, now: now.addingTimeInterval(2)))
        XCTAssertTrue(store.canSendNotification(for: intent.id, now: now.addingTimeInterval(4)))

        store.markConsumed(intentID: intent.id, at: now.addingTimeInterval(5))

        XCTAssertEqual(store.loadPendingIntent()?.consumedAt, now.addingTimeInterval(5))
        XCTAssertFalse(try XCTUnwrap(store.loadPendingIntent()).isFresh(at: now.addingTimeInterval(6)))
    }

    func testLaunchBridgeStoreClearExpiredAndNotificationPermissionState() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WriteBeforeScrollLaunchBridgeStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        _ = store.savePendingIntent(bridgeMode: .notification, now: now)
        store.markNotificationPermissionMissing(at: now.addingTimeInterval(1))

        XCTAssertEqual(store.currentFallbackShieldState(now: now.addingTimeInterval(2)), .notificationsDisabled)

        store.clearExpiredIntents(now: now.addingTimeInterval(WriteBeforeScrollLaunchBridgeStore.intentExpirationSeconds + 1))

        XCTAssertNil(store.loadPendingIntent())
        XCTAssertEqual(store.currentFallbackShieldState(now: now.addingTimeInterval(WriteBeforeScrollLaunchBridgeStore.intentExpirationSeconds + 2)), .initial)
    }

    func testAppRouteResolverUsesFreshPendingIntentOnce() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WriteBeforeScrollLaunchBridgeStore(defaults: defaults)
        let resolver = WriteBeforeScrollAppRouteResolver(bridgeStore: store)
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let intent = store.savePendingIntent(bridgeMode: .notification, now: now)

        XCTAssertEqual(
            resolver.pendingRoute(now: now.addingTimeInterval(1)),
            .writeBeforeScrollFromShield(intentID: intent.id)
        )

        store.markConsumed(intentID: intent.id, at: now.addingTimeInterval(2))

        XCTAssertNil(resolver.pendingRoute(now: now.addingTimeInterval(3)))
    }

    func testAppRouteResolverIgnoresExpiredIntent() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WriteBeforeScrollLaunchBridgeStore(defaults: defaults)
        let resolver = WriteBeforeScrollAppRouteResolver(bridgeStore: store)
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        _ = store.savePendingIntent(bridgeMode: .notification, now: now)

        XCTAssertNil(
            resolver.pendingRoute(
                now: now.addingTimeInterval(WriteBeforeScrollLaunchBridgeStore.intentExpirationSeconds + 1)
            )
        )
    }
}
