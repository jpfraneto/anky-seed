package inc.anky.android.core.protocol

data class AnkyEvent(
    val deltaMs: Long,
    val glyph: String,
)

data class ParsedAnky(
    val startEpochMs: Long,
    val events: List<AnkyEvent>,
    val terminalSilenceMs: Long?,
)

enum class AnkyKind {
    Fragment,
    Complete,
}

sealed interface AnkyValidation {
    val isValid: Boolean
    val isComplete: Boolean

    data class Valid(
        val kind: AnkyKind,
        val parsed: ParsedAnky,
        val durationMs: Long,
    ) : AnkyValidation {
        override val isValid: Boolean = true
        override val isComplete: Boolean = kind == AnkyKind.Complete
    }

    data class Invalid(
        val error: String,
    ) : AnkyValidation {
        override val isValid: Boolean = false
        override val isComplete: Boolean = false
    }
}

class AnkyParseException(message: String) : IllegalArgumentException(message)
