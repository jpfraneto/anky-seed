import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct ActiveDraftStore {
    let fileURL: URL
    private let legacyFileURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("ActiveDrafts", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(LocalAnkyArchive.canonicalFileName)
        self.legacyFileURL = base
            .appendingPathComponent("Ankys", isDirectory: true)
            .appendingPathComponent(LocalAnkyArchive.canonicalFileName)
    }

    func load() -> String? {
        if let draft = try? String(contentsOf: fileURL, encoding: .utf8) {
            return draft
        }

        guard let legacyDraft = try? String(contentsOf: legacyFileURL, encoding: .utf8),
              isOpenDraft(legacyDraft) else {
            return nil
        }
        return legacyDraft
    }

    func save(_ text: String) {
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        if let legacyDraft = try? String(contentsOf: legacyFileURL, encoding: .utf8),
           isOpenDraft(legacyDraft) {
            try? FileManager.default.removeItem(at: legacyFileURL)
        }
    }

    private func isOpenDraft(_ text: String) -> Bool {
        guard let parsed = try? AnkyParser.parse(text) else {
            return false
        }
        return parsed.terminalSilenceMs == nil
    }
}
