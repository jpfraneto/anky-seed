//
//  ExpressionSessionStore.swift
//  Anky
//
//  Where sessions live on disk — an intentional, documented location:
//
//    Documents/Sessions/<session-uuid>/session.json   the manifest
//    Documents/Sessions/<session-uuid>/media/          voice (.m4a/.caf) and video (.mov)
//
//  Written passages stay in Documents/Ankys/<sha256>.anky (LocalAnkyArchive)
//  and are referenced by hash. Every manifest write is atomic, so a crash
//  mid-write leaves the previous manifest intact. Media is written by the
//  recorders in crash-tolerant forms (CAF audio, fragmented QuickTime video)
//  so an interrupted capture keeps what was recorded.
//
//  Documents is included in the device's own backup. Export (every session,
//  with its original media) goes through the share sheet.
//

import Foundation

enum ExpressionSessionStoreError: Error, Equatable {
    case newerFormat
    case notFound
}

struct ExpressionSessionStore {
    static let manifestName = "session.json"
    static let mediaFolder = "media"

    let rootURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(rootURL: documents.appendingPathComponent("Sessions", isDirectory: true), fileManager: fileManager)
    }

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func folderURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    func mediaFolderURL(for id: UUID) throws -> URL {
        let url = folderURL(for: id).appendingPathComponent(Self.mediaFolder, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Absolute URL for a segment's media path (relative to the session folder).
    func mediaURL(for session: ExpressionSession, relativePath: String) -> URL {
        folderURL(for: session.id).appendingPathComponent(relativePath)
    }

    func save(_ session: ExpressionSession) throws {
        if let existing = try? load(id: session.id), existing.isFromNewerVersion {
            throw ExpressionSessionStoreError.newerFormat
        }
        let folder = folderURL(for: session.id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder.sessionEncoder.encode(session)
        try data.write(to: folder.appendingPathComponent(Self.manifestName), options: [.atomic])
    }

    func load(id: UUID) throws -> ExpressionSession {
        let url = folderURL(for: id).appendingPathComponent(Self.manifestName)
        guard fileManager.fileExists(atPath: url.path) else { throw ExpressionSessionStoreError.notFound }
        return try JSONDecoder.sessionDecoder.decode(ExpressionSession.self, from: Data(contentsOf: url))
    }

    /// Every readable session, newest first. An unreadable manifest is
    /// skipped, never deleted.
    func list() -> [ExpressionSession] {
        let folders = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return folders
            .compactMap { folder -> ExpressionSession? in
                let manifest = folder.appendingPathComponent(Self.manifestName)
                guard let data = try? Data(contentsOf: manifest) else { return nil }
                return try? JSONDecoder.sessionDecoder.decode(ExpressionSession.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// The session left open, if any (at most one is ever open; if several
    /// are found after a crash, the newest is the active one).
    func activeSession() -> ExpressionSession? {
        list().first(where: \.isActive)
    }

    /// Writing hashes that belong to some session, so the drawer can show
    /// standalone writings separately without listing anything twice.
    func writingHashesInSessions() -> Set<String> {
        Set(list().flatMap(\.writingHashes))
    }

    /// Deletes the session folder (manifest + media). Written passages are
    /// deleted by the caller through the writing archive, deliberately.
    func delete(id: UUID) throws {
        let folder = folderURL(for: id)
        guard fileManager.fileExists(atPath: folder.path) else { return }
        try fileManager.removeItem(at: folder)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try fileManager.removeItem(at: rootURL)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    /// The last time a segment's media file was written to — used by recovery
    /// to close an interrupted capture at the truthful moment.
    func lastWriteDate(of segment: ExpressionSegment, sessionID: UUID) -> Date? {
        guard let path = segment.mediaFile else { return nil }
        let url = folderURL(for: sessionID).appendingPathComponent(path)
        return (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Free space on the volume that holds sessions, for recording checks.
    func availableCapacityBytes() -> Int64? {
        let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

extension JSONEncoder {
    static var sessionEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithMilliseconds
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var sessionDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithMilliseconds
        return decoder
    }
}

extension JSONEncoder.DateEncodingStrategy {
    static var iso8601WithMilliseconds: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SessionDateFormat.string(from: date))
        }
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithMilliseconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = SessionDateFormat.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(raw)")
            }
            return date
        }
    }
}

enum SessionDateFormat {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
