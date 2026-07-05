import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct SavedRawCheckIn: Identifiable, Hashable {
    enum Mode: String, Codable {
        case write
        case talk
        case image
    }

    let id: String
    let url: URL
    let text: String
    let mode: Mode
    let createdAt: Date
}

struct RawCheckInStore {
    let directoryURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(directoryURL: documents.appendingPathComponent("RawCheckIns", isDirectory: true), fileManager: fileManager)
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func save(text: String, mode: SavedRawCheckIn.Mode, createdAt: Date = Date()) throws -> SavedRawCheckIn {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let id = Self.identifier(for: normalized, mode: mode, createdAt: createdAt)
        let url = directoryURL.appendingPathComponent("\(id).txt")
        try normalized.write(to: url, atomically: true, encoding: .utf8)
        let metadata = RawCheckInMetadata(mode: mode, createdAt: createdAt)
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL(for: id), options: [.atomic])
        return SavedRawCheckIn(id: id, url: url, text: normalized, mode: mode, createdAt: createdAt)
    }

    func list() -> [SavedRawCheckIn] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension == "txt" }
            .compactMap(load(url:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func load(url: URL) -> SavedRawCheckIn? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let id = url.deletingPathExtension().lastPathComponent
        let metadata = loadMetadata(id: id)
        return SavedRawCheckIn(
            id: id,
            url: url,
            text: text,
            mode: metadata?.mode ?? .write,
            createdAt: metadata?.createdAt ?? ((try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        )
    }

    private func metadataURL(for id: String) -> URL {
        directoryURL.appendingPathComponent("\(id).json")
    }

    private func loadMetadata(id: String) -> RawCheckInMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: id)) else {
            return nil
        }
        return try? JSONDecoder().decode(RawCheckInMetadata.self, from: data)
    }

    private static func identifier(for text: String, mode: SavedRawCheckIn.Mode, createdAt: Date) -> String {
        let timestamp = Int64(createdAt.timeIntervalSince1970 * 1000)
        let bytes = Data("\(mode.rawValue)\n\(timestamp)\n\(text)".utf8)
        return AnkyHasher.sha256Hex(bytes)
    }
}

private struct RawCheckInMetadata: Codable {
    let mode: SavedRawCheckIn.Mode
    let createdAt: Date
}
