import Foundation

@MainActor
final class MapViewModel: ObservableObject {
    @Published private(set) var days: [SessionDay] = []
    @Published private(set) var spatialDays: [SessionDay] = []
    @Published private(set) var firstOpenDate: Date = Date()
    @Published private(set) var mapStartDate: Date = Date()
    @Published private(set) var todayDate: Date = Calendar.current.startOfDay(for: Date())

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
        calendar: Calendar = .current
    ) {
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        self.appOpenStore = appOpenStore
        self.calendar = calendar
        refresh()
    }

    func refresh() {
        let storedFirstOpenDate = appOpenStore.loadOrCreate()
        let sessions = (try? sessionIndexStore.rebuild(archive: archive, reflectionStore: reflectionStore)) ?? sessionIndexStore.load()
        let now = Date()
        todayDate = calendar.startOfDay(for: now)
        let earliestSessionDate = sessions
            .map { calendar.startOfDay(for: $0.createdAt) }
            .min()
        firstOpenDate = earliestSessionDate
            .map { appOpenStore.recordEarlierFirstOpenDate($0, calendar: calendar) }
            ?? storedFirstOpenDate
        mapStartDate = sessions
            .map { calendar.startOfDay(for: $0.createdAt) }
            .min()
            .map { min(calendar.startOfDay(for: firstOpenDate), $0) }
            ?? calendar.startOfDay(for: firstOpenDate)
        days = sessions.groupedByDay(calendar: calendar, firstOpenDate: mapStartDate, now: now)
        spatialDays = sessions.groupedByContinuousDays(calendar: calendar, firstOpenDate: mapStartDate, now: now)
    }

    var today: SessionDay? {
        spatialDays.first { calendar.isDateInToday($0.date) }
    }

    var trailDays: [SessionDay] {
        days.filter { !calendar.isDateInToday($0.date) }
    }

    func artifact(for summary: SessionSummary) -> SavedAnky? {
        try? archive.load(url: summary.localFileURL)
    }
}
