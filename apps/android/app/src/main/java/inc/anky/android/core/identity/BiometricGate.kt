package inc.anky.android.core.identity

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

interface BiometricGate {
    suspend fun authenticate(reason: String): Boolean
}

class DeviceBiometricGate(
    private val activityProvider: () -> FragmentActivity?,
) : BiometricGate {
    override suspend fun authenticate(reason: String): Boolean {
        val activity = activityProvider() ?: return false
        val canAuthenticate = BiometricManager.from(activity).canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL,
        )
        if (canAuthenticate != BiometricManager.BIOMETRIC_SUCCESS) return false
        return suspendCancellableCoroutine { continuation ->
            val prompt = BiometricPrompt(
                activity,
                ContextCompat.getMainExecutor(activity),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        continuation.resume(true)
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        continuation.resume(false)
                    }

                    override fun onAuthenticationFailed() {
                        if (continuation.isActive) continuation.resume(false)
                    }
                },
            )
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Anky")
                .setSubtitle(reason)
                .setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_WEAK or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL,
                )
                .build()
            prompt.authenticate(info)
        }
    }
}
