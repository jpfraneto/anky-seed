import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct SavedAnky: Hashable {
    let url: URL
    let hash: String
    let text: String
    let reconstructedText: String
    let durationMs: Int64
    let isComplete: Bool
    let createdAt: Date
    let inputStats: WritingInputStats
}

extension SavedAnky: Identifiable {
    var id: String { hash }
}

struct WritingInputStats: Codable, Hashable {
    var backspaceCount: Int
    var enterCount: Int

    static let empty = WritingInputStats(backspaceCount: 0, enterCount: 0)
}

enum AnkyImportError: Error, Equatable {
    case invalidArtifact
}

struct LocalAnkyArchive {
    static let canonicalFileName = "dotAnky.anky"

    let directoryURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(directoryURL: documents.appendingPathComponent("Ankys", isDirectory: true), fileManager: fileManager)
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func save(_ ankyText: String, inputStats: WritingInputStats = .empty) throws -> SavedAnky {
        let bytes = Data(ankyText.utf8)
        let hash = AnkyHasher.sha256Hex(bytes)
        let url = hashURL(for: hash)
        let artifact = try artifact(from: ankyText, url: url, inputStats: inputStats)
        try bytes.write(to: url, options: [.atomic])
        try saveInputStats(inputStats, hash: hash)
        return artifact
    }

    func importArtifact(_ ankyText: String) throws -> SavedAnky {
        for candidate in Self.importCandidates(from: ankyText) {
            let validation = AnkyValidator.validate(candidate)
            guard validation.isValid, validation.isComplete else {
                continue
            }

            return try save(candidate)
        }

        throw AnkyImportError.invalidArtifact
    }

    func load(url: URL) throws -> SavedAnky {
        try artifact(from: String(contentsOf: url, encoding: .utf8), url: url)
    }

    func load(hash: String) throws -> SavedAnky {
        let directURL = hashURL(for: hash)
        if fileManager.fileExists(atPath: directURL.path) {
            return try load(url: directURL)
        }

        if let canonical = try? load(url: canonicalURL), canonical.hash == hash {
            return canonical
        }

        if let match = list().first(where: { $0.hash == hash }) {
            return match
        }

        throw CocoaError(.fileNoSuchFile)
    }

