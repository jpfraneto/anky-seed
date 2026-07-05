import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct WriteBeforeScrollSessionMetrics: Codable, Equatable {
    let sessionID: UUID
    var firstUnlockTierRawValue: String?
    var unlockAvailableAt: Date?
    var continuedWritingAfterUnlockAvailable: Bool
    var charactersAfterUnlockAvailable: Int
    var secondsWritingAfterUnlockAvailable: TimeInterval
    var finalTierRawValue: String?
    var totalAcceptedCharacters: Int
    var elapsedMs: Int64
    var hasQuickPassAvailable: Bool
    var hasDailyUnlockAvailable: Bool

    init(sessionID: UUID = UUID()) {
        self.sessionID = sessionID
        self.firstUnlockTierRawValue = nil
        self.unlockAvailableAt = nil
        self.continuedWritingAfterUnlockAvailable = false
        self.charactersAfterUnlockAvailable = 0
        self.secondsWritingAfterUnlockAvailable = 0
        self.finalTierRawValue = nil
        self.totalAcceptedCharacters = 0
        self.elapsedMs = 0
        self.hasQuickPassAvailable = false
        self.hasDailyUnlockAvailable = false
    }

    var firstUnlockTier: UnlockTier? {
        firstUnlockTierRawValue.flatMap(UnlockTier.init(rawValue:))
    }

    var finalTier: UnlockTier? {
        finalTierRawValue.flatMap(UnlockTier.init(rawValue:))
    }

    var currentThresholdStateText: String {
        [
            "quick pass: \(hasQuickPassAvailable ? "yes" : "no")",
            "daily unlock: \(hasDailyUnlockAvailable ? "yes" : "no")"
        ].joined(separator: ", ")
    }

    var goldenMetricText: String {
        guard firstUnlockTier != nil else {
            return "no unlock available yet"
        }
        return continuedWritingAfterUnlockAvailable
            ? "true, \(charactersAfterUnlockAvailable) chars, \(Int(secondsWritingAfterUnlockAvailable))s"
            : "false"
    }
}

struct WriteBeforeScrollSessionMetricUpdate: Equatable {
    let metrics: WriteBeforeScrollSessionMetrics
    let availableGrant: UnlockGrant?
    let events: [WriteBeforeScrollEventName]
}

struct WriteBeforeScrollSessionMetricTracker {
    private(set) var metrics: WriteBeforeScrollSessionMetrics
    private var hasLoggedWritingStarted = false
    private var loggedAvailableTiers = Set<UnlockTier>()
    private var hasLoggedContinuedWriting = false

    init(metrics: WriteBeforeScrollSessionMetrics = WriteBeforeScrollSessionMetrics()) {
        self.metrics = metrics
    }

    mutating func recordAcceptedCharacters(
        count: Int,
        snapshot: WritingSessionSnapshot,
        at now: Date,
        policy: UnlockPolicy = UnlockPolicy(),
        dailyTargetMs: Int64 = UnlockPolicy.defaultDailyTargetMs,
        quickPassesRemaining: Int = UnlockPolicy.quickPassDailyAllowance,
        dailyUnlockEntitled: Bool = true
    ) -> WriteBeforeScrollSessionMetricUpdate {
        guard count > 0 else {
            return WriteBeforeScrollSessionMetricUpdate(metrics: metrics, availableGrant: nil, events: [])
        }

        var events: [WriteBeforeScrollEventName] = []
        if !hasLoggedWritingStarted {
            hasLoggedWritingStarted = true
            events.append(.writingStarted)
        }

        metrics.totalAcceptedCharacters += count
        metrics.elapsedMs = snapshot.elapsedMs

        if metrics.unlockAvailableAt != nil {
            metrics.charactersAfterUnlockAvailable += count
            if let unlockAvailableAt = metrics.unlockAvailableAt {
                metrics.secondsWritingAfterUnlockAvailable = max(
                    metrics.secondsWritingAfterUnlockAvailable,
                    now.timeIntervalSince(unlockAvailableAt)
                )
            }
            if !hasLoggedContinuedWriting {
                metrics.continuedWritingAfterUnlockAvailable = true
                hasLoggedContinuedWriting = true
                events.append(.continuedWritingAfterUnlockAvailable)
            }
        }

        let availableTiers = availableTiers(
            for: snapshot,
            dailyTargetMs: dailyTargetMs,
            quickPassesRemaining: quickPassesRemaining,
            dailyUnlockEntitled: dailyUnlockEntitled
        )
        metrics.hasQuickPassAvailable = availableTiers.contains(.quick)
        metrics.hasDailyUnlockAvailable = availableTiers.contains(.daily)

        var newlyAvailableGrant: UnlockGrant?
        for tier in availableTiers.sorted(by: { $0.unlockRank < $1.unlockRank }) {
            guard !loggedAvailableTiers.contains(tier) else {
                continue
            }
            loggedAvailableTiers.insert(tier)
            if metrics.firstUnlockTierRawValue == nil {
                metrics.firstUnlockTierRawValue = tier.rawValue
                metrics.unlockAvailableAt = now
            }
            metrics.finalTierRawValue = tier.rawValue
            events.append(eventName(forAvailableTier: tier))
            newlyAvailableGrant = policy.grant(
                for: snapshot,
                at: now,
                dailyTargetMs: dailyTargetMs,
                quickPassesRemaining: quickPassesRemaining,
                dailyUnlockEntitled: dailyUnlockEntitled
            )
        }

        return WriteBeforeScrollSessionMetricUpdate(
            metrics: metrics,
            availableGrant: newlyAvailableGrant,
            events: events
        )
    }

    mutating func reset() {
        self = WriteBeforeScrollSessionMetricTracker()
    }

    private func availableTiers(
        for snapshot: WritingSessionSnapshot,
        dailyTargetMs: Int64,
        quickPassesRemaining: Int,
        dailyUnlockEntitled: Bool
    ) -> Set<UnlockTier> {
        var tiers = Set<UnlockTier>()
        if snapshot.hasCompletedSentence, quickPassesRemaining > 0 {
            tiers.insert(.quick)
        }
        // Phase-3: the Daily Unlock belongs to the subscription. The target
        // is still logged and the seconds still count — only the day-long
        // door needs the practice to be paid for.
        if dailyUnlockEntitled, snapshot.elapsedMs >= dailyTargetMs {
            tiers.insert(.daily)
        }
        return tiers
    }

    private func eventName(forAvailableTier tier: UnlockTier) -> WriteBeforeScrollEventName {
        switch tier {
        case .quick:
            return .sentenceUnlockAvailable
        case .daily:
            return .dailyTargetReached
        }
    }
}
