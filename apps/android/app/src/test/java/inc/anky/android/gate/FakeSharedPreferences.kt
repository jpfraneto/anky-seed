package inc.anky.android.gate

import android.content.SharedPreferences

/**
 * In-memory SharedPreferences for JVM unit tests — the Android analogue of
 * the iOS tests' throwaway `UserDefaults(suiteName:)` instances.
 */
class FakeSharedPreferences : SharedPreferences {
    private val values = mutableMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()

    override fun getString(key: String?, defValue: String?): String? =
        values[key] as? String ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        values[key] as? MutableSet<String> ?: defValues

    override fun getInt(key: String?, defValue: Int): Int =
        values[key] as? Int ?: defValue

    override fun getLong(key: String?, defValue: Long): Long =
        values[key] as? Long ?: defValue

    override fun getFloat(key: String?, defValue: Float): Float =
        values[key] as? Float ?: defValue

    override fun getBoolean(key: String?, defValue: Boolean): Boolean =
        values[key] as? Boolean ?: defValue

    override fun contains(key: String?): Boolean = values.containsKey(key)

    override fun edit(): SharedPreferences.Editor = FakeEditor()

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    private inner class FakeEditor : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private val removals = mutableSetOf<String>()
        private var clears = false

        override fun putString(key: String?, value: String?): SharedPreferences.Editor =
            apply { pending[checkNotNull(key)] = value }

        override fun putStringSet(key: String?, value: MutableSet<String>?): SharedPreferences.Editor =
            apply { pending[checkNotNull(key)] = value }

        override fun putInt(key: String?, value: Int): SharedPreferences.Editor =
            apply { pending[checkNotNull(key)] = value }

        override fun putLong(key: String?, value: Long): SharedPreferences.Editor =
            apply { pending[checkNotNull(key)] = value }

        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor =
            apply { pending[checkNotNull(key)] = value }

        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor =
            apply { pending[checkNotNull(key)] = value }

        override fun remove(key: String?): SharedPreferences.Editor =
            apply { removals.add(checkNotNull(key)) }

        override fun clear(): SharedPreferences.Editor = apply { clears = true }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun apply() {
            if (clears) values.clear()
            removals.forEach(values::remove)
            pending.forEach { (key, value) ->
                if (value == null) values.remove(key) else values[key] = value
            }
        }
    }
}
