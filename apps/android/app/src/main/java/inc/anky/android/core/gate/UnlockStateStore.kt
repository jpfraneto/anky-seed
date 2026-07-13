package inc.anky.android.core.gate

import android.content.SharedPreferences
import java.time.Instant
import java.time.ZoneId
import org.json.JSONObject

data class UnlockState(
    val grant: UnlockGrant? = null,
    val lastWroteAt: Instant? = null,
) {
    fun isUnlocked(at: Instant = Instant.now()): Boolean {
        val grant = grant ?: return false
        return at.isBefore(grant.unlockedUntil)
    }

    fun wroteToday(at: Instant = Instant.now(), zoneId: ZoneId = ZoneId.systemDefault()): Boolean {
        val lastWroteAt = lastWroteAt ?: return false
        return lastWroteAt.atZone(zoneId).toLocalDate() == at.atZone(zoneId).toLocalDate()
    }
}

class WriteBeforeScrollUnlockOfferPolicy {
    fun shouldOfferUnlock(state: UnlockState, at: Instant = Instant.now()): Boolean =
        !state.isUnlocked(at)
}

class UnlockStateStore(
    private val preferences: SharedPreferences,
) {
    fun load(): UnlockState {
        val raw = preferences.getString(Key, null) ?: return UnlockState()
        return runCatching {
            val json = JSONObject(raw)
            UnlockState(
                grant = json.optJSONObject("grant")?.let { grantJson ->
                    UnlockGrant(
                        tier = UnlockTier.fromRawValue(grantJson.getString("tier"))
                            ?: return UnlockState(),
                        unlockedUntil = Instant.parse(grantJson.getString("unlockedUntil")),
                        grantedAt = Instant.parse(grantJson.getString("grantedAt")),
                    )
                },
                lastWroteAt = json.optString("lastWroteAt", "")
                    .takeIf { it.isNotEmpty() }
                    ?.let(Instant::parse),
            )
        }.getOrDefault(UnlockState())
    }

    fun save(state: UnlockState) {
        val json = JSONObject()
        state.grant?.let { grant ->
            json.put(
                "grant",
                JSONObject()
                    .put("tier", grant.tier.rawValue)
                    .put("unlockedUntil", grant.unlockedUntil.toString())
                    .put("grantedAt", grant.grantedAt.toString()),
            )
        }
        state.lastWroteAt?.let { json.put("lastWroteAt", it.toString()) }
        preferences.edit().putString(Key, json.toString()).apply()
    }

    fun apply(grant: UnlockGrant) {
        save(UnlockState(grant = grant, lastWroteAt = grant.grantedAt))
    }

    fun markWrote(at: Instant = Instant.now()) {
        save(load().copy(lastWroteAt = at))
    }

    fun clearUnlock(keepWritingDate: Boolean = true) {
        val state = load()
        save(
            state.copy(
                grant = null,
                lastWroteAt = if (keepWritingDate) state.lastWroteAt else null,
            ),
        )
    }

    private companion object {
        const val Key = "writeBeforeScroll.unlockState.v1"
    }
}
