import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class ExpressionSessionTests: XCTestCase {
    private var root: URL!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("anky-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func store() -> ExpressionSessionStore {
        ExpressionSessionStore(rootURL: root.appendingPathComponent("Sessions", isDirectory: true))
    }

    // MARK: Creation, persistence, recovery

    func testSessionRoundTripsAndIsTheActiveOne() throws {
        let store = store()
        var session = ExpressionSession(startedAt: t0, setting: .walking)
        ExpressionSessionLifecycle.open(ExpressionSegment(kind: .silence, startedAt: t0), in: &session, now: t0)
        try store.save(session)

        let loaded = try store.load(id: session.id)
        XCTAssertEqual(loaded, session)
        XCTAssertEqual(store.activeSession()?.id, session.id)
        XCTAssertEqual(loaded.format, "anky.session")
        XCTAssertEqual(loaded.version, 1)
    }

    func testEndedSessionIsNoLongerActive() throws {
        let store = store()
        var session = ExpressionSession(startedAt: t0)
        ExpressionSessionLifecycle.end(&session, now: t0.addingTimeInterval(600))
        try store.save(session)
        XCTAssertNil(store.activeSession())
        XCTAssertEqual(store.list().first?.endedAt, t0.addingTimeInterval(600))
    }

    func testSwitchingMediumsClosesThePreviousSegment() {
        var session = ExpressionSession(startedAt: t0)
        let voice = ExpressionSegment(kind: .voice, startedAt: t0, mediaFile: "media/a.caf")
        ExpressionSessionLifecycle.open(voice, in: &session, now: t0)
        let video = ExpressionSegment(kind: .video, startedAt: t0.addingTimeInterval(60), mediaFile: "media/b.mov")
        ExpressionSessionLifecycle.open(video, in: &session, now: t0.addingTimeInterval(60))

        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.segments[0].status, .complete)
        XCTAssertEqual(session.segments[0].endedAt, t0.addingTimeInterval(60))
        XCTAssertEqual(session.segments[0].durationMs, 60_000)
        XCTAssertEqual(session.openSegment?.id, video.id)
        XCTAssertEqual(session.expressedKinds, [.voice, .video])
    }

    func testWritingJoinsSessionAndAResealReplacesItsHash() {
        var session = ExpressionSession(startedAt: t0)
        ExpressionSessionLifecycle.recordWriting(
            hash: "aaa", replacing: nil, startedAt: t0, durationMs: 480_000,
            in: &session, now: t0.addingTimeInterval(490)
        )
        // The same writing, reopened and resealed: one segment, new hash.
        ExpressionSessionLifecycle.recordWriting(
            hash: "bbb", replacing: "aaa", startedAt: t0, durationMs: 600_000,
            in: &session, now: t0.addingTimeInterval(700)
        )
        XCTAssertEqual(session.segments.count, 1)
        XCTAssertEqual(session.writingHashes, ["bbb"])
        XCTAssertEqual(session.segments[0].durationMs, 600_000)

        // A duplicate seal callback never adds a second copy.
        ExpressionSessionLifecycle.recordWriting(
            hash: "bbb", replacing: nil, startedAt: t0, durationMs: 600_000,
            in: &session, now: t0.addingTimeInterval(701)
        )
        XCTAssertEqual(session.segments.count, 1)
    }

    func testRecoveryClosesInterruptedCaptureAtItsLastWrite() throws {
        let store = store()
        var session = ExpressionSession(startedAt: t0)
        let mediaFolder = try store.mediaFolderURL(for: session.id)
        let file = mediaFolder.appendingPathComponent("voice.caf")
        try Data([1, 2, 3]).write(to: file)
        let lastWrite = t0.addingTimeInterval(95)
        try FileManager.default.setAttributes([.modificationDate: lastWrite], ofItemAtPath: file.path)

        ExpressionSessionLifecycle.open(
            ExpressionSegment(kind: .voice, startedAt: t0.addingTimeInterval(5), mediaFile: "media/voice.caf"),
            in: &session, now: t0.addingTimeInterval(5)
        )
        try store.save(session)

        // The app was killed. Next launch:
        var recovered = try XCTUnwrap(store.activeSession())
        let sessionID = recovered.id
        ExpressionSessionLifecycle.recover(&recovered, now: t0.addingTimeInterval(3600)) {
            store.lastWriteDate(of: $0, sessionID: sessionID)
        }
        let segment = try XCTUnwrap(recovered.segments.first)
        XCTAssertEqual(segment.status, .recovered)
        XCTAssertEqual(segment.endedAt?.timeIntervalSince1970 ?? 0, lastWrite.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(segment.durationMs ?? 0, 90_000, accuracy: 10)
        XCTAssertTrue(recovered.isActive, "recovery keeps the session open for the person to continue or end")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "recovery never deletes media")
    }

    // MARK: Format safety

    func testUnknownKindsAndFieldsStillRead() throws {
        let json = """
        {"format":"anky.session","version":1,"id":"\(UUID().uuidString)",
         "startedAt":"2027-01-15T08:00:00.000Z","segments":[
           {"id":"\(UUID().uuidString)","kind":"hologram","startedAt":"2027-01-15T08:00:00.000Z",
            "status":"complete","futureField":42}],
         "anotherFutureField":"x"}
        """
        let session = try JSONDecoder.sessionDecoder.decode(ExpressionSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.segments.first?.kind, .unknown)
    }

    func testNewerManifestIsNeverRewritten() throws {
        let store = store()
        var session = ExpressionSession(startedAt: t0)
        session.version = 99
        let folder = store.folderURL(for: session.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder.sessionEncoder.encode(session)
            .write(to: folder.appendingPathComponent(ExpressionSessionStore.manifestName))

        var edited = session
        edited.version = 1
        XCTAssertThrowsError(try store.save(edited)) { error in
            XCTAssertEqual(error as? ExpressionSessionStoreError, .newerFormat)
        }
    }

    func testUnreadableManifestIsSkippedNotDeleted() throws {
        let store = store()
        let broken = store.rootURL.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        let manifest = broken.appendingPathComponent(ExpressionSessionStore.manifestName)
        try Data("{not json".utf8).write(to: manifest)
        XCTAssertEqual(store.list(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
    }

    // MARK: Historical writings and export

    func testHistoricalWritingsAreNotWrappedOrRelabeled() throws {
        let archive = LocalAnkyArchive(directoryURL: root.appendingPathComponent("Ankys", isDirectory: true))
        let legacy = try archive.save(Self.sampleAnky(word: "before"))
        let store = store()
        XCTAssertTrue(store.list().isEmpty, "no session is invented for an old writing")
        XCTAssertFalse(store.writingHashesInSessions().contains(legacy.hash))
        // The .anky file is untouched.
        XCTAssertEqual(try String(contentsOf: legacy.url, encoding: .utf8), Self.sampleAnky(word: "before"))
    }

    func testExportIncludesSessionsMediaAndStandaloneWritings() throws {
        let archive = LocalAnkyArchive(directoryURL: root.appendingPathComponent("Ankys", isDirectory: true))
        let reflections = ReflectionStore(directoryURL: root.appendingPathComponent("Reflections", isDirectory: true))
        let store = store()

        let legacy = try archive.save(Self.sampleAnky(word: "legacy"))
        let walked = try archive.save(Self.sampleAnky(word: "walking"))

        var session = ExpressionSession(startedAt: t0, setting: .walking)
        let media = try store.mediaFolderURL(for: session.id).appendingPathComponent("voice-1.m4a")
        try Data(repeating: 7, count: 2048).write(to: media)
        ExpressionSessionLifecycle.open(
            ExpressionSegment(kind: .voice, startedAt: t0, mediaFile: "media/voice-1.m4a"),
            in: &session, now: t0
        )
        ExpressionSessionLifecycle.recordWriting(
            hash: walked.hash, replacing: nil, startedAt: t0.addingTimeInterval(60),
            durationMs: 60_000, in: &session, now: t0.addingTimeInterval(120)
        )
        ExpressionSessionLifecycle.end(&session, now: t0.addingTimeInterval(200))
        try store.save(session)

        let exportParent = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportParent, withIntermediateDirectories: true)
        let result = try MemoryExportBuilder(sessions: store, archive: archive, reflections: reflections)
            .build(into: exportParent, now: t0)

        XCTAssertEqual(result.sessionCount, 1)
        XCTAssertEqual(result.writingCount, 2)
        XCTAssertEqual(result.mediaCount, 1)

        let fm = FileManager.default
        let sessionFolders = try fm.contentsOfDirectory(atPath: result.folderURL.appendingPathComponent("sessions").path)
        XCTAssertEqual(sessionFolders.count, 1)
        XCTAssertTrue(sessionFolders[0].hasSuffix("· walking"))
        let sessionFolder = result.folderURL.appendingPathComponent("sessions").appendingPathComponent(sessionFolders[0])
        XCTAssertTrue(fm.fileExists(atPath: sessionFolder.appendingPathComponent("session.json").path))
        XCTAssertEqual(try Data(contentsOf: sessionFolder.appendingPathComponent("media/voice-1.m4a")).count, 2048)
        XCTAssertEqual(
            try String(contentsOf: sessionFolder.appendingPathComponent("writing 1.anky"), encoding: .utf8),
            walked.text
        )
        XCTAssertEqual(
            try String(contentsOf: sessionFolder.appendingPathComponent("writing 1.txt"), encoding: .utf8),
            walked.reconstructedText
        )

        let standalone = try fm.contentsOfDirectory(atPath: result.folderURL.appendingPathComponent("writings").path)
        XCTAssertEqual(standalone.filter { $0.hasSuffix(".anky") }.count, 1)
        let standaloneText = try String(
            contentsOf: result.folderURL.appendingPathComponent("writings").appendingPathComponent(standalone.first { $0.hasSuffix(".anky") }!),
            encoding: .utf8
        )
        XCTAssertEqual(standaloneText, legacy.text)
        XCTAssertTrue(fm.fileExists(atPath: result.folderURL.appendingPathComponent("README.txt").path))
    }

    /// A small valid .anky artifact (protocol: first line epoch ms + char,
    /// then delta lines, then the terminal 8000 marker).
    static func sampleAnky(word: String) -> String {
        var lines: [String] = []
        for (index, character) in word.enumerated() {
            lines.append(index == 0 ? "1700000000000 \(character)" : "0100 \(character)")
        }
        lines.append("8000")
        return lines.joined(separator: "\n")
    }
}
