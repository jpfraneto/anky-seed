import Foundation

struct ActiveDraftStore {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Anky", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("active-draft.anky")
    }

    func load() -> String? {
        try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func save(_ text: String) {
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
