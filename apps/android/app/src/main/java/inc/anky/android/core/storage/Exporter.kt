package inc.anky.android.core.storage

import android.content.Context
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class Exporter(
    private val context: Context,
    private val archive: LocalAnkyArchive,
) {
    fun exportArchiveZip(): File {
        val exportFile = File(context.cacheDir, "anky-archive.zip")
        ZipOutputStream(exportFile.outputStream()).use { zip ->
            archive.fileList().forEach { file ->
                zip.putNextEntry(ZipEntry(file.name))
                file.inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
        return exportFile
    }
}
