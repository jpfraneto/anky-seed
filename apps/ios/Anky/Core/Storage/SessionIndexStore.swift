import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

extension Calendar {
    static var ankyUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}

struct SessionSummary: Codable, Hashable, Identifiable {
    var id: String { hash }

    let hash: String
    let createdAt: Date
    let localFileURL: URL
    let durationMs: Int64
    let isComplete: Bool
    let preview: String
    let wordCount: Int
    let hasReflection: Bool
    let reflectionTitle: String?

    var title: String {
        reflectionTitle ?? (isComplete ? "Anky" : "Fragment")
    }

    init(
        hash: String,
        createdAt: Date,
        localFileURL: URL,
        durationMs: Int64,
        isComplete: Bool,
        preview: String,
        wordCount: Int = 0,
        hasReflection: Bool,
        reflectionTitle: String?
    ) {
        self.hash = hash
        self.createdAt = createdAt
        self.localFileURL = localFileURL
        self.durationMs = durationMs
        self.isComplete = isComplete
        self.preview = preview
        self.wordCount = wordCount
        self.hasReflection = hasReflection
        self.reflectionTitle = reflectionTitle
    }

    enum CodingKeys: String, CodingKey {
        case hash
        case createdAt
        case localFileURL
        case durationMs
        case isComplete
        case preview
        case wordCount
        case hasReflection
        case reflectionTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hash = try container.decode(String.self, forKey: .hash)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        localFileURL = try container.decode(URL.self, forKey: .localFileURL)
        durationMs = try container.decode(Int64.self, forKey: .durationMs)
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        preview = try container.decode(String.self, forKey: .preview)
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount) ?? Self.wordCount(from: preview)
        hasReflection = try container.decode(Bool.self, forKey: .hasReflection)
        reflectionTitle = try container.decodeIfPresent(String.self, forKey: .reflectionTitle)
    }

    static func make(artifact: SavedAnky, reflection: LocalReflection?) -> SessionSummary {
        SessionSummary(
            hash: artifact.hash,
            createdAt: artifact.createdAt,
            localFileURL: artifact.url,
            durationMs: artifact.durationMs,
            isComplete: artifact.isComplete,
            preview: Self.preview(from: artifact.reconstructedText),
            wordCount: Self.wordCount(from: artifact.reconstructedText),
            hasReflection: reflection != nil,
            reflectionTitle: reflection?.title
        )
    }

    private static func preview(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No readable text"
        }
        return trimmed.count > 96 ? "\(trimmed.prefix(96))..." : trimmed
    }

    private static func wordCount(from text: String) -> Int {
        text
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }
}

struct SessionDay: Hashable, Identifiable {
    var id: Date { date }

    let date: Date
    let sessions: [SessionSummary]
    let completeCount: Int
    let fragmentCount: Int
    let reflectionCount: Int
    let latestPreviewOrTitle: String
    let isToday: Bool
    let ankyversePosition: AnkyversePosition

    var ankyCount: Int {
        completeCount
    }

    var hasAnky: Bool {
        ankyCount > 0
    }

    var showsTrailCompletionMarker: Bool {
        completeCount > 0
    }

    var writingSessionCount: Int {
        fragmentCount
    }

    var stateLabel: String {
        if sessions.isEmpty { return "No writing" }
        if reflectionCount > 0 { return "Reflected" }
        if ankyCount > 0 && writingSessionCount > 0 { return "Mixed" }
        if ankyCount > 0 { return "Anky" }
        return "Writing"
    }

    var activitySummary: String {
        var parts = [String]()
        if ankyCount > 0 {
            parts.append(Self.pluralize(ankyCount, singular: "anky", plural: "ankys"))
        }
        if writingSessionCount > 0 {
            parts.append(Self.pluralize(writingSessionCount, singular: "fragment", plural: "fragments"))
        }
        if reflectionCount > 0 {
            parts.append(Self.pluralize(reflectionCount, singular: "reflection", plural: "reflections"))
        }
        return parts.isEmpty ? "No writing" : parts.joined(separator: " · ")
    }

    var trailActivitySummary: String {
        if sessions.isEmpty {
            return "No writing"
        }
        return showsTrailCompletionMarker ? "Showed up" : "No complete anky"
    }

