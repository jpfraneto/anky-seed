package inc.anky.android.core.storage

import android.content.Context
import org.json.JSONObject

/**
 * The writing chamber's typeface — five hands, all humanist. Raw values match
 * iOS AnkyWritingFontChoice (ios/Anky/Core/Storage/WritingPreferencesStore.swift)
 * exactly so preferences survive a device switch. The mapping to an actual
 * Compose FontFamily lives in the UI layer; this type stays framework-free.
 */
enum class AnkyWritingFontChoice(val rawValue: String, val displayName: String) {
    Quill("quill", "Quill"),
    Georgia("georgia", "Georgia"),
    Round("round", "Round"),
    Plain("plain", "Plain"),
    Typewriter("typewriter", "Typewriter"),
    ;

    companion object {
        val Default = Quill

        fun fromRawValue(rawValue: String?): AnkyWritingFontChoice? =
            entries.firstOrNull { it.rawValue == rawValue }
    }
}

/**
 * The writing text size, in steps rather than a free slider. Raw values and
 * point sizes match iOS AnkyWritingTextSize.
 */
enum class AnkyWritingTextSize(
    val rawValue: String,
    val displayName: String,
    val pointSize: Double,
) {
    Small("small", "Small", 18.0),
    Medium("medium", "Medium", 21.0),
    Large("large", "Large", 24.0),
    Grand("grand", "Grand", 28.0),
    ;

    companion object {
        val Default = Medium

        fun fromRawValue(rawValue: String?): AnkyWritingTextSize? =
            entries.firstOrNull { it.rawValue == rawValue }
    }
}

/**
 * User-tunable writing chamber settings. Historically Anky forced the ritual
 * (no backspace, forward only); these preferences let the writer choose their
 * own adventure, with the ritual as the clear default.
 */
data class WritingPreferences(
    /**
     * When false (default), backspace is rejected — words only move forward.
     * When true, deletion is allowed and is recorded in the .anky protocol as
     * a suffix rewrite.
     */
    val backspaceAllowed: Boolean,
    /** System autocorrection and the keyboard suggestion strip. */
    val autocorrectEnabled: Boolean,
    val fontChoice: AnkyWritingFontChoice,
    val textSize: AnkyWritingTextSize,
) {
    companion object {
        val RitualDefault = WritingPreferences(
            backspaceAllowed = false,
            autocorrectEnabled = true,
            fontChoice = AnkyWritingFontChoice.Default,
            textSize = AnkyWritingTextSize.Default,
        )
    }
}

/**
 * Persists WritingPreferences under the iOS key `anky.writingPreferences.v1`
 * as a JSON payload whose field names and raw values match the iOS Codable
 * encoding, so backups and mental models stay portable.
 */
class WritingPreferencesStore private constructor(
    private val read: () -> String?,
    private val write: (String) -> Unit,
) {
    constructor(context: Context) : this(
        read = {
            context.applicationContext
                .getSharedPreferences(PreferencesFileName, Context.MODE_PRIVATE)
                .getString(Key, null)
        },
        write = { json ->
            context.applicationContext
                .getSharedPreferences(PreferencesFileName, Context.MODE_PRIVATE)
                .edit()
                .putString(Key, json)
                .apply()
        },
    )

    fun load(): WritingPreferences {
        val stored = read() ?: return WritingPreferences.RitualDefault
        return runCatching {
            val json = JSONObject(stored)
            WritingPreferences(
                backspaceAllowed = json.getBoolean("backspaceAllowed"),
                autocorrectEnabled = json.getBoolean("autocorrectEnabled"),
                fontChoice = checkNotNull(AnkyWritingFontChoice.fromRawValue(json.getString("fontChoice"))),
                textSize = checkNotNull(AnkyWritingTextSize.fromRawValue(json.getString("textSize"))),
            )
        }.getOrDefault(WritingPreferences.RitualDefault)
    }

    fun save(preferences: WritingPreferences) {
        val json = JSONObject()
            .put("backspaceAllowed", preferences.backspaceAllowed)
            .put("autocorrectEnabled", preferences.autocorrectEnabled)
            .put("fontChoice", preferences.fontChoice.rawValue)
            .put("textSize", preferences.textSize.rawValue)
        write(json.toString())
    }

    fun update(mutate: (WritingPreferences) -> WritingPreferences) {
        save(mutate(load()))
    }

    companion object {
        const val Key = "anky.writingPreferences.v1"
        private const val PreferencesFileName = "anky-writing-preferences"

        fun forStorage(read: () -> String?, write: (String) -> Unit): WritingPreferencesStore =
            WritingPreferencesStore(read, write)
    }
}
