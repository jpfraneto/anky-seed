import Foundation

#if os(iOS) && canImport(DeviceActivity)
import DeviceActivity

struct WriteBeforeScrollUnlockScheduler {
    static let activityName = DeviceActivityName("writeBeforeScroll.unlockWindow")

    private let center = DeviceActivityCenter()
    private let stateStore = WriteBeforeScrollScreenTimeStateStore()
    private let eventLog = WriteBeforeScrollEventLogStore()

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
