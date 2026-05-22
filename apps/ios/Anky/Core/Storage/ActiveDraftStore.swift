import Foundation

struct ActiveDraftStore {
    let fileURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Ankys", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(LocalAnkyArchive.canonicalFileName)
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
