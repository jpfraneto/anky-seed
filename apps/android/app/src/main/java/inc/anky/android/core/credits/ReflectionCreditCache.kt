package inc.anky.android.core.credits

import android.content.Context
import android.content.SharedPreferences

interface ReflectionCreditCache {
    fun hasClaimedFreeCredits(accountId: String): Boolean
    fun markFreeCreditsClaimed(accountId: String)
    fun balance(accountId: String): Int?
    fun storeBalance(balance: Int?, accountId: String)
    fun clear()
}

object NoopReflectionCreditCache : ReflectionCreditCache {
    override fun hasClaimedFreeCredits(accountId: String): Boolean = false
    override fun markFreeCreditsClaimed(accountId: String) = Unit
    override fun balance(accountId: String): Int? = null
    override fun storeBalance(balance: Int?, accountId: String) = Unit
    override fun clear() = Unit
}

class SharedPreferencesReflectionCreditCache(
    context: Context,
) : ReflectionCreditCache {
    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences("anky-reflection-credit-cache", Context.MODE_PRIVATE)
    private val legacyPreferences: SharedPreferences =
        context.applicationContext.getSharedPreferences("anky-credit-prompt", Context.MODE_PRIVATE)

    override fun hasClaimedFreeCredits(accountId: String): Boolean =
        preferences.getBoolean(claimedKeyForAccount(accountId), false) ||
            preferences.getBoolean(ClaimedKey, false) ||
            legacyPreferences.getBoolean(LegacyClaimedKey, false)

    override fun markFreeCreditsClaimed(accountId: String) {
        preferences.edit().apply {
            putBoolean(ClaimedKey, true)
            putBoolean(claimedKeyForAccount(accountId), true)
        }.apply()
        legacyPreferences.edit().putBoolean(LegacyClaimedKey, true).apply()
    }

    override fun balance(accountId: String): Int? {
        val key = balanceKeyForAccount(accountId)
        if (!preferences.contains(key)) return null
        return preferences.getInt(key, 0)
    }

    override fun storeBalance(balance: Int?, accountId: String) {
        preferences.edit().apply {
            val key = balanceKeyForAccount(accountId)
            if (balance == null) {
                remove(key)
            } else {
                putInt(key, balance)
            }
        }.apply()
    }

    override fun clear() {
        val keys = preferences.all.keys.filter { key ->
            key == ClaimedKey || key.startsWith("$ClaimedKey.") || key.startsWith("$BalanceKey.")
        }
        preferences.edit().apply {
            keys.forEach(::remove)
        }.apply()
    }

    private fun claimedKeyForAccount(accountId: String): String =
        "$ClaimedKey.$accountId"

    private fun balanceKeyForAccount(accountId: String): String =
        "$BalanceKey.$accountId"

    private companion object {
        const val ClaimedKey = "anky.hasClaimedFreeReflections"
        const val BalanceKey = "anky.reflectionCreditBalance"
        const val LegacyClaimedKey = "hasClaimedFreeReflections"
    }
}

fun cachedCreditState(balance: Int?): CreditState? =
    balance?.let {
        CreditState(
            isConfigured = true,
            balance = it,
            message = "credits refreshed.",
        )
    }