    func list() -> [SavedAnky] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var seen = Set<String>()
        return urls
            .filter { $0.pathExtension == "anky" }
            .compactMap { try? load(url: $0) }
            .filter { artifact in
                guard !seen.contains(artifact.hash) else {
                    return false
                }
                seen.insert(artifact.hash)
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fileURLs() -> [URL] {
        list().map(\.url)
    }

    func delete(_ artifact: SavedAnky) throws {
        try? fileManager.removeItem(at: inputStatsURL(for: artifact.hash))
        if fileManager.fileExists(atPath: artifact.url.path) {
            try fileManager.removeItem(at: artifact.url)
            return
        }

        let hashURL = directoryURL.appendingPathComponent("\(artifact.hash).anky")
        guard fileManager.fileExists(atPath: hashURL.path) else {
            return
        }
        try fileManager.removeItem(at: hashURL)
    }

    func clear() throws {
        let urls = ((try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter { $0.pathExtension == "anky" }
        for url in urls {
            try fileManager.removeItem(at: url)
        }

        let statsURLs = ((try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasSuffix(".input-stats.json") }
        for url in statsURLs {
            try fileManager.removeItem(at: url)
        }
    }

    private var canonicalURL: URL {
        directoryURL.appendingPathComponent(Self.canonicalFileName)
    }

    private func hashURL(for hash: String) -> URL {
        directoryURL.appendingPathComponent("\(hash).anky")
    }

    private func inputStatsURL(for hash: String) -> URL {
        directoryURL.appendingPathComponent("\(hash).input-stats.json")
    }

    private func saveInputStats(_ stats: WritingInputStats, hash: String) throws {
        let data = try JSONEncoder().encode(stats)
        try data.write(to: inputStatsURL(for: hash), options: [.atomic])
    }

    private func loadInputStats(hash: String) -> WritingInputStats {
        guard let data = try? Data(contentsOf: inputStatsURL(for: hash)),
              let stats = try? JSONDecoder().decode(WritingInputStats.self, from: data) else {
            return .empty
        }
        return stats
    }

    private static func importCandidates(from text: String) -> [String] {
        var candidates = [String]()

        func append(_ candidate: String) {
            let normalized = normalizedImportedAnkyText(candidate)
            guard !normalized.isEmpty, !candidates.contains(normalized) else {
                return
            }
            candidates.append(normalized)
        }

        let prepared = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        append(prepared)

        for fencedBlock in fencedCodeBlocks(in: prepared) {
            append(fencedBlock)
        }

        if let protocolBlock = extractedProtocolBlock(from: prepared) {
            append(protocolBlock)
        }

        return candidates
    }

    private static func fencedCodeBlocks(in text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks = [String]()
        var startIndex: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("```") else {
                continue
            }

            if let start = startIndex {
                blocks.append(lines[(start + 1)..<index].joined(separator: "\n"))
                startIndex = nil
            } else {
                startIndex = index
            }
        }

        return blocks
    }

    private static func extractedProtocolBlock(from text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var best = [String]()
        var current = [String]()

        for line in lines {
            let normalized = normalizedProtocolLine(line)
            if let normalized {
                current.append(normalized)
                if normalized == "\(AnkyDuration.terminalSilenceMs)" {
                    if current.count > best.count {
                        best = current
                    }
                    current.removeAll()
                }
            } else {
                if current.count > best.count {
                    best = current
                }
                current.removeAll()
            }
        }

        if current.count > best.count {
            best = current
        }

        return best.isEmpty ? nil : best.joined(separator: "\n")
    }

    private static func normalizedImportedAnkyText(_ text: String) -> String {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        while let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeFirst()
        }

        while let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeLast()
        }

        return lines
            .map { normalizedProtocolLine($0) ?? $0 }
            .joined(separator: "\n")
    }

    private static func normalizedProtocolLine(_ line: String) -> String? {
        let line = line.trimmingLeadingWhitespace()

        if line.trimmingCharacters(in: .whitespacesAndNewlines) == "\(AnkyDuration.terminalSilenceMs)" {
            return "\(AnkyDuration.terminalSilenceMs)"
        }

        guard let separator = line.firstIndex(where: { $0.isWhitespace }),
              separator != line.startIndex else {
            return nil
        }

        let timeText = String(line[..<separator])
        guard timeText.allSatisfy(\.isNumber) else {
            return nil
        }

        let afterSeparator = line.index(after: separator)
        let characterText = String(line[afterSeparator...])
        let trimmedCharacterText = characterText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedCharacterText == "SPACE" || characterText == " " {
            return "\(timeText) SPACE"
        }

        if characterText.count == 1 {
            return "\(timeText) \(characterText)"
        }

        if trimmedCharacterText.count == 1 {
            return "\(timeText) \(trimmedCharacterText)"
        }

        return nil
    }

    private func artifact(from ankyText: String, url: URL, inputStats explicitInputStats: WritingInputStats? = nil) throws -> SavedAnky {
        let bytes = Data(ankyText.utf8)
        let hash = AnkyHasher.sha256Hex(bytes)
        let parsed = try AnkyParser.parse(ankyText)
        let durationMs = AnkyDuration.durationMs(parsed)
        let createdAt = Date(timeIntervalSince1970: TimeInterval(parsed.startEpochMs) / 1000)
        let inputStats = explicitInputStats ?? loadInputStats(hash: hash)
        return SavedAnky(
            url: url,
            hash: hash,
            text: ankyText,
            reconstructedText: AnkyReconstructor.reconstructText(parsed),
            durationMs: durationMs,
            isComplete: AnkyDuration.isComplete(parsed),
            createdAt: createdAt,
            inputStats: inputStats
        )
    }
}

private extension String {
    func trimmingLeadingWhitespace() -> String {
        guard let firstNonWhitespace = firstIndex(where: { !$0.isWhitespace }) else {
            return ""
        }
        return String(self[firstNonWhitespace...])
    }
}
