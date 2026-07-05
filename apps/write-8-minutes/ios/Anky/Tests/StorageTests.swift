import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class StorageTests: XCTestCase {
    func testReflectionRequestStorePersistsPendingReflectionByHash() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReflectionRequestStore(defaults: defaults)

        store.markPending(hash: "abc123")

        XCTAssertTrue(ReflectionRequestStore(defaults: defaults).isPending(hash: "abc123"))
        XCTAssertFalse(ReflectionRequestStore(defaults: defaults).isPending(hash: "other"))

        store.clear(hash: "abc123")

        XCTAssertFalse(ReflectionRequestStore(defaults: defaults).isPending(hash: "abc123"))
    }

    func testReflectionRequestStoreExpiresStalePendingReflection() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReflectionRequestStore(defaults: defaults, expirationInterval: 10)
        let startedAt = Date(timeIntervalSince1970: 100)

        store.markPending(hash: "abc123", now: startedAt)

        XCTAssertTrue(store.isPending(hash: "abc123", now: startedAt.addingTimeInterval(9)))
        XCTAssertFalse(store.isPending(hash: "abc123", now: startedAt.addingTimeInterval(11)))
    }

    func testReflectionStoreSavesAndLoadsByHash() throws {
        let directory = temporaryDirectory().appendingPathComponent("reflections", isDirectory: true)
        let store = ReflectionStore(directoryURL: directory)
        let reflection = LocalReflection(
            hash: "abc123",
            title: "Small Thread",
            reflection: "Here is what I saw.",
            createdAt: Date(timeIntervalSince1970: 1_770_000_000),
            creditsRemaining: nil
        )

        try store.save(reflection)

        XCTAssertEqual(store.load(hash: "abc123"), reflection)
        XCTAssertEqual(store.list(), [reflection])
    }

    func testLocalArchivePersistsEachAnkyByHash() throws {
        let directory = temporaryDirectory().appendingPathComponent("ankys", isDirectory: true)
        let archive = LocalAnkyArchive(directoryURL: directory)

        let older = try archive.save("1770000000000 h\n8000")
        let newer = try archive.save("1770000001000 y\n8000")

        XCTAssertEqual(archive.list().first?.hash, newer.hash)
        XCTAssertEqual(archive.list().map(\.hash), [newer.hash, older.hash])
        XCTAssertEqual(archive.fileURLs().count, 2)
        XCTAssertEqual(try archive.load(hash: older.hash).reconstructedText, "h")
    }

    func testLocalArchiveKeepsCompleteAnkyWhenShortAttemptIsSavedLater() throws {
        let directory = temporaryDirectory().appendingPathComponent("ankys", isDirectory: true)
        let archive = LocalAnkyArchive(directoryURL: directory)

        let complete = try archive.save("1770000000000 h\n480000 i\n8000")
        let fragment = try archive.save("1770000100000 n\n10000 o\n8000")

        XCTAssertFalse(fragment.isComplete)
        XCTAssertTrue(try archive.load(hash: complete.hash).isComplete)
        XCTAssertEqual(Set(archive.list().map(\.hash)), Set([complete.hash, fragment.hash]))
    }

    func testLocalArchiveImportsValidAnkyIdempotentlyByHash() throws {
        let directory = temporaryDirectory().appendingPathComponent("ankys", isDirectory: true)
        let archive = LocalAnkyArchive(directoryURL: directory)
        let text = "1770000000000 h\n480000 i"

        let first = try archive.importArtifact(text)
        let second = try archive.importArtifact(text)

        XCTAssertEqual(first.hash, second.hash)
        XCTAssertEqual(second.reconstructedText, "hi")
        XCTAssertEqual(archive.fileURLs().count, 1)
    }

    func testLocalArchiveImportsPastedMarkdownAnky() throws {
        let directory = temporaryDirectory().appendingPathComponent("ankys", isDirectory: true)
        let archive = LocalAnkyArchive(directoryURL: directory)
        let text = """
        here is the .anky:

        ```anky
        1770000000000 h
        480000 i
        ```
        """

        let saved = try archive.importArtifact(text)

        XCTAssertEqual(saved.reconstructedText, "hi")
    }

    func testLocalArchiveImportsPastedAnkyWithSpacePlaceholderAndTrailingWhitespace() throws {
        let directory = temporaryDirectory().appendingPathComponent("ankys", isDirectory: true)
        let archive = LocalAnkyArchive(directoryURL: directory)
        let text = [
            "",
            "    1770000000000 h",
            "    240000 SPACE",
            "    240000 i   ",
            ""
        ].joined(separator: "\n")

        let saved = try archive.importArtifact(text)

        XCTAssertEqual(saved.text, "1770000000000 h\n240000 SPACE\n240000 i")
        XCTAssertEqual(saved.reconstructedText, "h i")
    }

    func testLocalArchiveMigratesLiteralSpacePayloadOnImport() throws {
        let directory = temporaryDirectory().appendingPathComponent("ankys", isDirectory: true)
        let archive = LocalAnkyArchive(directoryURL: directory)

        let saved = try archive.importArtifact("1770000000000 h\n240000  \n240000 i")

        XCTAssertEqual(saved.text, "1770000000000 h\n240000 SPACE\n240000 i")
        XCTAssertEqual(saved.reconstructedText, "h i")
    }

    func testLocalArchiveRejectsPastedAnkyFragmentUnderEightMinutes() throws {
        let directory = temporaryDirectory().appendingPathComponent("ankys", isDirectory: true)
        let archive = LocalAnkyArchive(directoryURL: directory)

        XCTAssertThrowsError(try archive.importArtifact("1770000000000 h\n479999 i")) { error in
            XCTAssertEqual(error as? AnkyImportError, .invalidArtifact)
        }
        XCTAssertTrue(archive.fileURLs().isEmpty)
    }

    func testLocalArchiveRejectsInvalidImportedAnky() throws {
        let directory = temporaryDirectory().appendingPathComponent("ankys", isDirectory: true)
        let archive = LocalAnkyArchive(directoryURL: directory)

        XCTAssertThrowsError(try archive.importArtifact("not a .anky artifact")) { error in
            XCTAssertEqual(error as? AnkyImportError, .invalidArtifact)
        }
        XCTAssertTrue(archive.fileURLs().isEmpty)
    }

    func testSessionIndexRebuildsFromArchiveAndReflections() throws {
        let root = temporaryDirectory()
        let archive = LocalAnkyArchive(directoryURL: root.appendingPathComponent("ankys", isDirectory: true))
        let reflections = ReflectionStore(directoryURL: root.appendingPathComponent("reflections", isDirectory: true))
        let index = SessionIndexStore(url: root.appendingPathComponent("session-index.json"))

        let complete = try archive.save("1770000100000 y\n480000 o\n8000")
        try reflections.save(LocalReflection(
            hash: complete.hash,
            title: "Reflected Title",
            reflection: "Private reflection",
            createdAt: Date(timeIntervalSince1970: 1_770_001_000),
            creditsRemaining: 2
        ))

        let sessions = try index.rebuild(archive: archive, reflectionStore: reflections)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions.contains { $0.hash == complete.hash && $0.isComplete && $0.reflectionTitle == "Reflected Title" })
        XCTAssertEqual(index.load().count, 1)
    }

    func testSessionIndexFindsSessionsByReflectionTag() throws {
        let root = temporaryDirectory()
        let archive = LocalAnkyArchive(directoryURL: root.appendingPathComponent("ankys", isDirectory: true))
        let reflections = ReflectionStore(directoryURL: root.appendingPathComponent("reflections", isDirectory: true))
        let index = SessionIndexStore(url: root.appendingPathComponent("session-index.json"))
        let anky = try archive.save("1770000100000 y\n480000 o\n8000")
        try reflections.save(LocalReflection(
            hash: anky.hash,
            title: "Reflected Title",
            reflection: "Private reflection",
            tags: ["truth", "body"],
            createdAt: anky.createdAt,
            creditsRemaining: 2
        ))

        try index.rebuild(archive: archive, reflectionStore: reflections)

        XCTAssertEqual(index.sessionsWithTag(" truth ").map(\.hash), [anky.hash])
        XCTAssertEqual(index.sessionsWithTag("missing"), [])
    }

    func testDeletingWritingSessionRemovesArchiveReflectionAndIndexEntry() throws {
        let root = temporaryDirectory()
        let archive = LocalAnkyArchive(directoryURL: root.appendingPathComponent("ankys", isDirectory: true))
        let reflections = ReflectionStore(directoryURL: root.appendingPathComponent("reflections", isDirectory: true))
        let index = SessionIndexStore(url: root.appendingPathComponent("session-index.json"))
        let anky = try archive.save("1770000100000 y\n480000 o\n8000")
        try reflections.save(LocalReflection(
            hash: anky.hash,
            title: "Reflected Title",
            reflection: "Private reflection",
            createdAt: anky.createdAt,
            creditsRemaining: 2
        ))
        try index.rebuild(archive: archive, reflectionStore: reflections)

        try archive.delete(anky)
        try reflections.delete(hash: anky.hash)
        try index.delete(hash: anky.hash)

        XCTAssertTrue(archive.list().isEmpty)
        XCTAssertNil(reflections.load(hash: anky.hash))
        XCTAssertTrue(index.load().isEmpty)
    }

    func testSessionSummariesGroupByDayWithCounts() throws {
        let root = temporaryDirectory()
        let firstDay = Date(timeIntervalSince1970: 1_770_000_000)
        let secondDay = firstDay.addingTimeInterval(86_400)
        let sessions = [
            SessionSummary(
                hash: "a",
                createdAt: firstDay,
                localFileURL: root.appendingPathComponent("a.anky"),
                durationMs: 8_000,
                isComplete: false,
                preview: "first",
                hasReflection: false,
                reflectionTitle: nil
            ),
            SessionSummary(
                hash: "b",
                createdAt: secondDay,
                localFileURL: root.appendingPathComponent("b.anky"),
                durationMs: 488_000,
                isComplete: true,
                preview: "second",
                hasReflection: true,
                reflectionTitle: "title"
            )
        ]

        let days = sessions.groupedByDay(firstOpenDate: firstDay, now: secondDay)

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.first?.completeCount, 1)
        XCTAssertEqual(days.first?.reflectionCount, 1)
        XCTAssertEqual(days.first?.latestPreviewOrTitle, "title")
        XCTAssertEqual(days.first?.activitySummary, "1 anky · 1 reflection")
        XCTAssertEqual(days.last?.fragmentCount, 1)
        XCTAssertEqual(days.last?.activitySummary, "1 fragment")
    }

    func testSessionDaysAnchorToEarliestSessionBeforeFirstOpenDate() throws {
        let root = temporaryDirectory()
        let yesterday = Date(timeIntervalSince1970: 1_770_000_000)
        let today = yesterday.addingTimeInterval(86_400)
        let sessions = [
            SessionSummary(
                hash: "a",
                createdAt: yesterday,
                localFileURL: root.appendingPathComponent("a.anky"),
                durationMs: 8_000,
                isComplete: false,
                preview: "yesterday",
                hasReflection: false,
                reflectionTitle: nil
            ),
            SessionSummary(
                hash: "b",
                createdAt: today,
                localFileURL: root.appendingPathComponent("b.anky"),
                durationMs: 8_000,
                isComplete: false,
                preview: "today",
                hasReflection: false,
                reflectionTitle: nil
            )
        ]

        let days = sessions.groupedByDay(firstOpenDate: today, now: today)

        XCTAssertEqual(days.first?.ankyversePosition.dayIndex, 2)
        XCTAssertEqual(days.last?.ankyversePosition.dayIndex, 1)
    }

    func testContinuousSessionDaysIncludeEmptyCurrentDay() throws {
        let root = temporaryDirectory()
        let firstDay = Date(timeIntervalSince1970: 1_770_000_000)
        let currentDay = firstDay.addingTimeInterval(86_400 * 2)
        let sessions = [
            SessionSummary(
                hash: "a",
                createdAt: firstDay,
                localFileURL: root.appendingPathComponent("a.anky"),
                durationMs: 488_000,
                isComplete: true,
                preview: "first",
                hasReflection: false,
                reflectionTitle: nil
            )
        ]

        let days = sessions.groupedByContinuousDays(firstOpenDate: firstDay, now: currentDay)

        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days.first?.completeCount, 1)
        XCTAssertEqual(days[1].activitySummary, "No writing")
        XCTAssertEqual(days.last?.date, Calendar.ankyUTC.startOfDay(for: currentDay))
        XCTAssertEqual(days.last?.trailActivitySummary, "No writing")
        XCTAssertTrue(days.last?.isToday == true)
    }

    func testTrailCompletionMarkerIsBinaryAndIgnoresFragments() throws {
        let root = temporaryDirectory()
        let day = Date(timeIntervalSince1970: 1_770_000_000)
        let fragment = SessionSummary(
            hash: "fragment",
            createdAt: day,
            localFileURL: root.appendingPathComponent("fragment.anky"),
            durationMs: 8_000,
            isComplete: false,
            preview: "fragment",
            hasReflection: false,
            reflectionTitle: nil
        )
        let oneComplete = SessionSummary(
            hash: "complete-1",
            createdAt: day,
            localFileURL: root.appendingPathComponent("complete-1.anky"),
            durationMs: 488_000,
            isComplete: true,
            preview: "complete",
            hasReflection: false,
            reflectionTitle: nil
        )
        let manyComplete = (0..<8).map { index in
            SessionSummary(
                hash: "complete-\(index)",
                createdAt: day.addingTimeInterval(Double(index)),
                localFileURL: root.appendingPathComponent("complete-\(index).anky"),
                durationMs: 488_000,
                isComplete: true,
                preview: "complete",
                hasReflection: false,
                reflectionTitle: nil
            )
        }

        let fragmentDay = [fragment].groupedByContinuousDays(firstOpenDate: day, now: day).first
        let oneDay = [oneComplete].groupedByContinuousDays(firstOpenDate: day, now: day).first
        let manyDay = manyComplete.groupedByContinuousDays(firstOpenDate: day, now: day).first

        XCTAssertFalse(fragmentDay?.showsTrailCompletionMarker ?? true)
        XCTAssertTrue(oneDay?.showsTrailCompletionMarker == true)
        XCTAssertEqual(oneDay?.showsTrailCompletionMarker, manyDay?.showsTrailCompletionMarker)
        XCTAssertEqual(oneDay?.trailActivitySummary, manyDay?.trailActivitySummary)
    }

    func testCompleteRitualGateUsesLocalCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -3 * 60 * 60)!
        let root = temporaryDirectory()
        let today = Date(timeIntervalSince1970: 1_770_000_000)
        let complete = SessionSummary(
            hash: "complete",
            createdAt: today,
            localFileURL: root.appendingPathComponent("complete.anky"),
            durationMs: 488_000,
            isComplete: true,
            preview: "complete",
            hasReflection: false,
            reflectionTitle: nil
        )
        let fragment = SessionSummary(
            hash: "fragment",
            createdAt: today.addingTimeInterval(100),
            localFileURL: root.appendingPathComponent("fragment.anky"),
            durationMs: 8_000,
            isComplete: false,
            preview: "fragment",
            hasReflection: false,
            reflectionTitle: nil
        )

        XCTAssertTrue([fragment, complete].hasCompleteRitual(on: today, calendar: calendar))
        XCTAssertFalse([fragment].hasCompleteRitual(on: today, calendar: calendar))
        XCTAssertFalse([complete].hasCompleteRitual(on: today.addingTimeInterval(86_400), calendar: calendar))
    }

    func testBackupImporterImportsZipBackupAnkysAndReflections() throws {
        let sourceRoot = temporaryDirectory()
        let files = sourceRoot.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

        let backupAnkyText = "1770000000000 h\n480000 SPACE\n0200 i\n8000"
        let normalizedAnkyText = "1770000000000 h\n480000 SPACE\n0200 i\n8000"
        let backupHash = AnkyHasher.sha256Hex(backupAnkyText)
        let localHash = AnkyHasher.sha256Hex(normalizedAnkyText)
        try Data(backupAnkyText.utf8).write(to: files.appendingPathComponent("\(backupHash).anky"))
        try Data("Imported Thread".utf8).write(to: files.appendingPathComponent("\(backupHash).title.txt"))
        try Data("Imported reflection body".utf8).write(to: files.appendingPathComponent("\(backupHash).reflection.md"))
        try Data("""
        {"created_at":"2026-05-14T15:44:58.914Z","credits_remaining":3}
        """.utf8).write(to: files.appendingPathComponent("\(backupHash).processing.json"))
        try Data("{\"exportVersion\":1}".utf8).write(to: sourceRoot.appendingPathComponent("manifest.json"))

        let zipURL = sourceRoot.appendingPathComponent("backup.zip")
        try runZip(in: sourceRoot, output: zipURL)

        let destinationRoot = temporaryDirectory()
        let archive = LocalAnkyArchive(directoryURL: destinationRoot.appendingPathComponent("ankys", isDirectory: true))
        let reflections = ReflectionStore(directoryURL: destinationRoot.appendingPathComponent("reflections", isDirectory: true))
        let index = SessionIndexStore(url: destinationRoot.appendingPathComponent("session-index.json"))
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appOpenStore = AppOpenStore(defaults: defaults)
        let firstLocalOpen = Date(timeIntervalSince1970: 1_780_000_000)
        appOpenStore.loadOrCreate(now: firstLocalOpen)
        let importer = BackupImporter(
            archive: archive,
            reflectionStore: reflections,
            sessionIndexStore: index,
            appOpenStore: appOpenStore
        )

        let result = try importer.importBackup(from: zipURL)

        XCTAssertEqual(result, BackupImportResult(ankyCount: 1, reflectionCount: 1))
        XCTAssertEqual(archive.list().map(\.hash), [localHash])
        XCTAssertEqual(archive.list().first?.reconstructedText, "h i")
        XCTAssertEqual(reflections.load(hash: localHash)?.title, "Imported Thread")
        XCTAssertEqual(reflections.load(hash: localHash)?.reflection, "Imported reflection body")
        XCTAssertEqual(reflections.load(hash: localHash)?.creditsRemaining, 3)
        XCTAssertEqual(index.load().first?.reflectionTitle, "Imported Thread")
        XCTAssertEqual(appOpenStore.loadOrCreate(), Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000)))
    }

    func testBackupExporterCreatesZipBackupThatImporterRestores() throws {
        let sourceRoot = temporaryDirectory()
        let sourceArchive = LocalAnkyArchive(directoryURL: sourceRoot.appendingPathComponent("ankys", isDirectory: true))
        let sourceReflections = ReflectionStore(directoryURL: sourceRoot.appendingPathComponent("reflections", isDirectory: true))
        let anky = try sourceArchive.save("1770000000000 h\n480000 SPACE\n0200 i\n8000")
        try sourceReflections.save(LocalReflection(
            hash: anky.hash,
            title: "Exported Thread",
            reflection: "Exported reflection body",
            createdAt: anky.createdAt,
            creditsRemaining: 2
        ))

        let backupURL = try XCTUnwrap(BackupExporter(
            archive: sourceArchive,
            reflectionStore: sourceReflections
        ).exportBackup())

        let destinationRoot = temporaryDirectory()
        let destinationArchive = LocalAnkyArchive(directoryURL: destinationRoot.appendingPathComponent("ankys", isDirectory: true))
        let destinationReflections = ReflectionStore(directoryURL: destinationRoot.appendingPathComponent("reflections", isDirectory: true))
        let destinationIndex = SessionIndexStore(url: destinationRoot.appendingPathComponent("session-index.json"))
        let result = try BackupImporter(
            archive: destinationArchive,
            reflectionStore: destinationReflections,
            sessionIndexStore: destinationIndex
        ).importBackup(from: backupURL)

        XCTAssertEqual(result, BackupImportResult(ankyCount: 1, reflectionCount: 1))
        XCTAssertEqual(destinationArchive.list().first?.hash, anky.hash)
        XCTAssertEqual(destinationReflections.load(hash: anky.hash)?.title, "Exported Thread")
        XCTAssertEqual(destinationReflections.load(hash: anky.hash)?.reflection, "Exported reflection body")
        XCTAssertEqual(destinationIndex.load().first?.reflectionTitle, "Exported Thread")
    }

    func testICloudBackupEnvelopeEncryptsAndDecryptsWithRecoveryPhrase() throws {
        let phrase = try RecoveryPhrase.generate()
        let otherPhrase = try RecoveryPhrase.generate()
        let plaintext = Data("private writing and reflections".utf8)

        let envelope = try ICloudBackupStore.encrypt(plaintext, recoveryPhrase: phrase)
        XCTAssertNotEqual(envelope.payload, plaintext)
        XCTAssertEqual(try ICloudBackupStore.decrypt(envelope, recoveryPhrase: phrase), plaintext)
        XCTAssertThrowsError(try ICloudBackupStore.decrypt(envelope, recoveryPhrase: otherPhrase))
    }

    func testAppOpenStorePersistsFirstOpenDate() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppOpenStore(defaults: defaults)
        let first = Date(timeIntervalSince1970: 1_770_000_000)
        let later = Date(timeIntervalSince1970: 1_780_000_000)

        XCTAssertEqual(store.loadOrCreate(now: first), first)
        XCTAssertEqual(store.loadOrCreate(now: later), first)
    }

    func testAppOpenStoreMovesFirstOpenDateEarlierOnly() throws {
        let suiteName = "anky.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppOpenStore(defaults: defaults)
        let first = Date(timeIntervalSince1970: 1_780_000_000)
        let earlier = Date(timeIntervalSince1970: 1_770_000_000)
        let later = Date(timeIntervalSince1970: 1_790_000_000)

        XCTAssertEqual(store.loadOrCreate(now: first), first)
        XCTAssertEqual(store.recordEarlierFirstOpenDate(later), first)
        XCTAssertEqual(store.recordEarlierFirstOpenDate(earlier), Calendar.current.startOfDay(for: earlier))
        XCTAssertEqual(store.loadOrCreate(), Calendar.current.startOfDay(for: earlier))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func runZip(in directory: URL, output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", "-r", output.path, "manifest.json", "files"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
