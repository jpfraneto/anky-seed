package inc.anky.android.core.mirror

data class MirrorResponsePayload(
    val hash: String,
    val title: String,
    val reflection: String,
    val creditsRemaining: Int?,
)

enum class MirrorErrorCode {
    InvalidAnky,
    IncompleteRitual,
    MissingSignature,
    InvalidSignature,
    InsufficientCredits,
    DuplicateInProgress,
    RateLimited,
    MirrorFailed,
    BodyTooLarge,
    Unknown,
}

sealed class MirrorClientError(message: String) : Exception(message) {
    data object InvalidUrl : MirrorClientError("The mirror URL is not valid.")
    data object InvalidResponse : MirrorClientError("The mirror returned an invalid response.")
    data object HashMismatch : MirrorClientError("The mirror response did not match this .anky.")
    data class Server(val code: MirrorErrorCode, override val message: String) : MirrorClientError(message)
}
