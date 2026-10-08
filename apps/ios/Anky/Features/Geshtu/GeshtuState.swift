//
//  GeshtuState.swift
//  Anky — the Geshtu Redesign (spec §1, §2, §11).
//
//  The app is one page with a drawer beside it. This is the state machine
//  of that page: every face it can wear is one Phase below, and the drawer,
//  settings and stats are flags beside it.
//
//  Grammar (one-surface shell, 2026-10-08):
//    write → stillness or the writer ends it → the same page, finished
//    (continue writing / ask anky for reflection)
//    every written session is a row in the drawer and opens on this page
//

import SwiftUI

enum GeshtuReflectionChannelState: Equatable {
    /// The Geshtu is only the doorway into writing (the archive list).
    case none
    /// A writing is present, but has not been offered to Anky.
    case incomplete
    /// The reflection request is traveling.
    case listening
    /// Anky's reflection has returned and the channel is whole.
    case complete
}

@MainActor
final class GeshtuState: ObservableObject {

    /// The stations of the vertical world. There are no other destinations —
    /// no tabs, no nav stack, no back buttons (spec §1).
    enum Phase: Equatable {
        /// The front door: the writing page, keyboard up.
        case writing
        /// The sentinel fired (the writer's configured stillness elapsed). The
        /// keyboard fell and the crossroads stands: keep writing, get anky's
        /// reflection, or just leave (crossroads redesign, 2026-07-24).
        case channelClosed
        /// Anky's reflection unrolls beneath the writing, from the space where
        /// the keyboard stood, downward (spec §6, reshaped 2026-07-15; the
        /// electric ascent/descent interlude was removed 2026-07-24 — asking
        /// goes straight here, the spiral listening until the words arrive).
        /// The initial reflection and its threaded conversation live here.
        /// Asking ends the writing session — there is no way back to editing
        /// from this state.
        case reflection
        /// A past session opened from the drawer to read in full — the same
        /// document a just-finished writing becomes.
        case entryOpen
    }

    @Published private(set) var phase: Phase = .writing

    // MARK: - The drawer (one-surface shell, 2026-10-08)

    // The app is one surface with a drawer beside it, like a chat app: the
    // page in front is always the writing or one written session, and the
    // history lives in a drawer that slides in from the leading edge. The
    // drawer is not a destination, so it is not a phase — whatever was on the
    // page is still there when it closes.

    @Published private(set) var drawerIsOpen = false
    /// Settings and stats rise as sheets over whatever is standing.
    @Published var settingsIsOpen = false
    @Published var statsIsOpen = false

    func openDrawer() {
        guard !drawerIsOpen else { return }
        withAnimation(Self.drawerSpring) { drawerIsOpen = true }
    }

    func closeDrawer() {
        guard drawerIsOpen else { return }
        withAnimation(Self.drawerSpring) { drawerIsOpen = false }
    }

    static let drawerSpring = Animation.spring(response: 0.36, dampingFraction: 0.88)

    /// The just-sealed session awaiting its fate at `channelClosed`: sent for
    /// a reflection, kept writing, or settled unsent into the strata. Nil once
    /// resolved. Unsent is still saved locally — unsent ≠ lost (spec §4).
    @Published private(set) var pendingSession: SavedAnky?

    /// The sealed session the writer chose to keep writing (channel-close
    /// crossroads, 2026-07-24): carried across the phase change so the world
    /// can hand it back to the write engine as a continuation.
    @Published private(set) var sessionToResume: SavedAnky?

    /// A past session opened from the strata (`entryOpen`).
    @Published private(set) var openedEntry: SavedAnky?

    /// The native text range the writer has selected on a warm surface (the
    /// reflection canvas or an opened entry). The fixed top chrome honors it;
    /// with nothing chosen, copy carries the whole writing. Cleared on every
    /// phase transition — a choice never outlives its surface.
    @Published var selectedQuote: String?

    /// A tap on the Geshtu while reading never changes destination. It asks
    /// the mounted document to reveal the seam where the writer's words end
    /// and Anky's response begins.
    @Published private(set) var responseStartRequest = 0

    /// Reveal-page chrome follows the reader: it recedes while moving deeper
    /// into the document and returns as soon as they move back toward its top.
    @Published private(set) var revealChromeIsVisible = true

    func requestResponseStart() {
        responseStartRequest &+= 1
    }

    func setRevealChromeVisible(_ visible: Bool) {
        guard revealChromeIsVisible != visible else { return }
        revealChromeIsVisible = visible
    }

    // MARK: - Transitions

    /// Open the front door — a fresh writing session (app launch, the
    /// drawer's "new writing", or leaving a session that was just deleted).
    func openWriting() {
        openedEntry = nil
        pendingSession = nil
        selectedQuote = nil
        sessionToResume = nil
        withAnimation(.easeInOut(duration: 0.45)) { phase = .writing }
    }

    /// The writing ended: the channel closes and the keyboard falls, the
    /// words staying where they are. Driven by WriteViewModel's seal
    /// completion.
    func channelDidClose(session: SavedAnky?) {
        pendingSession = session
        selectedQuote = nil
        withAnimation(.easeInOut(duration: 0.65)) { phase = .channelClosed }
    }

    /// The "keep writing" option at the crossroads (2026-07-24): reopen the
    /// same sealed session — same words, same day. The world hands the
    /// carried session back to the write engine as a continuation; the
    /// reseal replaces the artifact.
    func resumeWriting() {
        guard phase == .channelClosed, let session = pendingSession else { return }
        sessionToResume = session
        pendingSession = nil
        selectedQuote = nil
        withAnimation(.easeInOut(duration: 0.45)) { phase = .writing }
    }

    /// One-shot read of the session `resumeWriting` carried across the phase
    /// change, taken by the world when the writing phase mounts.
    func consumeSessionToResume() -> SavedAnky? {
        defer { sessionToResume = nil }
        return sessionToResume
    }

    /// Enter the reflection document without sending anything. The channel is
    /// visibly incomplete until the writer holds Geshtu for three seconds.
    func openReflectionChannel() {
        guard phase == .channelClosed, pendingSession != nil else { return }
        selectedQuote = nil
        withAnimation(.easeInOut(duration: 0.55)) { phase = .reflection }
    }

    /// Open a past entry to read in full (spec §7). Memory brightens — and it
    /// brightens NOW: a snappy spring, not a slow dissolve (user decision,
    /// 2026-07-17).
    func openEntry(_ anky: SavedAnky) {
        selectedQuote = nil
        pendingSession = nil
        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
            openedEntry = anky
            phase = .entryOpen
        }
    }

    #if DEBUG
    /// Dev-only escape hatch: step the machine directly, for launch-env
    /// staging and screenshots.
    func debugSetPhase(_ next: Phase) {
        withAnimation(.easeInOut(duration: 0.4)) { phase = next }
    }

    /// Dev-only: stand a session at the closed channel without typing a real
    /// one; `debugSetPhase(.channelClosed)` alone has no session to show.
    func debugSetPendingSession(_ session: SavedAnky?) {
        pendingSession = session
    }
    #endif
}
