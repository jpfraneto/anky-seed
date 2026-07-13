import Foundation

#if os(iOS) && canImport(DeviceActivity)
import DeviceActivity

struct WriteBeforeScrollUnlockScheduler {
    static let activityName = DeviceActivityName("writeBeforeScroll.unlockWindow")
    static let dayBoundaryActivityName = DeviceActivityName("writeBeforeScroll.dayBoundary")

    private let center = DeviceActivityCenter()
    private let stateStore = WriteBeforeScrollScreenTimeStateStore()
    private let eventLog = WriteBeforeScrollEventLogStore()

    /// A repeating midnight-to-midnight schedule whose `intervalDidStart`
    /// reconciles the shield at the top of every local day. The one-shot
    /// relock below ends exactly at midnight for daily unlocks — a fragile
    /// edge — and foreground reconcile only helps if Anky itself is opened.
    /// This standing schedule is the actor that makes a new day start
    /// locked even when neither of those fires (feedback 2026-07-08).
    /// Idempotent: safe to call on every reconcile.
    func ensureDayBoundaryMonitoring(now: Date = Date()) {
        guard !center.activities.contains(Self.dayBoundaryActivityName) else {
            return
        }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        do {
            try center.startMonitoring(Self.dayBoundaryActivityName, during: schedule)
            eventLog.append(
                .relockScheduled,
                at: now,
                message: "Day-boundary reconcile schedule armed."
            )
        } catch {
            eventLog.append(
                .relockFailed,
                at: now,
                message: "Could not arm day-boundary schedule: \(error.localizedDescription)"
            )
        }
    }

    func scheduleRelock(at unlockedUntil: Date, now: Date = Date()) {
        stopRelockMonitoring()

        guard unlockedUntil > now.addingTimeInterval(5) else {
            stateStore.update { state in
                state.lastErrorMessage = "Unlock window is too short to schedule DeviceActivity relock."
            }
            eventLog.append(
                .relockFailed,
                at: now,
                message: "Unlock window is too short to schedule DeviceActivity relock."
            )
            return
        }

        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: unlockedUntil),
            repeats: false
        )

        do {
            try center.startMonitoring(Self.activityName, during: schedule)
            stateStore.update { state in
                state.lastErrorMessage = nil
            }
            eventLog.append(
                .relockScheduled,
                at: now,
                message: "Relock scheduled.",
                metadata: ["unlockedUntil": unlockedUntil.ISO8601Format()]
            )
        } catch {
            stateStore.update { state in
                state.lastErrorMessage = "Could not schedule relock: \(error.localizedDescription)"
            }
            eventLog.append(
                .relockFailed,
                at: now,
                message: "Could not schedule relock: \(error.localizedDescription)"
            )
        }
    }

    func stopRelockMonitoring() {
        center.stopMonitoring([Self.activityName])
    }
}
#endif
