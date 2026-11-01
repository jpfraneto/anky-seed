import XCTest
@testable import Anky

@MainActor
final class DraftRecoveryTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anky-draft-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func draftStore() throws -> (ActiveDraftStore, URL) {
        let directory = try temporaryDirectory()
        return (ActiveDraftStore(baseDirectory: directory), directory)
    }

    func testLaunchAndForegroundRecoveryLoadsValidOpenDraft() throws {
        let (store, _) = try draftStore()
        store.save("""
        1770000000000 h
        250 i
        """)

        let recovery = try XCTUnwrap(store.loadRecoverableDraft())

        XCTAssertEqual(recovery.text, "1770000000000 h\n250 i")
        XCTAssertEqual(recovery.durationMs, 250)
        XCTAssertEqual(recovery.wordCount, 1)
        XCTAssertEqual(recovery.createdAt, Date(timeIntervalSince1970: 1_770_000_000))
    }

    func testRecoveredDraftResumeDoesNotCountTimeSpentAway() throws {
        let draft = """
        1770000000000 h
        250 i
        """
        var engine = try WritingSessionEngine(draftText: draft)

        engine.prepareToResume(at: 1_770_086_400_250)
        _ = engine.accept("!", at: 1_770_086_400_250)

        XCTAssertEqual(engine.protocolText, """
        1770000000000 h
        250 i
        0 !
        """)
        let parsed = try AnkyParser.parse(engine.protocolText)
        XCTAssertEqual(parsed.events.last?.deltaMs, 0)
        XCTAssertEqual(AnkyDuration.durationMs(parsed), 250)
        XCTAssertEqual(AnkyReconstructor.reconstructText(parsed), "hi!")
    }

    func testDiscardConfirmationClearsTheDraft() throws {
        let (store, _) = try draftStore()
        store.save("1770000000000 h")

        XCTAssertNotNil(store.loadRecoverableDraft())

        // The UI owns the confirmation; once confirmed, discard is exactly this clear.
        store.clear()

        XCTAssertNil(store.loadRecoverableDraft())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testCorruptDraftIsQuarantinedAndOriginalIsPreserved() throws {
        let (store, directory) = try draftStore()
        try "not a valid .anky draft".write(to: store.fileURL, atomically: true, encoding: .utf8)

        XCTAssertNil(store.loadRecoverableDraft())

        let quarantineDirectory = directory
            .appendingPathComponent("ActiveDrafts", isDirectory: true)
            .appendingPathComponent("Quarantine", isDirectory: true)
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: quarantineDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(try String(contentsOf: quarantined[0], encoding: .utf8), "not a valid .anky draft")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testTerminalizedOrReflectedImmutableDraftIsNotRecoverable() throws {
        let (store, _) = try draftStore()
        store.save("""
        1770000000000 h
        480000 i
        8000
        """)

        XCTAssertNil(store.loadRecoverableDraft())
    }

    func testReflectionMarkdownKeepsHeadingAndBodyAsSeparateBlocks() {
        let blocks = ReflectionMarkdownBlock.parse("""
        # The App Is You

        You said it yourself and then kept going.

        **Worldview.** This remains part of the body.
        """)

        XCTAssertEqual(blocks, [
            ReflectionMarkdownBlock(kind: .heading(level: 1), text: "The App Is You"),
            ReflectionMarkdownBlock(kind: .paragraph, text: "You said it yourself and then kept going."),
            ReflectionMarkdownBlock(kind: .paragraph, text: "**Worldview.** This remains part of the body.")
        ])
    }
}
