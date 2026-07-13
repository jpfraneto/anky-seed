package inc.anky.android.core.gate.runtime

import android.content.SharedPreferences
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject

/**
 * One app the writer asked Anky to hold behind the door.
 *
 * Android's answer to the iOS `BlockedAppSelectionStore` snapshot: where iOS
 * persists opaque `FamilyActivitySelection` tokens (the OS never reveals the
 * apps), Android chooses its own apps, so the snapshot is honest — package
 * names plus the display labels the picker saw. Same key as iOS
 * (`writeBeforeScroll.blockedAppSelection.v1`), divergent payload by design.
 */
data class BlockedApp(
    val packageName: String,
    val label: String,
)

class BlockedAppSelectionStore(
    private val preferences: SharedPreferences,
) {
    fun load(): List<BlockedApp> = decode(preferences.getString(Key, null))

    fun save(apps: List<BlockedApp>, now: Instant = Instant.now()) {
        preferences.edit().putString(Key, encode(apps, now)).apply()
    }

    fun clear() {
        preferences.edit().remove(Key).apply()
    }

    fun blockedPackages(): Set<String> = load().mapTo(linkedSetOf()) { it.packageName }

    fun labelFor(packageName: String): String? =
        load().firstOrNull { it.packageName == packageName }?.label

    val hasSelection: Boolean
        get() = load().isNotEmpty()

    companion object {
        const val Key = "writeBeforeScroll.blockedAppSelection.v1"

        /** Pure codec, JVM-testable without a preferences instance. */
        fun encode(apps: List<BlockedApp>, updatedAt: Instant): String {
            val array = JSONArray()
            apps.forEach { app ->
                array.put(
                    JSONObject()
                        .put("packageName", app.packageName)
                        .put("label", app.label),
                )
            }
            return JSONObject()
                .put("apps", array)
                .put("updatedAt", updatedAt.toString())
                .toString()
        }

        fun decode(raw: String?): List<BlockedApp> {
            if (raw == null) return emptyList()
            return runCatching {
                val array = JSONObject(raw).getJSONArray("apps")
                (0 until array.length()).mapNotNull { index ->
                    val json = array.getJSONObject(index)
                    val packageName = json.optString("packageName", "")
                    if (packageName.isEmpty()) {
                        null
                    } else {
                        BlockedApp(
                            packageName = packageName,
                            label = json.optString("label", packageName),
                        )
                    }
                }
            }.getOrDefault(emptyList())
        }
    }
}
