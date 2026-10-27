import XCTest
@testable import AnkyCore

final class AccessPolicyTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func inputs(
        at offset: TimeInterval,
        free: FreeAccessRecord?? = nil,
        subscription: SubscriptionStatus = .unknown,
        trusted: Bool = true
    ) -> AccessInputs {
        AccessInputs(
            now: TrustedNow(date: start.addingTimeInterval(offset), isTrusted: trusted),
            freeAccess: free ?? FreeAccessRecord(startedAt: start, confirmedByServer: true),
            subscription: subscription
        )
    }

    // MARK: First use and the seven-day boundary

    func testNothingStartedAllowsFirstSessionAndNotAI() {
        let fresh = inputs(at: 0, free: .some(nil))
        XCTAssertEqual(AccessPolicy.state(fresh), .freeNotStarted)
        XCTAssertEqual(AccessPolicy.decide(.startSession, fresh), .allowed)
        XCTAssertEqual(AccessPolicy.decide(.requestAI, fresh), .denied(.subscriptionRequired))
    }

    func testFreeWindowIsExactlySevenDays() {
        let lastSecond = inputs(at: 7 * day - 1)
        XCTAssertEqual(AccessPolicy.state(lastSecond), .freeActive(endsAt: start.addingTimeInterval(7 * day)))
        XCTAssertEqual(AccessPolicy.decide(.startSession, lastSecond), .allowed)

        let boundary = inputs(at: 7 * day)
        XCTAssertEqual(AccessPolicy.state(boundary), .freeExpired(endedAt: start.addingTimeInterval(7 * day)))
        XCTAssertEqual(AccessPolicy.decide(.startSession, boundary), .denied(.freeAccessComplete))
        XCTAssertEqual(AccessPolicy.decide(.continueWriting, boundary), .denied(.freeAccessComplete))
    }

    func testFreeDaysNeverIncludeAI() {
        for dayIndex in 0..<7 {
            let during = inputs(at: TimeInterval(dayIndex) * day + 60)
            XCTAssertEqual(AccessPolicy.decide(.requestAI, during), .denied(.subscriptionRequired))
        }
        XCTAssertEqual(AccessPolicy.decide(.requestAI, inputs(at: 30 * day)), .denied(.subscriptionRequired))
    }

    // MARK: Memories are never held hostage

    func testReadAndExportAreAllowedInEveryState() {
        let states: [AccessInputs] = [
            inputs(at: 0, free: .some(nil)),
            inputs(at: 2 * day),
            inputs(at: 40 * day),
            inputs(at: 40 * day, trusted: false),
            inputs(at: 40 * day, subscription: .inactive(verifiedAt: start)),
            inputs(at: 40 * day, subscription: .active(verifiedAt: start, expiresAt: start.addingTimeInterval(day))),
            inputs(at: 40 * day, subscription: .active(verifiedAt: start.addingTimeInterval(40 * day), expiresAt: nil))
        ]
        for state in states {
            XCTAssertEqual(AccessPolicy.decide(.readMemories, state), .allowed)
            XCTAssertEqual(AccessPolicy.decide(.exportMemories, state), .allowed)
        }
    }

    // MARK: Subscription

    func testActiveSubscriberCanDoEverything() {
        let now = 30 * day
        let subscriber = inputs(
            at: now,
            subscription: .active(verifiedAt: start.addingTimeInterval(now - 60), expiresAt: start.addingTimeInterval(now + day))
        )
        XCTAssertTrue(AccessPolicy.state(subscriber).isSubscriber)
        XCTAssertEqual(AccessPolicy.decide(.startSession, subscriber), .allowed)
        XCTAssertEqual(AccessPolicy.decide(.requestAI, subscriber), .allowed)
    }

    func testSubscriberDuringFreeDaysGetsAI() {
        let early = inputs(at: day, subscription: .active(verifiedAt: start.addingTimeInterval(day), expiresAt: nil))
        XCTAssertEqual(AccessPolicy.state(early), .subscriber(expiresAt: nil))
        XCTAssertEqual(AccessPolicy.decide(.requestAI, early), .allowed)
    }

    func testCancelledSubscriptionStopsAtExpiry() {
        let expiry = start.addingTimeInterval(20 * day)
        let verified = start.addingTimeInterval(19 * day)
        let before = inputs(at: 20 * day - 60, subscription: .active(verifiedAt: verified, expiresAt: expiry))
        XCTAssertEqual(AccessPolicy.decide(.startSession, before), .allowed)

        // Past the known expiry but not re-checked yet (offline): it may have
        // renewed, so Anky asks to verify instead of declaring it over.
        let unchecked = inputs(at: 20 * day + 60, subscription: .active(verifiedAt: verified, expiresAt: expiry))
        XCTAssertEqual(AccessPolicy.decide(.startSession, unchecked), .denied(.needsVerification))
        XCTAssertEqual(AccessPolicy.decide(.requestAI, unchecked), .denied(.subscriptionRequired))

        // RevenueCat confirms it did not renew.
        let confirmed = inputs(at: 20 * day + 120, subscription: .inactive(verifiedAt: start.addingTimeInterval(20 * day + 100)))
        XCTAssertEqual(AccessPolicy.decide(.startSession, confirmed), .denied(.freeAccessComplete))
    }

    func testVerifiedInactiveAfterFreeDaysIsComplete() {
        let lapsed = inputs(at: 10 * day, subscription: .inactive(verifiedAt: start.addingTimeInterval(10 * day)))
        XCTAssertEqual(AccessPolicy.state(lapsed), .freeExpired(endedAt: start.addingTimeInterval(7 * day)))
    }

    // MARK: Offline and uncertainty

    func testCachedSubscriptionWorksOfflineWithinBound() {
        let verified = start.addingTimeInterval(10 * day)
        let sixDaysOffline = inputs(at: 16 * day, subscription: .active(verifiedAt: verified, expiresAt: nil))
        XCTAssertEqual(AccessPolicy.decide(.startSession, sixDaysOffline), .allowed)
    }

    func testStaleSubscriptionBecomesUnverifiedNotExpired() {
        let verified = start.addingTimeInterval(10 * day)
        let longOffline = inputs(at: 18 * day, subscription: .active(verifiedAt: verified, expiresAt: nil))
        XCTAssertEqual(AccessPolicy.state(longOffline), .unverified(lastKnownEnd: start.addingTimeInterval(7 * day)))
        XCTAssertEqual(AccessPolicy.decide(.startSession, longOffline), .denied(.needsVerification))
        XCTAssertEqual(AccessPolicy.decide(.requestAI, longOffline), .denied(.subscriptionRequired))
        XCTAssertEqual(AccessPolicy.decide(.readMemories, longOffline), .allowed)
    }

    func testUnknownSubscriptionDuringFreeDaysStillAllowsExpression() {
        let unknown = inputs(at: 3 * day, subscription: .unknown)
        XCTAssertEqual(AccessPolicy.decide(.startSession, unknown), .allowed)
    }

    // MARK: Clock manipulation

    func testRewoundClockCannotReopenFreeDays() {
        // The trusted clock reports "not trusted" when the device clock is
        // behind the high-water mark; the policy refuses to decide in favour.
        let rewound = inputs(at: 2 * day, trusted: false)
        XCTAssertEqual(AccessPolicy.state(rewound), .unverified(lastKnownEnd: start.addingTimeInterval(7 * day)))
        XCTAssertEqual(AccessPolicy.decide(.startSession, rewound), .denied(.needsVerification))
    }

    func testRewoundClockDoesNotBlockSubscriber() {
        let rewound = inputs(
            at: 30 * day,
            subscription: .active(verifiedAt: start.addingTimeInterval(30 * day), expiresAt: nil),
            trusted: false
        )
        XCTAssertEqual(AccessPolicy.decide(.startSession, rewound), .allowed)
    }

    // MARK: A session that crosses the end of access

    func testOpenSessionCanBeFinishedAfterFreeDaysEnd() {
        let sessionStart = start.addingTimeInterval(7 * day - 30 * 60)
        let tenMinutesAfterEnd = inputs(at: 7 * day + 10 * 60)
        XCTAssertEqual(AccessPolicy.decide(.newSegment(sessionStartedAt: sessionStart), tenMinutesAfterEnd), .allowed)
        // …but a new session is not.
        XCTAssertEqual(AccessPolicy.decide(.startSession, tenMinutesAfterEnd), .denied(.freeAccessComplete))
    }

    func testOpenSessionGraceIsBounded() {
        let sessionStart = start.addingTimeInterval(7 * day - 30 * 60)
        let tooLate = inputs(at: 7 * day + AccessPolicy.openSessionGrace + 1)
        XCTAssertEqual(
            AccessPolicy.decide(.newSegment(sessionStartedAt: sessionStart), tooLate),
            .denied(.freeAccessComplete)
        )
    }

    func testSessionStartedAfterExpiryGetsNoGrace() {
        let sessionStart = start.addingTimeInterval(7 * day + 60)
        let now = inputs(at: 7 * day + 120)
        XCTAssertEqual(
            AccessPolicy.decide(.newSegment(sessionStartedAt: sessionStart), now),
            .denied(.freeAccessComplete)
        )
    }

    func testSubscriptionLapsingMidSessionAllowsFinishing() {
        let expiry = start.addingTimeInterval(40 * day)
        let sessionStart = expiry.addingTimeInterval(-3600)
        let afterLapse = inputs(
            at: 40 * day + 600,
            subscription: .active(verifiedAt: expiry.addingTimeInterval(-7200), expiresAt: expiry)
        )
        XCTAssertEqual(AccessPolicy.decide(.newSegment(sessionStartedAt: sessionStart), afterLapse), .allowed)
        XCTAssertEqual(AccessPolicy.decide(.startSession, afterLapse), .denied(.needsVerification))
    }
}

