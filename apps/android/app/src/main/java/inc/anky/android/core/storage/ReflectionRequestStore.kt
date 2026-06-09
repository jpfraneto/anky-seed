package inc.anky.android.core.storage

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class ReflectionRequestStore private constructor(
    private val file: File,
    private val expirationMs: Long = 15 * 60 * 1000L,
) {
    constructor(context: Context) : this(File(File(context.filesDir, "Anky"), "pending-reflection-requests.json"))

    init {
        file.parentFile?.mkdirs()
    }

    fun isPending(hash: String, nowMs: Long = System.currentTimeMillis()): Boolean =
        load(nowMs).any { it.hash == hash }

    fun markPending(hash: String, nowMs: Long = System.currentTimeMillis()) {
        val requests = load(nowMs).filter { it.hash != hash } + PendingRequest(hash = hash, startedAtMs = nowMs)
        save(requests)
    }

    fun clear(hash: String, nowMs: Long = System.currentTimeMillis()) {
        save(load(nowMs).filter { it.hash != hash })
    }

    fun clear() {
        if (file.exists()) file.delete()
    }

    private fun load(nowMs: Long): List<PendingRequest> {
        if (!file.exists()) return emptyList()
        val decoded = runCatching {
            val array = JSONArray(file.readText(Charsets.UTF_8))
            (0 until array.length()).mapNotNull { index ->
                val objectValue = array.optJSONObject(index) ?: return@mapNotNull null
                PendingRequest(
                    hash = objectValue.optString("hash"),
                    startedAtMs = objectValue.optLong("startedAtMs"),
                ).takeIf { it.hash.matches(Sha256Hex) }
            }
        }.getOrDefault(emptyList())
        val active = decoded.filter { nowMs - it.startedAtMs < expirationMs }
        if (active.size != decoded.size) save(active)
        return active
    }

    private fun save(requests: List<PendingRequest>) {
        val array = JSONArray()
        requests.forEach { request ->
            array.put(
                JSONObject()
                    .put("hash", request.hash)
                    .put("startedAtMs", request.startedAtMs),
            )
        }
        file.writeText(array.toString(2), Charsets.UTF_8)
    }

    private data class PendingRequest(
        val hash: String,
        val startedAtMs: Long,
    )

    companion object {
        private val Sha256Hex = Regex("^[0-9a-f]{64}$")

        fun forFile(file: File, expirationMs: Long = 15 * 60 * 1000L): ReflectionRequestStore =
            ReflectionRequestStore(file, expirationMs)
    }
}
