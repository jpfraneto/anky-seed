package inc.anky.android.core.storage

import android.content.Context
import java.io.File

/**
 * The writer's optional selfie, taken during onboarding and worn across the
 * app. Kept as a single JPEG in the app's private files directory — never off
 * the device. Mirrors iOS AvatarStore (ios/Anky/Core/Storage/AvatarStore.swift);
 * decoding the bytes into a Bitmap happens in the UI layer.
 */
class AvatarStore private constructor(
    private val directory: File,
) {
    constructor(context: Context) : this(context.filesDir)

    private val file: File
        get() = File(directory, FileName)

    val hasAvatar: Boolean
        get() = file.exists()

    fun loadData(): ByteArray? =
        runCatching { file.takeIf { it.exists() }?.readBytes() }.getOrNull()

    fun save(data: ByteArray) {
        runCatching {
            directory.mkdirs()
            file.writeBytes(data)
        }
    }

    fun delete() {
        file.delete()
    }

    companion object {
        const val FileName = "avatar.jpg"

        fun forDirectory(directory: File): AvatarStore = AvatarStore(directory)
    }
}
