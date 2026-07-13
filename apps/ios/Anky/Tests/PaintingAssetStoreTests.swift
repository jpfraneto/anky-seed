import XCTest
@testable import AnkyCore

final class PaintingAssetStoreTests: XCTestCase {
    private func temporaryStore() -> PaintingAssetStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("anky-paintings-\(UUID().uuidString)")
        return PaintingAssetStore(root: root)
    }

    private let meta = """
    {"title": "The Door", "palette": ["#1d1611", "#714a28", "#d2a47e"], "level": 2, "thresholdSeconds": 480}
    """

    func testInstallAndReadBackPackage() throws {
        let store = temporaryStore()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let package = try store.install(
            level: 2,
            finalPng: png,
            underdrawingPng: png,
            revealMapPng: png,
            metaJson: Data(meta.utf8)
        )
        XCTAssertEqual(package.level, 2)
        XCTAssertEqual(package.title, "The Door")
        XCTAssertEqual(package.palette.count, 3)
        XCTAssertEqual(package.thresholdSeconds, 480)
        XCTAssertNotNil(store.installedPackage(forLevel: 2))
        XCTAssertEqual(store.installedLevels(), [2])
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.finalURL.path))
    }

    func testIncompletePackageIsNotInstalled() throws {
        let store = temporaryStore()
        let dir = store.directory(forLevel: 3)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([0x00]).write(to: dir.appendingPathComponent("final.png"))
        XCTAssertNil(store.installedPackage(forLevel: 3))
        XCTAssertEqual(store.installedLevels(), [])
    }

    func testReinstallReplacesPackage() throws {
        let store = temporaryStore()
        let png = Data([0x01])
        _ = try store.install(level: 2, finalPng: png, underdrawingPng: png, revealMapPng: png, metaJson: Data(meta.utf8))
        let updatedMeta = meta.replacingOccurrences(of: "The Door", with: "The Return")
        let package = try store.install(level: 2, finalPng: png, underdrawingPng: png, revealMapPng: png, metaJson: Data(updatedMeta.utf8))
        XCTAssertEqual(package.title, "The Return")
    }
}
