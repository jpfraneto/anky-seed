import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class StorageTests: XCTestCase {
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

    func testLocalArchiveListsSavedAnkysNewestFirst() throws {
        let directory = temporaryDirectory().appendingPathComponent("ankys", isDirectory: true)
        let archive = LocalAnkyArchive(directoryURL: directory)

        _ = try archive.save("1770000000000 h\n8000")
        let newer = try archive.save("1770000001000 y\n8000")

        XCTAssertEqual(archive.list().first?.hash, newer.hash)
        XCTAssertEqual(archive.fileURLs().count, 2)
    }

    func testSessionIndexRebuildsFromArchiveAndReflections() throws {
        let root = temporaryDirectory()
        let archive = LocalAnkyArchive(directoryURL: root.appendingPathComponent("ankys", isDirectory: true))
        let reflections = ReflectionStore(directoryURL: root.appendingPathComponent("reflections", isDirectory: true))
        let index = SessionIndexStore(url: root.appendingPathComponent("session-index.json"))

        let fragment = try archive.save("1770000000000 h\n8000")
        let complete = try archive.save("1770000100000 y\n480000 o\n8000")
        try reflections.save(LocalReflection(
            hash: complete.hash,
            title: "Reflected Title",
            reflection: "Private reflection",
            createdAt: Date(timeIntervalSince1970: 1_770_001_000),
            creditsRemaining: 2
        ))

        let sessions = try index.rebuild(archive: archive, reflectionStore: reflections)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.contains { $0.hash == fragment.hash && !$0.isComplete && !$0.hasReflection })
        XCTAssertTrue(sessions.contains { $0.hash == complete.hash && $0.isComplete && $0.reflectionTitle == "Reflected Title" })
        XCTAssertEqual(index.load().count, 2)
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
        XCTAssertEqual(days.last?.date, Calendar.current.startOfDay(for: currentDay))
        XCTAssertEqual(days.last?.trailActivitySummary, "No writing")
        XCTAssertTrue(days.last?.isToday == true)
    }

    func testBackupImporterImportsZipBackupAnkysAndReflections() throws {
        let sourceRoot = temporaryDirectory()
        let files = sourceRoot.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

        let backupAnkyText = "1770000000000 h\n480000 SPACE\n0200 i\n8000"
        let normalizedAnkyText = "1770000000000 h\n480000  \n0200 i\n8000"
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
        let anky = try sourceArchive.save("1770000000000 h\n480000  \n0200 i\n8000")
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
