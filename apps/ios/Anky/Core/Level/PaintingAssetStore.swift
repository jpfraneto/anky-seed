import Foundation

/// One level's painting package on disk: the three images and their meta.
struct PaintingPackage: Codable, Equatable {
    let level: Int
    let title: String
    let palette: [String]
    let thresholdSeconds: Int
    let directoryURL: URL

    var finalURL: URL { directoryURL.appendingPathComponent("final.png") }
    var underdrawingURL: URL { directoryURL.appendingPathComponent("underdrawing.png") }
    var revealMapURL: URL { directoryURL.appendingPathComponent("revealmap.png") }
}

private struct PaintingMetaFile: Codable {
    let title: String
    let palette: [String]
    let level: Int
    let thresholdSeconds: Int
}

/// Downloads, caches, and lists painting packages.
///
/// Layout: Documents/Paintings/<level>/{final,underdrawing,revealmap}.png +
/// meta.json — identical to the server package, cached permanently. Level 1
/// ships in the app bundle (StarterPainting/) so a fresh install has a
/// painting before any network round-trip.
struct PaintingAssetStore {
    static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paintings")
    }

    private let root: URL
    private let fileManager: FileManager

    init(root: URL = PaintingAssetStore.defaultRoot, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static let packageFileNames = ["final.png", "underdrawing.png", "revealmap.png", "meta.json"]

    func directory(forLevel level: Int) -> URL {
        root.appendingPathComponent(String(level))
    }

    /// A package is installed only when all four files are present.
    func installedPackage(forLevel level: Int) -> PaintingPackage? {
        let dir = directory(forLevel: level)
        for name in Self.packageFileNames {
            guard fileManager.fileExists(atPath: dir.appendingPathComponent(name).path) else {
                return nil
            }
        }
        guard
            let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
            let meta = try? JSONDecoder().decode(PaintingMetaFile.self, from: data)
        else {
            return nil
        }
        return PaintingPackage(
            level: level,
            title: meta.title,
            palette: meta.palette,
            thresholdSeconds: meta.thresholdSeconds,
            directoryURL: dir
        )
    }

    /// Copies the bundled starter painting in as level 1, once.
    @discardableResult
    func installStarterIfNeeded(bundle: Bundle = .main) -> PaintingPackage? {
        if let existing = installedPackage(forLevel: 1) {
            return existing
        }
        let dir = directory(forLevel: 1)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in Self.packageFileNames {
            let parts = name.split(separator: ".")
            guard
                let source = bundle.url(
                    forResource: String(parts[0]),
                    withExtension: String(parts[1]),
                    subdirectory: "StarterPainting"
                )
            else {
                return nil
            }
            let destination = dir.appendingPathComponent(name)
            try? fileManager.removeItem(at: destination)
            do {
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                return nil
            }
        }
        return installedPackage(forLevel: 1)
    }

    /// Writes a freshly downloaded package atomically-ish: files land in a
    /// staging directory, then move into place.
    func install(
        level: Int,
        finalPng: Data,
        underdrawingPng: Data,
        revealMapPng: Data,
        metaJson: Data
    ) throws -> PaintingPackage {
        let staging = root.appendingPathComponent(".staging-\(level)-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try finalPng.write(to: staging.appendingPathComponent("final.png"))
        try underdrawingPng.write(to: staging.appendingPathComponent("underdrawing.png"))
        try revealMapPng.write(to: staging.appendingPathComponent("revealmap.png"))
        try metaJson.write(to: staging.appendingPathComponent("meta.json"))

        let destination = directory(forLevel: level)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: staging, to: destination)

        guard let package = installedPackage(forLevel: level) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return package
    }

    /// Every installed level, ascending — the gallery reads completed ones.
    func installedLevels() -> [Int] {
        let contents = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        return contents.compactMap(Int.init).sorted().filter {
            installedPackage(forLevel: $0) != nil
        }
    }

    /// Downloads and installs a level's package from the server.
    @discardableResult
    func downloadPackage(
        level: Int,
        client: LevelSyncClient = LevelSyncClient(),
        identityStore: WriterIdentityStore = WriterIdentityStore()
    ) async throws -> PaintingPackage {
        if let existing = installedPackage(forLevel: level) {
            return existing
        }
        let identity = try identityStore.loadOrCreate()
        // Sequential on purpose: each GET signs the same empty body, and two
        // signatures minted in the same millisecond would collide with the
        // server's replay protection.
        let finalPng = try await client.fetchAsset(level: level, file: "final.png", identity: identity)
        let underPng = try await client.fetchAsset(level: level, file: "underdrawing.png", identity: identity)
        let mapPng = try await client.fetchAsset(level: level, file: "revealmap.png", identity: identity)
        let metaJson = try await client.fetchAsset(level: level, file: "meta.json", identity: identity)
        return try install(
            level: level,
            finalPng: finalPng,
            underdrawingPng: underPng,
            revealMapPng: mapPng,
            metaJson: metaJson
        )
    }
}
