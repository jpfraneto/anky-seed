package inc.anky.android.core.gate

import android.content.SharedPreferences
import java.time.Instant
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

enum class WriteBeforeScrollEventName(val rawValue: String) {
    ShieldShown("shield_shown"),
    ShieldRendered("shield_rendered"),
    ShieldActionTapped("shield_action_tapped"),
    ShieldPrimaryTapped("shield_primary_tapped"),
    AnkyOpenedFromShieldPendingState("anky_opened_from_shield_pending_state"),
    WritingStarted("writing_started"),
    SentenceUnlockAvailable("sentence_unlock_available"),
    PresenceUnlockAvailable("presence_unlock_available"),
    AnkyUnlockAvailable("anky_unlock_available"),
    UnlockTapped("unlock_tapped"),
    ContinuedWritingAfterUnlockAvailable("continued_writing_after_unlock_available"),
    UnlockGranted("unlock_granted"),
    RelockScheduled("relock_scheduled"),
    RelockApplied("relock_applied"),
    RelockFailed("relock_failed"),
    BridgeModeDirectOpen("bridge_mode_direct_open"),
    BridgeModeNotification("bridge_mode_notification"),
    DirectOpenRequested("direct_open_requested"),
    NotificationScheduled("notification_scheduled"),
    NotificationResendTapped("notification_resend_tapped"),
    NotificationPermissionMissing("notification_permission_missing"),
    NotificationTapped("notification_tapped"),
    AppOpenedWithPendingWBSIntent("app_opened_with_pending_wbs_intent"),
    RoutedToWBSFromShield("routed_to_wbs_from_shield"),
    PendingIntentConsumed("pending_intent_consumed"),
    EmergencyUnlockTapped("emergency_unlock_tapped"),
    OnboardingTargetSet("onboarding_target_set"),
    TargetChanged("target_changed"),
    QuickPassUsed("quick_pass_used"),
    QuickPassExhaustedShown("quick_pass_exhausted_shown"),
    DailyTargetReached("daily_target_reached"),
    SessionOvershoot("session_overshoot"),
    ScreenTimeAuthorizationRequested("screen_time_authorization_requested"),
    ScreenTimeAuthorizationGranted("screen_time_authorization_granted"),
    ScreenTimeAuthorizationDenied("screen_time_authorization_denied"),
    AppSelectionSaved("app_selection_saved"),
    ShieldApplied("shield_applied"),
    ShieldCleared("shield_cleared"),
    WbsSessionSealed("wbs_session_sealed"),
    ;

    companion object {
        fun fromRawValue(rawValue: String?): WriteBeforeScrollEventName? =
            entries.firstOrNull { it.rawValue == rawValue }
    }
}

data class WriteBeforeScrollEvent(
    val id: UUID = UUID.randomUUID(),
    val name: WriteBeforeScrollEventName,
    val timestamp: Instant = Instant.now(),
    val sessionId: UUID? = null,
    val tierRawValue: String? = null,
    val message: String? = null,
    val metadata: Map<String, String> = emptyMap(),
)

class WriteBeforeScrollEventLogStore(
    private val preferences: SharedPreferences,
    private val maxStoredEvents: Int = 300,
) {
    fun load(): List<WriteBeforeScrollEvent> {
        val raw = preferences.getString(Key, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                array.getJSONObject(index).toEventOrNull()
            }
        }.getOrDefault(emptyList())
    }

    fun recent(limit: Int = 20): List<WriteBeforeScrollEvent> =
        load().takeLast(limit).reversed()

    fun append(
        name: WriteBeforeScrollEventName,
        at: Instant = Instant.now(),
        sessionId: UUID? = null,
        tierRawValue: String? = null,
        message: String? = null,
        metadata: Map<String, String> = emptyMap(),
    ) {
        append(
            WriteBeforeScrollEvent(
                name = name,
                timestamp = at,
                sessionId = sessionId,
                tierRawValue = tierRawValue,
                message = message,
                metadata = metadata,
            ),
        )
    }

    fun append(event: WriteBeforeScrollEvent) {
        var events = load() + event
        if (events.size > maxStoredEvents) {
            events = events.takeLast(maxStoredEvents)
        }
        val array = JSONArray()
        events.forEach { array.put(it.toJson()) }
        preferences.edit().putString(Key, array.toString()).apply()
    }

    /**
     * Shield events are transition-only, mirroring iOS
     * `ScreenTimeShieldController`: `shield_applied` logs only when the
     * shield goes up from down, `shield_cleared` only when it comes down
     * from up. Reconciles that re-affirm the current state stay silent.
     */
    fun appendShieldTransition(
        wasShieldActive: Boolean,
        isShieldActive: Boolean,
        at: Instant = Instant.now(),
        metadata: Map<String, String> = emptyMap(),
    ) {
        if (!wasShieldActive && isShieldActive) {
            append(WriteBeforeScrollEventName.ShieldApplied, at = at, metadata = metadata)
        } else if (wasShieldActive && !isShieldActive) {
            append(WriteBeforeScrollEventName.ShieldCleared, at = at)
        }
    }

    fun clear() {
        preferences.edit().remove(Key).apply()
    }

    private fun WriteBeforeScrollEvent.toJson(): JSONObject {
        val json = JSONObject()
            .put("id", id.toString())
            .put("name", name.rawValue)
            .put("timestamp", timestamp.toString())
        sessionId?.let { json.put("sessionID", it.toString()) }
        tierRawValue?.let { json.put("tierRawValue", it) }
        message?.let { json.put("message", it) }
        val metadataJson = JSONObject()
        metadata.forEach { (key, value) -> metadataJson.put(key, value) }
        json.put("metadata", metadataJson)
        return json
    }

    private fun JSONObject.toEventOrNull(): WriteBeforeScrollEvent? {
        val name = WriteBeforeScrollEventName.fromRawValue(optString("name")) ?: return null
        val metadataJson = optJSONObject("metadata") ?: JSONObject()
        return WriteBeforeScrollEvent(
            id = runCatching { UUID.fromString(getString("id")) }.getOrElse { UUID.randomUUID() },
            name = name,
            timestamp = Instant.parse(getString("timestamp")),
            sessionId = optString("sessionID", "").takeIf { it.isNotEmpty() }
                ?.let { runCatching { UUID.fromString(it) }.getOrNull() },
            tierRawValue = if (has("tierRawValue")) getString("tierRawValue") else null,
            message = if (has("message")) getString("message") else null,
            metadata = metadataJson.keys().asSequence().associateWith { metadataJson.getString(it) },
        )
    }

    private companion object {
        const val Key = "writeBeforeScroll.eventLog.v1"
    }
}
