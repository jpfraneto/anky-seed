package inc.anky.android.core.mirror

import inc.anky.android.core.protocol.AnkyValidation
import inc.anky.android.core.protocol.AnkyValidator

object MirrorEligibility {
    fun canAsk(isComplete: Boolean, hasReflection: Boolean): Boolean =
        isComplete && !hasReflection

    fun canAsk(ankyText: String): Boolean =
        canAsk(
            isComplete = (AnkyValidator.validate(ankyText) as? AnkyValidation.Valid)?.isComplete == true,
            hasReflection = false,
        )

    fun reason(ankyText: String): String? {
        val validation = AnkyValidator.validate(ankyText)
        return when {
            validation !is AnkyValidation.Valid -> "This does not appear to be a valid .anky file."
            !validation.isComplete -> "Only complete 8-minute ankys can ask for reflection."
            else -> null
        }
    }
}

sealed interface ReflectionCreditPromptState {
    data class Available(val count: Int) : ReflectionCreditPromptState
    data class FreeGift(val count: Int) : ReflectionCreditPromptState
    data object Unavailable : ReflectionCreditPromptState
    data object Unknown : ReflectionCreditPromptState
}

object ReflectionCreditPresentation {
    const val FirstGiftCount = 8

    fun state(
        creditsRemaining: Int?,
        hasClaimedFreeCredits: Boolean,
        creditsDenied: Boolean = false,
    ): ReflectionCreditPromptState {
        if (creditsDenied) return ReflectionCreditPromptState.Unavailable
        creditsRemaining?.let { balance ->
            if (balance > 0) return ReflectionCreditPromptState.Available(balance)
            return if (hasClaimedFreeCredits) {
                ReflectionCreditPromptState.Unavailable
            } else {
                ReflectionCreditPromptState.FreeGift(FirstGiftCount)
            }
        }
        return if (hasClaimedFreeCredits) {
            ReflectionCreditPromptState.Unknown
        } else {
            ReflectionCreditPromptState.FreeGift(FirstGiftCount)
        }
    }

    fun messageFor(state: ReflectionCreditPromptState): String =
        when (state) {
            is ReflectionCreditPromptState.Available -> "You have ${state.count} ${if (state.count == 1) "reflection" else "reflections"} left"
            is ReflectionCreditPromptState.FreeGift -> "Anky gives you ${state.count} free reflections"
            ReflectionCreditPromptState.Unavailable -> "No reflections left"
            ReflectionCreditPromptState.Unknown -> "Checking reflections"
        }
}
