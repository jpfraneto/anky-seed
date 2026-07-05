import DeviceActivity
import Foundation

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

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
}
