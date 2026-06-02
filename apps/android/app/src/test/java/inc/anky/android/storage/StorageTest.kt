package inc.anky.android.storage

import inc.anky.android.core.storage.ActiveDraftStore
import inc.anky.android.core.storage.BackupImportResult
import inc.anky.android.core.storage.BackupImporter
import inc.anky.android.core.storage.BackupZipWriter
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.ReflectionRequestStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.core.storage.SingleAnkyImporter
import inc.anky.android.core.storage.startOfLocalDay
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.json.JSONObject

class StorageTest {
    @get:Rule val temp = TemporaryFolder()
    private val validHash = "a".repeat(64)

    @Test
    fun activeDraftSaveRestoreClearWorks() {
        val store = ActiveDraftStore.forDirectory(temp.newFolder("draft"))
        store.save("1770000000000 h")
        assertEquals("1770000000000 h", store.load())
        store.clear()
        assertNull(store.load())
    }

    @Test
    fun activeDraftLoadsOnlyOpenLegacyDraftLikeIos() {
        val active = temp.newFolder("active-drafts")
        val legacy = temp.newFolder("legacy-ankys")
        val legacyFile = File(legacy, LocalAnkyArchive.CanonicalFileName)
        val store = ActiveDraftStore.forDirectories(active, legacy)

        legacyFile.writeText("1770000000000 h", Charsets.UTF_8)
        assertEquals("1770000000000 h", store.load())

        legacyFile.writeText("1770000000000 h\n8000", Charsets.UTF_8)
        assertNull(store.load())
    }

    @Test
    fun activeDraftClearOnlyRemovesOpenLegacyDraftLikeIos() {
        val active = temp.newFolder("active-drafts")
        val legacy = temp.newFolder("legacy-ankys")
        val activeFile = File(active, LocalAnkyArchive.CanonicalFileName)
        val legacyFile = File(legacy, LocalAnkyArchive.CanonicalFileName)
        val store = ActiveDraftStore.forDirectories(active, legacy)

        store.save("1770000000000 h")
        legacyFile.writeText("1770000001000 i", Charsets.UTF_8)
        store.clear()
        assertFalse(activeFile.exists())
        assertFalse(legacyFile.exists())

        legacyFile.writeText("1770000001000 i\n8000", Charsets.UTF_8)
        store.clear()
        assertTrue(legacyFile.exists())
    }

