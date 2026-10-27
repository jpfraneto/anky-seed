//
//  MemoryExportBuilder.swift
//  Anky
//
//  "Export my memories": everything someone made with Anky, in a folder a
//  person (or another program) can understand without Anky.
//
//    Anky Memories 2026-10-27/
//      README.txt
//      sessions/2026-10-27 08.12 · walking/
//        session.json                the manifest, as stored
//        media/…                     original audio and video, untouched
//        writing 1.anky / .txt       each written passage: the protocol file
//                                    and its plain reconstructed text
//      writings/                     writings made outside any session
//        2026-10-01 09.00.anky / .txt
//      reflections/<hash>.md         AI reflections a subscriber asked for
//
//  Export is always allowed, in every access state. Media is hard-linked
//  into the export folder when the volume allows it (no second copy of a
//  long video on a full phone) and copied otherwise. The folder is built
//  fresh in Caches each time and zipped by the caller.
//

import Foundation

struct MemoryExportBuilder {
    let sessions: ExpressionSessionStore
    let archive: LocalAnkyArchive
    let reflections: ReflectionStore
    var fileManager: FileManager = .default

    struct Result: Equatable {
        let folderURL: URL
        let sessionCount: Int
        let writingCount: Int
        let mediaCount: Int
    }

    func build(into parent: URL, now: Date = Date()) throws -> Result {
        let rootName = "Anky Memories \(Self.dayStamp(now))"
        let root = parent.appendingPathComponent(rootName, isDirectory: true)
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let allWritings = archive.list()
        let writingsByHash = Dictionary(allWritings.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
        var exportedHashes = Set<String>()
        var mediaCount = 0

        let sessionList = sessions.list()
        if !sessionList.isEmpty {
            let sessionsRoot = root.appendingPathComponent("sessions", isDirectory: true)
            try fileManager.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
            var usedNames = Set<String>()
            for session in sessionList.reversed() {
                var name = Self.minuteStamp(session.startedAt)
                if let setting = session.setting { name += " · \(setting.rawValue)" }
                name = Self.unique(name, in: &usedNames)
                let folder = sessionsRoot.appendingPathComponent(name, isDirectory: true)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

                let manifest = sessions.folderURL(for: session.id)
                    .appendingPathComponent(ExpressionSessionStore.manifestName)
                try placeFile(from: manifest, to: folder.appendingPathComponent(ExpressionSessionStore.manifestName))

                var writingIndex = 0
                for segment in session.segments {
                    if let path = segment.mediaFile {
                        let source = sessions.mediaURL(for: session, relativePath: path)
                        guard fileManager.fileExists(atPath: source.path) else { continue }
                        let destination = folder.appendingPathComponent(path)
                        try fileManager.createDirectory(
                            at: destination.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try placeFile(from: source, to: destination)
                        mediaCount += 1
                    }
                    if let hash = segment.ankyHash, let writing = writingsByHash[hash] {
                        writingIndex += 1
                        try write(writing, named: "writing \(writingIndex)", in: folder)
                        exportedHashes.insert(hash)
                    }
                }
            }
        }

        let standalone = allWritings
            .filter { !exportedHashes.contains($0.hash) }
            .sorted { $0.createdAt < $1.createdAt }
        if !standalone.isEmpty {
            let writingsRoot = root.appendingPathComponent("writings", isDirectory: true)
            try fileManager.createDirectory(at: writingsRoot, withIntermediateDirectories: true)
            var usedNames = Set<String>()
            for writing in standalone {
                let name = Self.unique(Self.minuteStamp(writing.createdAt), in: &usedNames)
                try write(writing, named: name, in: writingsRoot)
            }
        }

        let reflectionList = reflections.list()
        if !reflectionList.isEmpty {
            let reflectionsRoot = root.appendingPathComponent("reflections", isDirectory: true)
            try fileManager.createDirectory(at: reflectionsRoot, withIntermediateDirectories: true)
            for reflection in reflectionList {
                let text = "# \(reflection.title)\n\n\(reflection.reflection)\n"
                try Data(text.utf8).write(
                    to: reflectionsRoot.appendingPathComponent("\(reflection.hash).md"),
                    options: [.atomic]
                )
            }
        }

        let writingCount = exportedHashes.count + standalone.count
        try Data(Self.readme(
            sessionCount: sessionList.count,
            writingCount: writingCount,
            mediaCount: mediaCount,
            exportedAt: now
        ).utf8).write(to: root.appendingPathComponent("README.txt"), options: [.atomic])

        return Result(
            folderURL: root,
            sessionCount: sessionList.count,
            writingCount: writingCount,
            mediaCount: mediaCount
        )
    }

    private func write(_ writing: SavedAnky, named name: String, in folder: URL) throws {
        try Data(writing.text.utf8).write(to: folder.appendingPathComponent("\(name).anky"), options: [.atomic])
        try Data(writing.reconstructedText.utf8).write(to: folder.appendingPathComponent("\(name).txt"), options: [.atomic])
    }

    /// Hard link when possible (same volume, no extra space), copy otherwise.
    private func placeFile(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.linkItem(at: source, to: destination)
        } catch {
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private static func unique(_ name: String, in used: inout Set<String>) -> String {
        var candidate = name
        var counter = 2
        while used.contains(candidate) {
            candidate = "\(name) (\(counter))"
            counter += 1
        }
        used.insert(candidate)
        return candidate
    }

    static func dayStamp(_ date: Date) -> String {
        stamp(date, format: "yyyy-MM-dd")
    }

    static func minuteStamp(_ date: Date) -> String {
        stamp(date, format: "yyyy-MM-dd HH.mm")
    }

    private static func stamp(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func readme(sessionCount: Int, writingCount: Int, mediaCount: Int, exportedAt: Date) -> String {
        """
        Your memories from Anky
        Exported \(SessionDateFormat.string(from: exportedAt))

        \(sessionCount) session(s), \(writingCount) writing(s), \(mediaCount) recording(s).

        sessions/      One folder per session. session.json lists, in order, what
                       you expressed: writing, voice, video, livestream, silence,
                       with start and end times. Audio (.m4a, or .caf if a
                       recording was interrupted) and video (.mov) are the original
                       files in media/.
        writings/      Writings made outside a session.
        reflections/   Reflections you asked Anky for, as Markdown.

        Every writing is saved twice: the .txt is the plain text, and the .anky is
        the original Anky protocol file, which also records the timing of every
        keystroke. .anky files can be imported back into Anky.

        This is yours. Anky's server keeps no copy of it.
        """
    }
}