    private static func pluralize(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

struct SessionIndexStore {
    private let url: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(url: base.appendingPathComponent("Anky/session-index.json"), fileManager: fileManager)
    }

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func load() -> [SessionSummary] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder.sessionIndexDecoder.decode([SessionSummary].self, from: data)) ?? []
    }

    func hasCompleteRitual(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        load().hasCompleteRitual(on: date, calendar: calendar)
    }

    func save(_ sessions: [SessionSummary]) throws {
        let sorted = sessions.sorted { $0.createdAt > $1.createdAt }
        let data = try JSONEncoder.sessionIndexEncoder.encode(sorted)
        try data.write(to: url, options: [.atomic])
    }

    func upsert(_ summary: SessionSummary) throws {
        var sessions = load().filter { $0.hash != summary.hash }
        sessions.append(summary)
        try save(sessions)
    }

    @discardableResult
    func rebuild(archive: LocalAnkyArchive, reflectionStore: ReflectionStore) throws -> [SessionSummary] {
        let sessions = archive.list().map { artifact in
            SessionSummary.make(
                artifact: artifact,
                reflection: reflectionStore.load(hash: artifact.hash)
            )
        }
        try save(sessions)
        return sessions
    }

    func updateReflection(hash: String, title: String) throws {
        let sessions = load().map { summary in
            guard summary.hash == hash else {
                return summary
            }
            return SessionSummary(
                hash: summary.hash,
                createdAt: summary.createdAt,
                localFileURL: summary.localFileURL,
                durationMs: summary.durationMs,
                isComplete: summary.isComplete,
                preview: summary.preview,
                wordCount: summary.wordCount,
                hasReflection: true,
                reflectionTitle: title
            )
        }
        try save(sessions)
    }

    func delete(hash: String) throws {
        try save(load().filter { $0.hash != hash })
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }
}

extension Array where Element == SessionSummary {
    func hasCompleteRitual(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        contains { summary in
            summary.isComplete && calendar.isDate(summary.createdAt, inSameDayAs: date)
        }
    }

    func groupedByDay(
        calendar: Calendar = .ankyUTC,
        firstOpenDate: Date,
        now: Date = Date()
    ) -> [SessionDay] {
        let grouped = Dictionary(grouping: self) { calendar.startOfDay(for: $0.createdAt) }
        let earliestSessionDate = grouped.keys.min()
        let mapStartDate = [calendar.startOfDay(for: firstOpenDate), earliestSessionDate]
            .compactMap { $0 }
            .min() ?? calendar.startOfDay(for: firstOpenDate)
        let ankyverse = AnkyverseCalendar(firstOpenDate: mapStartDate, calendar: calendar)
        let today = calendar.startOfDay(for: now)

        return grouped.map { date, sessions in
            let sortedSessions = sessions.sorted { $0.createdAt > $1.createdAt }
            let latest = sortedSessions.first
            return SessionDay(
                date: date,
                sessions: sortedSessions,
                completeCount: sortedSessions.filter(\.isComplete).count,
                fragmentCount: sortedSessions.filter { !$0.isComplete }.count,
                reflectionCount: sortedSessions.filter(\.hasReflection).count,
                latestPreviewOrTitle: latest?.reflectionTitle ?? latest?.preview ?? "No writing",
                isToday: calendar.isDate(date, inSameDayAs: today),
                ankyversePosition: ankyverse.position(for: date)
            )
        }
        .sorted { $0.date > $1.date }
    }

    func groupedByContinuousDays(
        calendar: Calendar = .ankyUTC,
        firstOpenDate: Date,
        now: Date = Date()
    ) -> [SessionDay] {
        let grouped = Dictionary(grouping: self) { calendar.startOfDay(for: $0.createdAt) }
        let earliestSessionDate = grouped.keys.min()
        let startDate = [calendar.startOfDay(for: firstOpenDate), earliestSessionDate]
            .compactMap { $0 }
            .min() ?? calendar.startOfDay(for: firstOpenDate)
        let today = calendar.startOfDay(for: now)
        let endDate = Swift.max(today, grouped.keys.max() ?? today)
        let ankyverse = AnkyverseCalendar(firstOpenDate: startDate, calendar: calendar)
        let dayCount = Swift.max(0, calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0)

        return (0...dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            let sortedSessions = (grouped[date] ?? []).sorted { $0.createdAt > $1.createdAt }
            let latest = sortedSessions.first
            return SessionDay(
                date: date,
                sessions: sortedSessions,
                completeCount: sortedSessions.filter(\.isComplete).count,
                fragmentCount: sortedSessions.filter { !$0.isComplete }.count,
                reflectionCount: sortedSessions.filter(\.hasReflection).count,
                latestPreviewOrTitle: latest?.reflectionTitle ?? latest?.preview ?? "No writing",
                isToday: calendar.isDate(date, inSameDayAs: today),
                ankyversePosition: ankyverse.position(for: date)
            )
        }
    }
}

private extension JSONEncoder {
    static var sessionIndexEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var sessionIndexDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
