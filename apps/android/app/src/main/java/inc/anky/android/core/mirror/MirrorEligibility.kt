package inc.anky.android.core.mirror

import inc.anky.android.core.protocol.AnkyValidation
import inc.anky.android.core.protocol.AnkyValidator

object MirrorEligibility {
    fun canAsk(ankyText: String): Boolean =
        (AnkyValidator.validate(ankyText) as? AnkyValidation.Valid)?.isComplete == true

    fun reason(ankyText: String): String? {
        val validation = AnkyValidator.validate(ankyText)
        return when {
            validation !is AnkyValidation.Valid -> "This does not appear to be a valid .anky file."
            !validation.isComplete -> "Only complete 8-minute ankys can ask for reflection."
            else -> null
        }
    }
}
