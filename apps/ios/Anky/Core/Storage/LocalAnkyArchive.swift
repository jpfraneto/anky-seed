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

    func save(_ ankyText: String) throws -> SavedAnky {
        let bytes = Data(ankyText.utf8)
        let url = canonicalURL
        try bytes.write(to: url, options: [.atomic])

        return try artifact(from: ankyText, url: url)
    }

    func importArtifact(_ ankyText: String) throws -> SavedAnky {
        guard AnkyValidator.validate(ankyText).isValid else {
            throw AnkyImportError.invalidArtifact
        }

        return try save(ankyText)
    }

    func load(url: URL) throws -> SavedAnky {
        try artifact(from: String(contentsOf: url, encoding: .utf8), url: url)
    }

    func load(hash: String) throws -> SavedAnky {
        let current = try load(url: canonicalURL)
        guard current.hash == hash else {
            throw CocoaError(.fileNoSuchFile)
        }
        return current
    }

    func list() -> [SavedAnky] {
        if let current = try? load(url: canonicalURL) {
            return [current]
        }

        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension == "anky" }
            .compactMap { try? load(url: $0) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(1)
            .map { $0 }
    }

    func fileURLs() -> [URL] {
        list().map(\.url)
    }

    func delete(_ artifact: SavedAnky) throws {
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
    }

    private var canonicalURL: URL {
        directoryURL.appendingPathComponent(Self.canonicalFileName)
    }

    private func artifact(from ankyText: String, url: URL) throws -> SavedAnky {
        let bytes = Data(ankyText.utf8)
        let hash = AnkyHasher.sha256Hex(bytes)
        let parsed = try AnkyParser.parse(ankyText)
        let durationMs = AnkyDuration.durationMs(parsed)
        let createdAt = Date(timeIntervalSince1970: TimeInterval(parsed.startEpochMs) / 1000)
        return SavedAnky(
            url: url,
            hash: hash,
            text: ankyText,
            reconstructedText: AnkyReconstructor.reconstructText(parsed),
            durationMs: durationMs,
            isComplete: AnkyDuration.isComplete(parsed),
            createdAt: createdAt
        )
    }
}
