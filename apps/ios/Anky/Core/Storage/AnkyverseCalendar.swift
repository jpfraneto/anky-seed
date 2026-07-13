import Foundation

struct AnkyversePosition: Hashable {
    let dayIndex: Int
    let cycleDay: Int
    let region: Int
    let dayInRegion: Int
}

struct AnkyverseCalendar {
    private let calendar: Calendar
    private let firstOpenDate: Date

    init(firstOpenDate: Date, calendar: Calendar = .current) {
        self.firstOpenDate = calendar.startOfDay(for: firstOpenDate)
        self.calendar = calendar
    }

    func position(for date: Date) -> AnkyversePosition {
        let start = calendar.startOfDay(for: date)
        let rawIndex = calendar.dateComponents([.day], from: firstOpenDate, to: start).day ?? 0
        let dayIndex = max(0, rawIndex)
        let cycleDay = dayIndex % 96
        return AnkyversePosition(
            dayIndex: dayIndex + 1,
            cycleDay: cycleDay + 1,
            region: (cycleDay / 8) + 1,
            dayInRegion: (cycleDay % 8) + 1
        )
    }
}
