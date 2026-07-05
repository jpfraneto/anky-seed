import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

/// Persistence for the in-progress (unsealed) writing session.
///
/// Current semantics — read before changing:
/// - **In-process resume works**: the live session lives in
///   `WriteViewModel.sessionEngine` (a `@StateObject` on AppRoot), so
///   navigating between surfaces or backgrounding the app resumes writing
///   without touching this store.
/// - **This file is a crash artifact, not a restore feature**: it is written
///   on background/navigation/seal-failure, but nothing currently loads it
///   back into a `WritingSessionEngine` at launch. `WriteViewModel.init`
///   only inspects it to clear stale previous-day drafts
///   (`resetDotAnkyIfNeeded`).
/// - **Sealed `.anky` artifacts are immutable**: sealing appends the terminal
///   `8000` sentinel exactly once and closes the engine; a closed artifact
///   can be read, reflected on, and exported, but never continued.
/// - Future improvement (intentionally not built yet): restore an unsealed
///   draft into the engine after a crash/relaunch.
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
