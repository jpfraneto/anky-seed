package inc.anky.android.subscription

import android.app.Activity
import android.content.SharedPreferences
import inc.anky.android.core.subscription.EntitlementSnapshot
import inc.anky.android.core.subscription.SubscriptionBackend
import inc.anky.android.core.subscription.SubscriptionGateway
import inc.anky.android.core.subscription.SubscriptionPackage
import inc.anky.android.core.subscription.SubscriptionPurchaseOutcome
import inc.anky.android.core.subscription.TrialReminderPort

/** In-memory SharedPreferences for JVM tests — no Robolectric needed. */
class FakeSharedPreferences : SharedPreferences {
    private val values = mutableMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()

    override fun getString(key: String?, defValue: String?): String? =
        values[key] as? String ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        values[key] as? MutableSet<String> ?: defValues

    override fun getInt(key: String?, defValue: Int): Int = values[key] as? Int ?: defValue

    override fun getLong(key: String?, defValue: Long): Long = values[key] as? Long ?: defValue

    override fun getFloat(key: String?, defValue: Float): Float = values[key] as? Float ?: defValue

    override fun getBoolean(key: String?, defValue: Boolean): Boolean =
        values[key] as? Boolean ?: defValue

    override fun contains(key: String?): Boolean = values.containsKey(key)

    override fun edit(): SharedPreferences.Editor = Editor()

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    private inner class Editor : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private val removals = mutableSetOf<String>()
        private var clearAll = false

        override fun putString(key: String, value: String?): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putStringSet(key: String, values: MutableSet<String>?): SharedPreferences.Editor {
            pending[key] = values
            return this
        }

        override fun putInt(key: String, value: Int): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putLong(key: String, value: Long): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putFloat(key: String, value: Float): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun remove(key: String): SharedPreferences.Editor {
            removals.add(key)
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            clearAll = true
            return this
        }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun apply() {
            if (clearAll) values.clear()
            removals.forEach { values.remove(it) }
            pending.forEach { (key, value) ->
                if (value == null) values.remove(key) else values[key] = value
            }
        }
    }
}

class FakeSubscriptionGateway : SubscriptionGateway {
    override var identifiedAppUserId: String? = null
    var identifyAnswer: String? = null
    var packagesAnswer: List<SubscriptionPackage> = emptyList()
    var loadPackagesThrows = false
    var purchaseOutcome: SubscriptionPurchaseOutcome = SubscriptionPurchaseOutcome.Failed
    var restoreAnswer: EntitlementSnapshot? = null
    var fetchCurrentAnswer: EntitlementSnapshot? = null
    var trialEligibilityAnswer = true
    var observer: ((EntitlementSnapshot) -> Unit)? = null
    val calls = mutableListOf<String>()

    override suspend fun ensureIdentified(): String? {
        calls.add("ensureIdentified")
        identifiedAppUserId = identifyAnswer
        return identifyAnswer
    }

    override fun observeCustomerInfo(onSnapshot: (EntitlementSnapshot) -> Unit) {
        calls.add("observeCustomerInfo")
        observer = onSnapshot
    }

    override suspend fun fetchCurrentSnapshot(): EntitlementSnapshot? {
        calls.add("fetchCurrentSnapshot")
        return fetchCurrentAnswer
    }

    override suspend fun loadPackages(): List<SubscriptionPackage> {
        calls.add("loadPackages")
        if (loadPackagesThrows) error("offerings unreachable")
        return packagesAnswer
    }

    override suspend fun purchase(
        pkg: SubscriptionPackage,
        activity: Activity?,
    ): SubscriptionPurchaseOutcome {
        calls.add("purchase:${pkg.productId}")
        return purchaseOutcome
    }

    override suspend fun restore(): EntitlementSnapshot {
        calls.add("restore")
        return restoreAnswer ?: error("restore failed")
    }

    override suspend fun yearlyTrialEligibility(): Boolean = trialEligibilityAnswer
}

class RecordingSubscriptionBackend : SubscriptionBackend {
    var identifyAnswer: Boolean? = true
    val identifiedUserIds = mutableListOf<String>()
    val funnelEvents = mutableListOf<Pair<String, String?>>()
    val orderedCalls = mutableListOf<String>()

    override suspend fun identify(appUserId: String): Boolean? {
        identifiedUserIds.add(appUserId)
        orderedCalls.add("identify")
        return identifyAnswer
    }

    override suspend fun funnel(event: String, origin: String?) {
        funnelEvents.add(event to origin)
        orderedCalls.add("funnel:$event")
    }
}

class RecordingTrialReminderPort : TrialReminderPort {
    val scheduledAt = mutableListOf<Long>()
    var cancelCount = 0

    override suspend fun scheduleTrialEndingReminder(fireAtEpochMillis: Long) {
        scheduledAt.add(fireAtEpochMillis)
    }

    override fun cancelTrialEndingReminder() {
        cancelCount += 1
    }
}
