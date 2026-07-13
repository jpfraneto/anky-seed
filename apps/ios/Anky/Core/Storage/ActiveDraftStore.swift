import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct ActiveDraftRecovery: Equatable {
    let text: String
    let createdAt: Date
    let durationMs: Int64
    let wordCount: Int
}

/// Persistence for the in-progress (unsealed) writing session.
///
/// Drafts are recoverable artifacts. Time passing must never delete them:
/// only successful seal/archive, successful reflection terminalization, or
/// explicit user discard may clear the file.
struct ActiveDraftStore {
    let fileURL: URL
    private let legacyFileURL: URL
    private let quarantineDirectory: URL

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        let base = baseDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("ActiveDrafts", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(LocalAnkyArchive.canonicalFileName)
        self.quarantineDirectory = directory.appendingPathComponent("Quarantine", isDirectory: true)
        try? fileManager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
        self.legacyFileURL = base
            .appendingPathComponent("Ankys", isDirectory: true)
            .appendingPathComponent(LocalAnkyArchive.canonicalFileName)
    }

    func load() -> String? {
        loadRecoverableDraft()?.text
    }

    func loadRecoverableDraft() -> ActiveDraftRecovery? {
        if let draft = loadRecovery(from: fileURL) {
            return draft
        }

        return loadRecovery(from: legacyFileURL)
    }

    func save(_ text: String) {
        let tempURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try Data(text.utf8).write(to: tempURL, options: [.atomic])
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        if loadRecovery(from: legacyFileURL) != nil {
            try? FileManager.default.removeItem(at: legacyFileURL)
        }
    }

    private func loadRecovery(from url: URL) -> ActiveDraftRecovery? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            quarantine(url: url, raw: (try? Data(contentsOf: url)) ?? Data())
            return nil
        }
        do {
            let parsed = try AnkyParser.parse(text)
            guard parsed.terminalSilenceMs == nil else {
                return nil
            }
            let reconstructed = AnkyReconstructor.reconstructText(parsed)
            return ActiveDraftRecovery(
                text: text,
                createdAt: Date(timeIntervalSince1970: TimeInterval(parsed.startEpochMs) / 1000),
                durationMs: AnkyDuration.durationMs(parsed),
                wordCount: reconstructed.split { $0.isWhitespace || $0.isNewline }.count
            )
        } catch {
            quarantine(url: url, raw: data)
            return nil
        }
    }

    private func quarantine(url: URL, raw: Data) {
        let quarantineURL = quarantineDirectory
            .appendingPathComponent("corrupt-\(Int(Date().timeIntervalSince1970 * 1000))-\(url.lastPathComponent)")
        try? raw.write(to: quarantineURL, options: [.atomic])
    }
}
