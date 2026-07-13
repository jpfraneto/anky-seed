import Foundation

enum WriteBeforeScrollUnlockSource: String, Codable, Equatable {
    case writing
    case test
    /// The 30-second emergency breath (phase-2 §2). Grants the day without
    /// writing and never consumes a Quick Pass.
    case emergency
}

enum WriteBeforeScrollUnlockStateMachine {
    static func applyingUnlock(
        tierRawValue: String,
        unlockedUntil: Date,
        startsCountingOnExit: Bool = false,
        source: WriteBeforeScrollUnlockSource,
        to state: WriteBeforeScrollScreenTimeState
    ) -> WriteBeforeScrollScreenTimeState {
        var state = state
        state.unlockTierRawValue = tierRawValue
        state.unlockedUntil = unlockedUntil
        state.unlockStartsCountingOnExit = startsCountingOnExit
        state.unlockSourceRawValue = source.rawValue
        state.shieldActive = false
        state.lastErrorMessage = nil
        return state
    }

    static func forcingLock(
        _ state: WriteBeforeScrollScreenTimeState,
        at now: Date
    ) -> WriteBeforeScrollScreenTimeState {
        var state = state
        state.unlockTierRawValue = nil
        state.unlockedUntil = nil
        state.unlockStartsCountingOnExit = false
        state.unlockSourceRawValue = nil
        state.shieldActive = true
        state.lastRelockedAt = now
        state.lastErrorMessage = nil
        return state
    }

    static func applyingRelock(
        _ state: WriteBeforeScrollScreenTimeState,
        at now: Date
    ) -> WriteBeforeScrollScreenTimeState {
        forcingLock(state, at: now)
    }
}
