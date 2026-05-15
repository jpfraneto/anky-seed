package inc.anky.android.core.protocol

object AnkyValidator {
    fun validate(text: String): AnkyValidation {
        return try {
            if (text.trim().isEmpty()) throw AnkyParseException("EMPTY_ANKY")
            val parsed = AnkyParser.parse(text)
            val durationMs = AnkyDuration.durationMs(parsed)
            val kind = if (AnkyDuration.isComplete(parsed)) AnkyKind.Complete else AnkyKind.Fragment
            AnkyValidation.Valid(kind = kind, parsed = parsed, durationMs = durationMs)
        } catch (error: Throwable) {
            AnkyValidation.Invalid(error = error.message ?: "INVALID_ANKY")
        }
    }
}
