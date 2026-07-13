import Foundation

enum JourneyAnchor {
    static func firstSealedDay(
        in summaries: [SessionSummary],
        calendar: Calendar = .current
    ) -> Date? {
        summaries
            .filter(\.isComplete)
            .map { calendar.startOfDay(for: $0.createdAt) }
            .min()
    }

    static func anchorDay(
        in summaries: [SessionSummary],
        fallback: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        firstSealedDay(in: summaries, calendar: calendar)
            ?? calendar.startOfDay(for: fallback)
    }
}
