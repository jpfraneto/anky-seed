import Foundation

@MainActor
final class MapViewModel: ObservableObject {
    @Published private(set) var days: [SessionDay] = []
    @Published private(set) var spatialDays: [SessionDay] = []
    @Published private(set) var firstOpenDate: Date = Date()
    @Published private(set) var mapStartDate: Date = Date()
    @Published private(set) var todayDate: Date = Calendar.ankyUTC.startOfDay(for: Date())
    @Published private(set) var completeAnkyCount = 0
    @Published private(set) var totalWritingMinutes = 0
    @Published private(set) var currentStreak = 0
    @Published private(set) var completeAnkySessions: [SessionSummary] = []

    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let appOpenStore: AppOpenStore
    private let calendar: Calendar

    init(
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        appOpenStore: AppOpenStore = AppOpenStore(),
        calendar: Calendar = .ankyUTC
    ) {
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        self.appOpenStore = appOpenStore
        self.calendar = calendar
        refresh()
    }

    func refresh() {
        let sessions = (try? sessionIndexStore.rebuild(archive: archive, reflectionStore: reflectionStore)) ?? sessionIndexStore.load()
        let now = Date()
        todayDate = calendar.startOfDay(for: now)
        firstOpenDate = JourneyAnchor.anchorDay(in: sessions, fallback: now, calendar: calendar)
        mapStartDate = firstOpenDate
        days = sessions.groupedByDay(calendar: calendar, firstOpenDate: mapStartDate, now: now)
        spatialDays = sessions.groupedByContinuousDays(calendar: calendar, firstOpenDate: mapStartDate, now: now)
        let completeSessions = sessions.filter(\.isComplete)
        completeAnkySessions = completeSessions.sorted { $0.createdAt > $1.createdAt }
        completeAnkyCount = completeSessions.count
        let totalDurationMs = sessions.reduce(Int64(0)) { $0 + $1.durationMs }
        totalWritingMinutes = sessions.isEmpty ? 0 : max(1, Int((totalDurationMs + 59_999) / 60_000))
        currentStreak = Self.currentStreak(from: completeSessions.map(\.createdAt), calendar: calendar, now: now)
    }

    var today: SessionDay? {
        spatialDays.first { calendar.isDate($0.date, inSameDayAs: todayDate) }
    }

    var trailDays: [SessionDay] {
        days.filter { !calendar.isDate($0.date, inSameDayAs: todayDate) }
    }

    func day(for date: Date) -> SessionDay? {
        spatialDays.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func artifact(for summary: SessionSummary) -> SavedAnky? {
        try? archive.load(url: summary.localFileURL)
    }

    private static func currentStreak(from dates: [Date], calendar: Calendar, now: Date) -> Int {
        let activeDays = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !activeDays.isEmpty else {
            return 0
        }

        var day = calendar.startOfDay(for: now)
        guard activeDays.contains(day) else {
            return 0
        }

        var streak = 0
        while activeDays.contains(day) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previousDay
        }
        return streak
    }
}
