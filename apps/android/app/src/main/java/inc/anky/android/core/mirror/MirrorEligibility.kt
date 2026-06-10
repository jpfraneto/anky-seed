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

object AnkyReflectionPrompt {
    fun build(reconstructedText: String): String =
        """
        Take a look at this stream-of-consciousness journal entry.

        Respond with deep insight that feels personal, casual, and alive, not clinical. Be a sharp mirror: part close friend, part mentor, part pattern-recognizer.

        Help the writer see the emotional undercurrents, hidden loops, deeper meaning, contradictions, longings, and connections they might be missing.

        Comfort what is real. Validate without flattering. Challenge gently where needed. Reframe the surface topic into what the writer may really be seeking underneath.

        Do not force introspection for its own sake. Help the writer recognize something true about who they are and move toward a more honest, positive loop in life.

        Use vivid metaphors and powerful imagery when they reveal something real. Don't diagnose, don't sound like therapy, and don't give generic advice.

        Write in the same language and vibe as the entry.

        Reply with pure markdown, and use headings for different sections. At the top of the reply add a max 4 word title.

        ---

        $reconstructedText
        """.trimIndent()
}

sealed interface ReflectionCreditPromptState {
    data class Available(val count: Int) : ReflectionCreditPromptState
    data class FreeGift(val count: Int) : ReflectionCreditPromptState
    data object Unavailable : ReflectionCreditPromptState
    data object Unknown : ReflectionCreditPromptState
}

object ReflectionCreditPresentation {
    const val FirstGiftCount = 2

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
            ReflectionCreditPromptState.Unavailable
        } else {
            ReflectionCreditPromptState.FreeGift(FirstGiftCount)
        }
    }

    fun messageFor(state: ReflectionCreditPromptState): String =
        when (state) {
            is ReflectionCreditPromptState.Available -> "You have ${state.count} ${if (state.count == 1) "reflection" else "reflections"} left"
            is ReflectionCreditPromptState.FreeGift -> "${state.count} ${if (state.count == 1) "reflection" else "reflections"} available on this device"
            ReflectionCreditPromptState.Unavailable -> "No reflections left"
            ReflectionCreditPromptState.Unknown -> "Reflection balance updates after mirroring"
        }
}
