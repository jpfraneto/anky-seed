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
