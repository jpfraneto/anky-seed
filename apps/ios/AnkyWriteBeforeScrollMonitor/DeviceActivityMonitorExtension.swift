import DeviceActivity
import Foundation

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        // The repeating day-boundary schedule opens at local midnight: a new
        // day starts locked (or honestly open — reconcile respects the gate
        // off-switch and any still-valid grant) without waiting for the app
        // to be foregrounded.
        guard activity == WriteBeforeScrollUnlockScheduler.dayBoundaryActivityName else {
            return
        }
        reconcileAtDayBoundary()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        if activity == WriteBeforeScrollUnlockScheduler.dayBoundaryActivityName {
            // Redundant second edge just before midnight — cheap insurance
            // against a missed dayStart callback.
            reconcileAtDayBoundary()
            return
        }

        guard activity == WriteBeforeScrollUnlockScheduler.activityName else {
            return
        }

        let now = Date()
        let applied = WriteBeforeScrollShieldController().applyShield(now: now)
        if applied {
            WriteBeforeScrollScreenTimeStateStore().update { state in
                state = WriteBeforeScrollUnlockStateMachine.applyingRelock(state, at: now)
            }
            WriteBeforeScrollEventLogStore().append(.relockApplied, at: now)
        } else {
            WriteBeforeScrollEventLogStore().append(
                .relockFailed,
                at: now,
                message: "DeviceActivity interval ended, but shield could not be applied."
            )
        }
    }

    private func reconcileAtDayBoundary() {
        // reconcileShield owns the state writes and transition-only logging;
        // it honors the gate off-switch and any still-valid grant.
        _ = WriteBeforeScrollShieldController().reconcileShield(now: Date())
    }
}
