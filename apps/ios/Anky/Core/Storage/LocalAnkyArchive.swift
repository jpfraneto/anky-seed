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

struct LocalAnkyArchive {
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
        let hash = AnkyHasher.sha256Hex(bytes)
        let url = directoryURL.appendingPathComponent("\(hash).anky")
        try bytes.write(to: url, options: [.atomic])

        return try artifact(from: ankyText, url: url)
    }

    func load(url: URL) throws -> SavedAnky {
        try artifact(from: String(contentsOf: url, encoding: .utf8), url: url)
    }

    func load(hash: String) throws -> SavedAnky {
        try load(url: directoryURL.appendingPathComponent("\(hash).anky"))
    }

    func list() -> [SavedAnky] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension == "anky" }
            .compactMap { try? load(url: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fileURLs() -> [URL] {
        ((try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter { $0.pathExtension == "anky" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func clear() throws {
        let urls = fileURLs()
        for url in urls {
            try fileManager.removeItem(at: url)
        }
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