final class TrustedClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testFirstEvaluationTrustsDeviceAndRecordsHighWater() {
        let result = TrustedClock.evaluate(deviceNow: t0, uptime: 100, anchor: nil, state: nil)
        XCTAssertEqual(result.now, TrustedNow(date: t0, isTrusted: true))
        XCTAssertEqual(result.state.highWaterMark, t0)
    }

    func testSmallDriftBackIsTolerated() {
        let state = TrustedClockState(highWaterMark: t0)
        let result = TrustedClock.evaluate(deviceNow: t0.addingTimeInterval(-120), uptime: 0, anchor: nil, state: state)
        XCTAssertTrue(result.now.isTrusted)
        XCTAssertEqual(result.now.date, t0, "now never goes backwards")
    }

    func testRewindIsDetected() {
        let state = TrustedClockState(highWaterMark: t0)
        let result = TrustedClock.evaluate(deviceNow: t0.addingTimeInterval(-3 * 86_400), uptime: 0, anchor: nil, state: state)
        XCTAssertFalse(result.now.isTrusted)
        XCTAssertEqual(result.now.date, t0)
        XCTAssertEqual(result.state.highWaterMark, t0)
    }

    func testServerAnchorOverridesARewoundDeviceClock() {
        let state = TrustedClockState(highWaterMark: t0)
        let anchor = ServerTimeAnchor(serverNow: t0.addingTimeInterval(3600), uptimeAtSync: 1000)
        let result = TrustedClock.evaluate(
            deviceNow: t0.addingTimeInterval(-10 * 86_400),
            uptime: 1060,
            anchor: anchor,
            state: state
        )
        XCTAssertEqual(result.now, TrustedNow(date: t0.addingTimeInterval(3660), isTrusted: true))
        XCTAssertEqual(result.state.highWaterMark, t0.addingTimeInterval(3660))
    }

    func testAnchorFromAnEarlierBootIsIgnored() {
        // Uptime restarts at boot; an anchor whose uptime is in the "future"
        // belongs to a previous boot.
        let anchor = ServerTimeAnchor(serverNow: t0, uptimeAtSync: 5000)
        let result = TrustedClock.evaluate(deviceNow: t0.addingTimeInterval(60), uptime: 10, anchor: anchor, state: nil)
        XCTAssertEqual(result.now.date, t0.addingTimeInterval(60))
    }

    func testLedgerNeverMovesAnExistingStart() {
        let existing = FreeAccessRecord(startedAt: t0, confirmedByServer: false)
        XCTAssertEqual(FreeAccessLedger.begin(existing: existing, now: t0.addingTimeInterval(86_400)), existing)
        XCTAssertEqual(FreeAccessLedger.begin(existing: nil, now: t0).startedAt, t0)
    }

    func testReinstallAdoptsTheServersEarlierStart() {
        // Reinstall: the local copy was lost and a new start was opened, but
        // the server remembers the account's real first day.
        let local = FreeAccessRecord(startedAt: t0.addingTimeInterval(5 * 86_400), confirmedByServer: false)
        let merged = FreeAccessLedger.merge(local: local, serverStartedAt: t0)
        XCTAssertEqual(merged, FreeAccessRecord(startedAt: t0, confirmedByServer: true))
    }

    func testServerCannotExtendTheWindow() {
        let local = FreeAccessRecord(startedAt: t0, confirmedByServer: false)
        let merged = FreeAccessLedger.merge(local: local, serverStartedAt: t0.addingTimeInterval(86_400))
        XCTAssertEqual(merged?.startedAt, t0)
        XCTAssertEqual(FreeAccessLedger.merge(local: nil, serverStartedAt: nil), nil)
    }
}
