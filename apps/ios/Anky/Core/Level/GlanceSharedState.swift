import Foundation

/// Phase-2 §4/§5: the App Group contract between the app and the
/// AnkyGlanceWidgets extension. The app pre-renders a flat composite of the
/// current painting at its true progress and writes it here; the widget only
/// ever reads. The image lands first under a content-addressed name, the
/// JSON last and atomically, so the widget never sees a half-written frame.
struct GlanceSnapshot: Codable, Equatable {
    var level: Int
    var percent: Int
    var updatedAtMs: Int64
    var imageFile: String
    var isPlaceholder: Bool
    /// Phase-3 §5: the free tier's held-100% moment. The widget shows the
    /// earned painting with the spiral and "a new painting waits" — truthful
    /// at the boundary, routing to the veiled ceremony. Optional so old
    /// snapshots on disk keep decoding.
    var isAtBoundary: Bool?
}

enum GlanceSharedState {
    static let directoryName = "Widget"
    static let snapshotFileName = "snapshot.json"
    static let trialThumbFileName = "trial-thumb.png"

    static func directoryURL(fileManager: FileManager = .default) -> URL? {
        AnkyAppGroupStorage.containerURL(fileManager: fileManager)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static func imageFileName(level: Int, percent: Int) -> String {
        "painting-\(level)-\(percent).png"
    }

    static func loadSnapshot(fileManager: FileManager = .default) -> GlanceSnapshot? {
        guard let directory = directoryURL(fileManager: fileManager),
              let data = try? Data(contentsOf: directory.appendingPathComponent(snapshotFileName)) else {
            return nil
        }
        return try? JSONDecoder().decode(GlanceSnapshot.self, from: data)
    }

    static func imageURL(named name: String, fileManager: FileManager = .default) -> URL? {
        directoryURL(fileManager: fileManager)?.appendingPathComponent(name)
    }

    /// Image first, snapshot last; stale painting frames are pruned after.
    static func write(
        snapshot: GlanceSnapshot,
        imageData: Data,
        fileManager: FileManager = .default
    ) throws {
        guard let directory = directoryURL(fileManager: fileManager) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try imageData.write(to: directory.appendingPathComponent(snapshot.imageFile), options: [.atomic])
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directory.appendingPathComponent(snapshotFileName), options: [.atomic])

        if let files = try? fileManager.contentsOfDirectory(atPath: directory.path) {
            for file in files where file.hasPrefix("painting-") && file != snapshot.imageFile {
                try? fileManager.removeItem(at: directory.appendingPathComponent(file))
            }
        }
    }

    static func writeTrialThumb(_ imageData: Data, fileManager: FileManager = .default) throws {
        guard let directory = directoryURL(fileManager: fileManager) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try imageData.write(to: directory.appendingPathComponent(trialThumbFileName), options: [.atomic])
    }
}
