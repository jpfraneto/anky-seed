import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class ClipSessionHandoffTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-handoff-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A canonical sealed session string exactly as the shared
    /// `WritingSessionEngine`/`AnkyWriter` would produce it in the clip.
    private func canonicalSessionText() -> String {
        var writer = AnkyWriter()
        let start: Int64 = 1_752_700_000_000
        var cursor = start
        for character in "hola this is me" {
            _ = writer.accept(character, at: cursor)
            cursor += 137
        }
        writer.closeWithTerminalSilence()
        return writer.text
    }

    func testHandoffRoundTripsByteForByteThroughNormalSessionStorage() throws {
        let container = try temporaryDirectory()
        let archiveDirectory = try temporaryDirectory()
        let indexURL = try temporaryDirectory().appendingPathComponent("session-index.json")
        let reflectionsDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        let sessionText = canonicalSessionText()
        try ClipSessionHandoff.write(
            sessionText: sessionText,
            meta: ClipSessionHandoff.Meta(createdAt: 1_752_700_009_999, clipVersion: "2.0.0", source: "farcaster"),
            to: container
        )

        let archive = LocalAnkyArchive(directoryURL: archiveDirectory)
        let sessionIndexStore = SessionIndexStore(url: indexURL)
        let importer = ClipSessionImporter(
            archive: archive,
            sessionIndexStore: sessionIndexStore,
            reflectionStore: ReflectionStore(directoryURL: reflectionsDirectory)
        )

        let imported = try XCTUnwrap(importer.claimPendingClipSession(container: container))

        // Byte-for-byte through the same storage path a native session takes.
        XCTAssertEqual(imported.text, sessionText)
        let onDisk = try XCTUnwrap(archive.list().first { $0.hash == imported.hash })
        XCTAssertEqual(Data(onDisk.text.utf8), Data(sessionText.utf8))

        // Dated by the protocol's own start epoch.
        XCTAssertEqual(
            imported.createdAt,
            Date(timeIntervalSince1970: 1_752_700_000_000.0 / 1000)
        )

        // Indexed like any other session.
        XCTAssertTrue(sessionIndexStore.load().contains { $0.hash == imported.hash })

        // Claimed exactly once: the container is empty afterwards.
        XCTAssertNil(ClipSessionHandoff.load(from: container))
        XCTAssertNil(importer.claimPendingClipSession(container: container))
    }

    func testMalformedClipSessionIsClearedWithoutImporting() throws {
        let container = try temporaryDirectory()
        let archiveDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        try Data("not an anky protocol string".utf8).write(
            to: container.appendingPathComponent(ClipSessionHandoff.sessionFileName)
        )

        let archive = LocalAnkyArchive(directoryURL: archiveDirectory)
        let importer = ClipSessionImporter(
            archive: archive,
            sessionIndexStore: SessionIndexStore(url: archiveDirectory.appendingPathComponent("index.json")),
            reflectionStore: ReflectionStore(directoryURL: archiveDirectory)
        )

        XCTAssertNil(importer.claimPendingClipSession(container: container))
        XCTAssertTrue(archive.list().isEmpty)
        // The bad payload cannot wedge future launches.
        XCTAssertNil(ClipSessionHandoff.load(from: container))
    }

    func testMissingContainerIsQuietlyIgnored() {
        XCTAssertNil(ClipSessionImporter().claimPendingClipSession(container: nil))
    }
}