    @Test
    fun archiveSaveReadListWorks() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val artifact = archive.save("1770000000000 h\n0042 e\n8000")
        assertEquals("he", artifact.reconstructedText)
        assertEquals("${artifact.hash}.anky", artifact.file.name)
        assertEquals(artifact.hash, archive.load(artifact.hash).hash)
        assertEquals(1, archive.list().size)
    }

    @Test
    fun archivePersistsMultipleHashNamedDotAnkyFiles() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val first = archive.save("1770000000000 h\n8000")
        val second = archive.save("1770000001000 i\n8000")

        assertEquals(2, archive.fileList().size)
        assertEquals(setOf("${first.hash}.anky", "${second.hash}.anky"), archive.fileList().map { it.name }.toSet())
        assertEquals(listOf(second.hash, first.hash), archive.list().map { it.hash })
        assertEquals("h", archive.load(first.hash).reconstructedText)
        assertEquals("i", archive.load(second.hash).reconstructedText)
    }

    @Test
    fun archiveClearRemovesLocalAnkyFiles() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        archive.save("1770000000000 h\n0042 e\n8000")

        archive.clear()

        assertEquals(0, archive.list().size)
    }

    @Test
    fun archiveRejectsNonHashLoadPaths() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        try {
            archive.load("../session-index")
            fail("Expected invalid hash rejection")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message!!.contains("Invalid .anky hash."))
        }
    }

    @Test
    fun archiveDoesNotWriteInvalidAnkyFiles() {
        val directory = temp.newFolder("ankys")
        val archive = LocalAnkyArchive.forDirectory(directory)
        try {
            archive.save("not-a-timestamp h\n8000")
            fail("Expected invalid .anky rejection")
        } catch (_: Throwable) {
            assertEquals(0, directory.listFiles { file -> file.extension == "anky" }!!.size)
        }
    }

    @Test
    fun reflectionSaveReadByHashWorks() {
        val store = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val reflection = LocalReflection(validHash, "Small Thread", "Here is what I saw.", Instant.EPOCH, 3, tags = listOf("truth", "body"))
        store.save(reflection)
        assertEquals(reflection, store.load(validHash))
    }

    @Test
    fun reflectionClearRemovesLocalReflectionFiles() {
        val store = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        store.save(LocalReflection(validHash, "Small Thread", "Here is what I saw.", Instant.EPOCH, 3))

        store.clear()

        assertEquals(0, store.list().size)
        assertNull(store.load(validHash))
    }

    @Test
    fun reflectionStoreRejectsNonHashPaths() {
        val store = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        try {
            store.save(LocalReflection("../escape", "Small Thread", "Here is what I saw.", Instant.EPOCH, 3))
            fail("Expected invalid reflection hash rejection")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message!!.contains("Invalid reflection hash."))
        }
        assertEquals(0, store.fileList().size)
    }

    @Test
    fun reflectionRequestStoreTracksAndExpiresPendingHashes() {
        val store = ReflectionRequestStore.forFile(File(temp.newFolder("requests"), "pending.json"), expirationMs = 1000)
        store.markPending(validHash, nowMs = 10_000)

        assertTrue(store.isPending(validHash, nowMs = 10_500))
        assertFalse(store.isPending(validHash, nowMs = 11_500))

        store.markPending(validHash, nowMs = 12_000)
        store.clear(validHash, nowMs = 12_100)
        assertFalse(store.isPending(validHash, nowMs = 12_200))
    }

    @Test
    fun sessionIndexRebuildAndReflectionUpdateWorks() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val artifact = archive.save("1770000000000 h\n0042 e\n8000")

        val sessions = index.rebuild(archive, reflections)
        assertEquals(1, sessions.size)
        assertEquals("he", sessions.first().preview)
        assertTrue(SessionIndexStore.groupByDay(sessions).isNotEmpty())

        index.updateReflection(artifact.hash, "Small Thread", tags = listOf("truth", "body"))
        assertEquals("Small Thread", index.load().first().reflectionTitle)
        assertEquals(listOf("truth", "body"), index.load().first().tags)
        assertEquals(listOf(artifact.hash), index.sessionsWithTag("truth").map { it.hash })

        index.clear()
        assertEquals(0, index.load().size)
    }

    @Test
    fun sessionPreviewTruncatesBySwiftCharacterCount() {
        val composed = "e\u0301"
        val family = "\uD83D\uDC68\u200D\uD83D\uDC69\u200D\uD83D\uDC67\u200D\uD83D\uDC66"
        val flag = "\uD83C\uDDFA\uD83C\uDDF8"
        val ninetySixSwiftCharacters = composed.repeat(94) + family + flag

        assertEquals(ninetySixSwiftCharacters, SessionSummary.preview(ninetySixSwiftCharacters))
        assertEquals(
            ninetySixSwiftCharacters + "...",
            SessionSummary.preview(ninetySixSwiftCharacters + composed),
        )
    }

    @Test
    fun continuousSessionDaysIncludeEmptyCurrentDay() {
        val firstDay = Instant.parse("2026-02-01T12:00:00Z")
        val currentDay = Instant.parse("2026-02-03T12:00:00Z")
        val sessions = listOf(
            SessionSummary(
                hash = "a",
                createdAt = firstDay,
                localFilePath = File(temp.root, "a.anky").absolutePath,
                durationMs = 488_000,
                isComplete = true,
                preview = "first",
                wordCount = 1,
                hasReflection = false,
                reflectionTitle = null,
            ),
        )

        val days = SessionIndexStore.groupByContinuousDays(sessions, firstDay, currentDay, ZoneOffset.UTC)

        assertEquals(3, days.size)
        assertEquals(1, days.first().completeCount)
        assertEquals(1, days.first().dayInRegion)
        assertEquals(0, days[1].sessions.size)
        assertEquals(0, days[1].completeCount)
        assertEquals(0, days[1].fragmentCount)
        assertEquals(2, days[1].dayInRegion)
        assertEquals(0, days.last().sessions.size)
        assertEquals(3, days.last().dayInRegion)
    }

    @Test
    fun continuousSessionDaysClampCorruptVeryOldFirstOpenDates() {
        val firstDay = Instant.parse("1970-01-01T12:00:00Z")
        val currentDay = Instant.parse("2026-02-03T12:00:00Z")

        val days = SessionIndexStore.groupByContinuousDays(emptyList(), firstDay, currentDay, ZoneOffset.UTC)

        assertEquals(3651, days.size)
        assertEquals(currentDay.atZone(ZoneOffset.UTC).toLocalDate(), Instant.ofEpochMilli(days.last().dayEpochMs).atZone(ZoneOffset.UTC).toLocalDate())
    }

    @Test
    fun continuousSessionDaysCountCompleteFragmentsAndReflections() {
        val day = Instant.parse("2026-02-01T12:00:00Z")
        val sessions = listOf(
            SessionSummary(
                hash = "a",
                createdAt = day.plusSeconds(30),
                localFilePath = File(temp.root, "a.anky").absolutePath,
                durationMs = 488_000,
                isComplete = true,
                preview = "complete with reflection",
                wordCount = 3,
                hasReflection = true,
                reflectionTitle = "Small Thread",
            ),
            SessionSummary(
                hash = "b",
                createdAt = day.plusSeconds(10),
                localFilePath = File(temp.root, "b.anky").absolutePath,
                durationMs = 42_000,
                isComplete = false,
                preview = "fragment",
                wordCount = 1,
                hasReflection = false,
                reflectionTitle = null,
            ),
        )

        val days = SessionIndexStore.groupByContinuousDays(sessions, day, day.plusSeconds(60), ZoneOffset.UTC)

        assertEquals(1, days.size)
        assertEquals(1, days.single().completeCount)
        assertEquals(1, days.single().fragmentCount)
        assertEquals(1, days.single().reflectionCount)
        assertEquals(listOf("a", "b"), days.single().sessions.map { it.hash })
    }

    @Test
    fun trailCompletionMarkerIsBinaryAndIgnoresFragments() {
        val day = Instant.parse("2026-02-01T12:00:00Z")
        val fragment = sessionSummary("fragment", day, isComplete = false)
        val oneComplete = sessionSummary("complete-1", day, isComplete = true)
        val manyComplete = (0 until 8).map { index ->
            sessionSummary("complete-$index", day.plusSeconds(index.toLong()), isComplete = true)
        }

        val fragmentDay = SessionIndexStore.groupByContinuousDays(listOf(fragment), day, day, ZoneOffset.UTC).first()
        val oneDay = SessionIndexStore.groupByContinuousDays(listOf(oneComplete), day, day, ZoneOffset.UTC).first()
        val manyDay = SessionIndexStore.groupByContinuousDays(manyComplete, day, day, ZoneOffset.UTC).first()

        assertFalse(fragmentDay.showsTrailCompletionMarker)
        assertEquals("No complete anky", fragmentDay.trailActivitySummary)
        assertTrue(oneDay.showsTrailCompletionMarker)
        assertEquals(oneDay.showsTrailCompletionMarker, manyDay.showsTrailCompletionMarker)
        assertEquals(oneDay.trailActivitySummary, manyDay.trailActivitySummary)
    }

    @Test
    fun importedFirstOpenDatesSnapToLocalStartOfDayLikeIos() {
        val zone = ZoneId.of("America/Santiago")
        val importedSessionTime = Instant.parse("2026-05-14T18:44:58Z")

        assertEquals(
            Instant.parse("2026-05-14T04:00:00Z"),
            importedSessionTime.startOfLocalDay(zone),
        )
    }

    @Test
    fun backupZipWriterMatchesIosExportShape() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val artifact = archive.save("1770000000000 h\n0042 i\n8000")
        val reflection = LocalReflection(
            hash = artifact.hash,
            title = "Small Thread",
            reflection = "Here is what I saw.",
            createdAt = Instant.parse("2026-05-14T15:44:58Z"),
            creditsRemaining = 3,
        )
        val output = File(temp.newFolder("exports"), "anky-backup.zip")

        BackupZipWriter.write(
            outputFile = output,
            ankys = listOf(artifact),
            reflections = listOf(reflection),
            createdAt = Instant.parse("2026-05-15T12:00:00Z"),
        )

        val entries = unzip(output)
        val manifest = JSONObject(entries.getValue("manifest.json"))
        assertEquals(1, manifest.getInt("exportVersion"))
        assertEquals("2026-05-15T12:00:00.000Z", manifest.getString("createdAt"))
        assertEquals(1, manifest.getInt("ankyCount"))
        assertEquals(1, manifest.getInt("reflectionCount"))
        assertEquals(artifact.text, entries.getValue("files/${artifact.hash}.anky"))

        val reflectionJson = JSONObject(entries.getValue("reflections/${artifact.hash}.json"))
        assertEquals("Small Thread", reflectionJson.getString("title"))
        assertEquals("Here is what I saw.", reflectionJson.getString("reflection"))
        assertEquals("2026-05-14T15:44:58Z", reflectionJson.getString("createdAt"))
        assertEquals(3, reflectionJson.getInt("creditsRemaining"))
    }

    @Test
    fun backupImporterRestoresLegacyReflectionSidecars() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val importer = BackupImporter(null, archive, reflections, index)
        val backupHash = "a".repeat(64)
        val zip = File(temp.newFolder("imports"), "legacy.zip")

        ZipOutputStream(zip.outputStream()).use { output ->
            output.putTextEntry("files/$backupHash.anky", "1770000000000 h\n0042 SPACE\n8000")
            output.putTextEntry("files/$backupHash.title.txt", "Legacy Thread\n")
            output.putTextEntry("files/$backupHash.reflection.md", "Legacy reflection body")
            output.putTextEntry(
                "files/$backupHash.processing.json",
                """{"created_at":"2026-05-14T15:44:58Z","credits_remaining":3}""",
            )
        }

        val result = importer.importBackupBytes(zip.readBytes())

        val artifact = archive.list().single()
        assertEquals(BackupImportResult(ankyCount = 1, reflectionCount = 1), result)
        assertEquals("h ", artifact.reconstructedText)
        assertEquals("Legacy Thread", reflections.load(artifact.hash)?.title)
        assertEquals("Legacy reflection body", reflections.load(artifact.hash)?.reflection)
        assertEquals(3, reflections.load(artifact.hash)?.creditsRemaining)
    }

    @Test
    fun backupImporterRecordsEarliestImportedAnkyDateLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        var recorded: Instant? = null
        val importer = BackupImporter(
            null,
            archive,
            reflections,
            index,
            recordEarlierFirstOpenDate = { recorded = it },
        )
        val zip = File(temp.newFolder("imports"), "dated-ankys.zip")

        ZipOutputStream(zip.outputStream()).use { output ->
            output.putTextEntry("files/${"a".repeat(64)}.anky", "1770100000000 l\n8000")
            output.putTextEntry("files/${"b".repeat(64)}.anky", "1770000000000 e\n8000")
        }

        val result = importer.importBackupBytes(zip.readBytes())

        assertEquals(BackupImportResult(ankyCount = 2, reflectionCount = 0), result)
        assertEquals(2, archive.list().size)
        assertEquals(Instant.ofEpochMilli(1_770_000_000_000), recorded)
    }

    @Test
    fun backupImporterRejectsReflectionJsonWithUnsafeHash() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val importer = BackupImporter(null, archive, reflections, index)
        val zip = File(temp.newFolder("imports"), "unsafe-reflection.zip")

        ZipOutputStream(zip.outputStream()).use { output ->
            output.putTextEntry(
                "reflections/unsafe.json",
                """
                {
                  "hash": "../escape",
                  "title": "Bad",
                  "reflection": "Should not be imported.",
                  "createdAt": "2026-05-14T15:44:58Z",
                  "creditsRemaining": null
                }
                """.trimIndent(),
            )
        }

        try {
            importer.importBackupBytes(zip.readBytes())
            fail("Expected no importable data rejection")
        } catch (expected: IllegalStateException) {
            assertEquals("No .anky files or reflections were found in that import.", expected.message)
        }
        assertEquals(0, reflections.fileList().size)
    }

    @Test
    fun backupImporterRejectsBackslashZipEntryPathsLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val importer = BackupImporter(null, archive, reflections, index)
        val backupHash = "a".repeat(64)
        val zip = File(temp.newFolder("imports"), "backslash-path.zip")

        ZipOutputStream(zip.outputStream()).use { output ->
            output.putTextEntry("files\\$backupHash.anky", "1770000000000 h\n0042 i\n8000")
        }

        try {
            importer.importBackupBytes(zip.readBytes())
            fail("Expected no importable data rejection")
        } catch (expected: IllegalStateException) {
            assertEquals("No .anky files or reflections were found in that import.", expected.message)
        }
        assertEquals(0, archive.list().size)
    }

    @Test
    fun backupImporterRejectsDotDotZipEntryPathsLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val importer = BackupImporter(null, archive, reflections, index)
        val zip = File(temp.newFolder("imports"), "dotdot-path.zip")

        ZipOutputStream(zip.outputStream()).use { output ->
            output.putTextEntry("files/a..b.anky", "1770000000000 h\n0042 i\n8000")
        }

        try {
            importer.importBackupBytes(zip.readBytes())
            fail("Expected no importable data rejection")
        } catch (expected: IllegalStateException) {
            assertEquals("No .anky files or reflections were found in that import.", expected.message)
        }
        assertEquals(0, archive.list().size)
    }

    @Test
    fun backupImporterReportsCorruptZipLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val importer = BackupImporter(null, archive, reflections, index)

        try {
            importer.importBackupBytes(byteArrayOf(0x50, 0x4B, 0x03, 0x04))
            fail("Expected corrupt zip rejection")
        } catch (expected: IllegalStateException) {
            assertEquals("That zip backup appears to be corrupt.", expected.message)
        }
        assertEquals(0, archive.list().size)
    }

    @Test
    fun backupImporterReportsNoImportableDataForEmptyZipLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val importer = BackupImporter(null, archive, reflections, index)
        val zip = File(temp.newFolder("imports"), "empty.zip")

        ZipOutputStream(zip.outputStream()).use { }

        try {
            importer.importBackupBytes(zip.readBytes())
            fail("Expected no importable data rejection")
        } catch (expected: IllegalStateException) {
            assertEquals("No .anky files or reflections were found in that import.", expected.message)
        }
        assertEquals(0, archive.list().size)
    }

    @Test
    fun backupImporterRejectsUnsupportedNamedFilesLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val importer = BackupImporter(null, archive, reflections, index)

        try {
            importer.importBackupBytes("not a backup".toByteArray(Charsets.UTF_8), "notes.txt")
            fail("Expected unsupported file rejection")
        } catch (expected: IllegalStateException) {
            assertEquals("Choose a .zip backup, .anky file, or exported reflection JSON.", expected.message)
        }
        assertEquals(0, archive.list().size)
    }

    @Test
    fun backupImporterSkipsInvalidUtf8AnkyZipEntriesLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val importer = BackupImporter(null, archive, reflections, index)
        val zip = File(temp.newFolder("imports"), "invalid-utf8-entry.zip")

        ZipOutputStream(zip.outputStream()).use { output ->
            output.putBytesEntry("files/${"a".repeat(64)}.anky", invalidUtf8AnkyBytes())
        }

        try {
            importer.importBackupBytes(zip.readBytes())
            fail("Expected no importable data rejection")
        } catch (expected: IllegalStateException) {
            assertEquals("No .anky files or reflections were found in that import.", expected.message)
        }
        assertEquals(0, archive.list().size)
    }

    @Test
    fun backupImporterRejectsInvalidUtf8AnkyBytesLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val importer = BackupImporter(null, archive, reflections, index)

        try {
            importer.importBackupBytes(invalidUtf8AnkyBytes())
            fail("Expected invalid UTF-8 backup rejection")
        } catch (expected: IllegalStateException) {
            assertEquals("That backup could not be read.", expected.message)
        }
        assertEquals(0, archive.list().size)
    }

    @Test
    fun singleAnkyImporterSavesValidClipboardTextAndIndexesIt() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))

        val saved = SingleAnkyImporter.importText(
            rawText = "1770000000000 h\n480000 i\n8000\n",
            archive = archive,
            reflectionStore = reflections,
            indexStore = index,
        )

        assertEquals("hi", saved.reconstructedText)
        assertEquals(saved.hash, archive.load(saved.hash).hash)
        assertEquals(saved.hash, index.load().single().hash)
        assertFalse(index.load().single().hasReflection)
    }

    @Test
    fun singleAnkyImporterImportsPastedMarkdownAnkyLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val pasted = """
            here is the .anky:

            ```anky
            1770000000000 h
            480000 i
            8000
            ```
        """.trimIndent()

        val saved = SingleAnkyImporter.importText(pasted, archive, reflections, index)

        assertEquals("hi", saved.reconstructedText)
        assertEquals(saved.hash, index.load().single().hash)
    }

    @Test
    fun singleAnkyImporterNormalizesSpacePlaceholderAndTrailingWhitespaceLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val pasted = listOf(
            "",
            "    1770000000000 h",
            "    240000 SPACE",
            "    240000 i   ",
            "    8000",
            "",
        ).joinToString("\n")

        val saved = SingleAnkyImporter.importText(pasted, archive, reflections, index)

        assertEquals("1770000000000 h\n240000  \n240000 i\n8000", saved.text)
        assertEquals("h i", saved.reconstructedText)
    }

    @Test
    fun singleAnkyImporterRejectsPastedFragmentUnderEightMinutesLikeIos() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))

        try {
            SingleAnkyImporter.importText("1770000000000 h\n471999 i\n8000", archive, reflections, index)
            fail("Expected incomplete import rejection")
        } catch (expected: IllegalStateException) {
            assertEquals("i couldn't find a readable .anky in that.", expected.message)
        }

        assertEquals(0, archive.list().size)
        assertEquals(0, index.load().size)
    }

    @Test
    fun singleAnkyImporterRejectsInvalidBytesWithoutWriting() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))

        try {
            SingleAnkyImporter.importBytes(
                bytes = invalidUtf8AnkyBytes(),
                archive = archive,
                reflectionStore = reflections,
                indexStore = index,
            )
            fail("Expected invalid UTF-8 rejection")
        } catch (expected: IllegalStateException) {
            assertEquals("That .anky file could not be read.", expected.message)
        }

        assertEquals(0, archive.list().size)
        assertEquals(0, index.load().size)
    }

    private fun unzip(file: File): Map<String, String> {
        val entries = mutableMapOf<String, String>()
        ZipInputStream(file.inputStream()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (!entry.isDirectory) {
                    entries[entry.name] = zip.readBytes().toString(Charsets.UTF_8)
                }
                zip.closeEntry()
            }
        }
        return entries
    }

    private fun invalidUtf8AnkyBytes(): ByteArray = byteArrayOf(
        '1'.code.toByte(),
        '7'.code.toByte(),
        '7'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
        ' '.code.toByte(),
        0xff.toByte(),
        '\n'.code.toByte(),
        '8'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
        '0'.code.toByte(),
    )

    private fun sessionSummary(hash: String, createdAt: Instant, isComplete: Boolean): SessionSummary =
        SessionSummary(
            hash = hash,
            createdAt = createdAt,
            localFilePath = File(temp.root, "$hash.anky").absolutePath,
            durationMs = if (isComplete) 488_000 else 8_000,
            isComplete = isComplete,
            preview = hash,
            wordCount = 1,
            hasReflection = false,
            reflectionTitle = null,
        )

    private fun ZipOutputStream.putTextEntry(path: String, text: String) {
        putNextEntry(ZipEntry(path))
        write(text.toByteArray(Charsets.UTF_8))
        closeEntry()
    }

    private fun ZipOutputStream.putBytesEntry(path: String, bytes: ByteArray) {
        putNextEntry(ZipEntry(path))
        write(bytes)
        closeEntry()
    }
}
