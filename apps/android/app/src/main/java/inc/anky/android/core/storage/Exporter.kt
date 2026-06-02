package inc.anky.android.core.storage

import android.content.Context
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.temporal.ChronoUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.json.JSONArray
import org.json.JSONObject

interface BackupExporting {
    fun exportArchiveZip(): File?
}

class Exporter(
    private val context: Context,
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
) : BackupExporting {
    override fun exportArchiveZip(): File? {
        val ankys = archive.list()
        val reflections = reflectionStore.list()
        if (ankys.isEmpty() && reflections.isEmpty()) return null

        val createdAt = Instant.now()
        val exportDirectory = File(context.cacheDir, "exports").also { it.mkdirs() }
        val exportFile = File(exportDirectory, "anky-backup-${BackupDateFormatter.format(createdAt)}.zip")
        BackupZipWriter.write(exportFile, ankys, reflections, createdAt)
        return exportFile
    }

    private companion object {
        val BackupDateFormatter: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneId.systemDefault())
    }
}

internal object BackupZipWriter {
    fun write(
        outputFile: File,
        ankys: List<SavedAnky>,
        reflections: List<LocalReflection>,
        createdAt: Instant,
    ) {
        ZipOutputStream(outputFile.outputStream()).use { zip ->
            zip.putJsonEntry(
                "manifest.json",
                JSONObject()
                    .put("exportVersion", 1)
                    .put("createdAt", BackupManifestDateFormatter.format(createdAt))
                    .put("ankyCount", ankys.size)
                    .put("reflectionCount", reflections.size),
                createdAt,
            )

            ankys.forEach { anky ->
                zip.putNextEntry(ZipEntry("files/${anky.hash}.anky").apply { time = anky.createdAt.toEpochMilli() })
                zip.write(anky.text.toByteArray(Charsets.UTF_8))
                zip.closeEntry()
            }

            reflections.forEach { reflection ->
                zip.putJsonEntry(
                    "reflections/${reflection.hash}.json",
                    reflection.toBackupJson(),
                    reflection.createdAt,
                )
            }
        }
    }

    private fun ZipOutputStream.putJsonEntry(path: String, json: JSONObject, modifiedAt: Instant) {
        putNextEntry(ZipEntry(path).apply { time = modifiedAt.toEpochMilli() })
        write(json.toString(2).toByteArray(Charsets.UTF_8))
        closeEntry()
    }

    private fun LocalReflection.toBackupJson(): JSONObject =
        JSONObject()
            .put("hash", hash)
            .put("title", title)
            .put("reflection", reflection)
            .put("tags", JSONArray(tags))
            .put("createdAt", createdAt.truncatedTo(ChronoUnit.SECONDS).toString())
            .put("creditsRemaining", creditsRemaining)

    private val BackupManifestDateFormatter: DateTimeFormatter =
        DateTimeFormatterBuilder().appendInstant(3).toFormatter()
}
