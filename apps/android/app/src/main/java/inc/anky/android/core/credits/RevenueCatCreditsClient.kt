package inc.anky.android.core.credits

import inc.anky.android.BuildConfig

data class CreditState(
    val isConfigured: Boolean,
    val balance: Int?,
    val message: String,
)

interface CreditsClient {
    suspend fun configure(appUserId: String)
    suspend fun refresh(): CreditState
    suspend fun purchase(packageId: String): CreditState
}

class RevenueCatCreditsClient : CreditsClient {
    private var configured = false

    override suspend fun configure(appUserId: String) {
        configured = BuildConfig.REVENUECAT_ANDROID_PUBLIC_KEY.isNotBlank() && appUserId.isNotBlank()
    }

    override suspend fun refresh(): CreditState =
        if (configured) {
            CreditState(
                isConfigured = true,
                balance = null,
                message = "RevenueCat is configured. Credit balance depends on project virtual currency setup.",
            )
        } else {
            CreditState(
                isConfigured = false,
                balance = null,
                message = "RevenueCat Android products are not configured in this build.",
            )
        }

    override suspend fun purchase(packageId: String): CreditState =
        CreditState(
            isConfigured = configured,
            balance = null,
            message = "Purchases are disabled until Google Play and RevenueCat Android offerings are configured.",
        )
}
