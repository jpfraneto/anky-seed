import Foundation

@MainActor
final class MapViewModel: ObservableObject {
    @Published private(set) var days: [SessionDay] = []
    @Published private(set) var spatialDays: [SessionDay] = []
    @Published private(set) var firstOpenDate: Date = Date()
    @Published private(set) var mapStartDate: Date = Date()
    @Published private(set) var todayDate: Date = Calendar.ankyUTC.startOfDay(for: Date())

    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let appOpenStore: AppOpenStore
    private let calendar: Calendar
    private static let testAnkyRandomCharacters = Array("abcdefghijklmnopqrstuvwxyz0123456789")

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

    @discardableResult
    func createTestAnky(on dayDate: Date, now: Date = Date()) throws -> SavedAnky {
        let createdAt = testAnkyCreatedAt(for: dayDate, now: now)
        let ankyText = try Self.testAnkyText(
            template: DevAnkyFixture.validArtifact,
            startEpochMs: Int64(createdAt.timeIntervalSince1970 * 1000)
        )
        let saved = try archive.importArtifact(ankyText)
        try sessionIndexStore.rebuild(archive: archive, reflectionStore: reflectionStore)
        refresh()
        return saved
    }

    private func testAnkyCreatedAt(for dayDate: Date, now: Date) -> Date {
        guard !calendar.isDate(dayDate, inSameDayAs: now) else {
            return now
        }

        let dayComponents = calendar.dateComponents([.year, .month, .day], from: dayDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = dayComponents.year
        components.month = dayComponents.month
        components.day = dayComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        components.nanosecond = timeComponents.nanosecond
        return calendar.date(from: components) ?? dayDate
    }

    private static func testAnkyText(template: String, startEpochMs: Int64) throws -> String {
        var lines = template
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let firstLine = lines.first,
              let separator = firstLine.firstIndex(where: { $0.isWhitespace }) else {
            throw AnkyImportError.invalidArtifact
        }

        let characterPart = firstLine[separator...]
        lines[0] = "\(startEpochMs)\(characterPart)"

        guard let terminalIndex = lines.lastIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "\(AnkyDuration.terminalSilenceMs)"
        }) else {
            throw AnkyImportError.invalidArtifact
        }

        let randomDelta = Int.random(in: 1...Int(AnkyDuration.terminalSilenceMs))
        let randomCharacter = testAnkyRandomCharacters.randomElement() ?? "x"
        lines.insert("\(String(format: "%04d", randomDelta)) \(randomCharacter)", at: terminalIndex)

        return lines.joined(separator: "\n")
    }
}
