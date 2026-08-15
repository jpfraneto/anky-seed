package inc.anky.android.core.continuity

/**
 * The small, platform-neutral genome of Anky's Geshtu experience.
 *
 * UI, storage, purchases, reflection transport, and the writing engine are
 * adapters around this reducer. Keeping the transition law here prevents the
 * Android composition root from drifting back into screen-by-screen routing.
 */
enum class GeshtuPhase {
    Writing,
    ChannelClosed,
    Reflection,
    Landing,
    EntryOpen,
    Seed,
}

data class GeshtuContinuity(
    val phase: GeshtuPhase = GeshtuPhase.Writing,
    val pendingSessionHash: String? = null,
    val sessionToResumeHash: String? = null,
    val openedEntryHash: String? = null,
    val isLateOfferingArmed: Boolean = false,
) {
    val isDeviceSpace: Boolean
        get() = phase == GeshtuPhase.Writing ||
            phase == GeshtuPhase.ChannelClosed ||
            phase == GeshtuPhase.Reflection

    val anchorIsVisible: Boolean
        get() = !isDeviceSpace && phase != GeshtuPhase.Seed

    val offeringStands: Boolean
        get() = pendingSessionHash != null &&
            (phase == GeshtuPhase.ChannelClosed ||
                (phase == GeshtuPhase.EntryOpen && isLateOfferingArmed))
}

sealed interface GeshtuEvent {
    data object OpenWriting : GeshtuEvent
    data class ChannelClosed(val sessionHash: String) : GeshtuEvent
    data object KeepWriting : GeshtuEvent
    data object SendOffering : GeshtuEvent
    data object Settle : GeshtuEvent
    data class OpenEntry(val sessionHash: String) : GeshtuEvent
    data object CloseEntry : GeshtuEvent
    data object ArmLateOffering : GeshtuEvent
    data object OpenSeed : GeshtuEvent
    data object CloseSeed : GeshtuEvent
}

object GeshtuReducer {
    fun reduce(state: GeshtuContinuity, event: GeshtuEvent): GeshtuContinuity =
        when (event) {
            GeshtuEvent.OpenWriting -> state.copy(
                phase = GeshtuPhase.Writing,
                pendingSessionHash = null,
                sessionToResumeHash = null,
                openedEntryHash = null,
                isLateOfferingArmed = false,
            )

            is GeshtuEvent.ChannelClosed -> {
                if (state.phase != GeshtuPhase.Writing) state
                else state.copy(
                    phase = GeshtuPhase.ChannelClosed,
                    pendingSessionHash = event.sessionHash,
                    sessionToResumeHash = null,
                )
            }

            GeshtuEvent.KeepWriting -> {
                val hash = state.pendingSessionHash
                if (state.phase != GeshtuPhase.ChannelClosed || hash == null) state
                else state.copy(
                    phase = GeshtuPhase.Writing,
                    pendingSessionHash = null,
                    sessionToResumeHash = hash,
                )
            }

            GeshtuEvent.SendOffering -> {
                if (!state.offeringStands) state
                else state.copy(phase = GeshtuPhase.Reflection)
            }

            GeshtuEvent.Settle -> state.copy(
                phase = GeshtuPhase.Landing,
                pendingSessionHash = null,
                sessionToResumeHash = null,
                openedEntryHash = null,
                isLateOfferingArmed = false,
            )

            is GeshtuEvent.OpenEntry -> {
                if (state.phase != GeshtuPhase.Landing) state
                else state.copy(
                    phase = GeshtuPhase.EntryOpen,
                    openedEntryHash = event.sessionHash,
                    pendingSessionHash = null,
                    isLateOfferingArmed = false,
                )
            }

            GeshtuEvent.CloseEntry -> {
                if (state.phase != GeshtuPhase.EntryOpen) state
                else state.copy(
                    phase = GeshtuPhase.Landing,
                    openedEntryHash = null,
                    pendingSessionHash = null,
                    isLateOfferingArmed = false,
                )
            }

            GeshtuEvent.ArmLateOffering -> {
                val hash = state.openedEntryHash
                if (state.phase != GeshtuPhase.EntryOpen || hash == null) state
                else state.copy(
                    pendingSessionHash = hash,
                    isLateOfferingArmed = true,
                )
            }

            GeshtuEvent.OpenSeed -> {
                if (state.phase != GeshtuPhase.Landing && state.phase != GeshtuPhase.EntryOpen) state
                else state.copy(phase = GeshtuPhase.Seed)
            }

            GeshtuEvent.CloseSeed -> {
                if (state.phase != GeshtuPhase.Seed) state
                else state.copy(
                    phase = if (state.openedEntryHash == null) GeshtuPhase.Landing else GeshtuPhase.EntryOpen,
                )
            }
        }
}
