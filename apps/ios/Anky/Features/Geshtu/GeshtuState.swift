//
//  GeshtuState.swift
//  Anky — the Geshtu Redesign (spec §1, §2, §11).
//
//  The app is no longer a set of screens. It is one vertical world
//  organized around a single fixed point: the Anchor. This is the state
//  machine of that world — it replaces AppRoot's selectedTab / writeSurface
//  router. Every surface the app can show is one Phase below.
//
//  Grammar (crossroads redesign, 2026-07-24):
//    write → stillness closes the channel → the crossroads
//    (keep writing / get anky's reflection / just leave)
//    days settle around the Anchor to be kept (reflection → landing)
//

import SwiftUI

@MainActor
final class GeshtuState: ObservableObject {

    /// The stations of the vertical world. There are no other destinations —
    /// no tabs, no nav stack, no back buttons (spec §1).
    enum Phase: Equatable {
        /// The front door. Keyboard up the whole time; the Anchor is covered
        /// by the keyboard and is not a navigation primitive here (spec §3).
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
        /// The landing surface / history strata: days settled around the
        /// Anchor, fading with age (spec §7).
        case landing
        /// A past entry opened from the strata to read in full — this is where
        /// copy / share / record live (spec §7, §12).
        case entryOpen
        /// The seed at the base of the past: settings, subscription, account
        /// deletion (spec §7).
        case seed
    }

    @Published private(set) var phase: Phase = .writing

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

    /// A past, unreflected day armed for a late offering (user idea,
    /// 2026-07-17): the grey geshtu at the day's base was taken, gravity
    /// pulled it into the Anchor, and now the Anchor awaits the hold while
    /// the entry stays open. The vigil grammar is identical to a fresh
    /// channel close — only the origin differs. Cleared whenever the entry
    /// closes or the world moves on.
    @Published private(set) var reOffering = false

    /// The native text range the writer has selected on a warm surface (the
    /// reflection canvas or an opened entry). The fixed top chrome honors it;
    /// with nothing chosen, share carries the whole writing. Cleared on every
    /// phase transition — a choice never outlives its surface.
    @Published var selectedQuote: String? {
        didSet { if selectedQuote == nil { selectedQuoteIsAnky = false } }
    }

    /// Whose words the chosen paragraph is: false = the writer's (YOU card),
    /// true = Anky's reflection (ANKY card). Set alongside `selectedQuote` by
    /// whichever tappable surface made the choice; resets with it.
    @Published var selectedQuoteIsAnky = false

    // MARK: - The two spaces (device split, 2026-07-22)

    // The unified-scroll approach machinery (approach/surface ticks,
    // landingAtTop) is gone with the device split: the writing page is no
    // longer the top of the world scroll, so summoning it is a phase change —
    // never a scroll journey through the strata.

    /// Every phase lives in one of two spaces. The DEVICE is the writing
    /// machine — a sovereign, full-screen surface holding the entire ritual:
    /// writing, the closed channel, and the reflection. The WORLD is
    /// everything outside it: the strata, an opened day, and the seed. The
    /// device appears as a frontmost screen over the world; the world
    /// underneath never contains the page.
    var isDeviceSpace: Bool {
        switch phase {
        case .writing, .channelClosed, .reflection:
            return true
        case .landing, .entryOpen, .seed:
            return false
        }
    }

    // MARK: - The Anchor's grammar (spec §2)

    /// The Anchor belongs to the archive list, where it opens a new writing
    /// session. An opened archive entry is the canonical finished-session
    /// document, so no floating control is allowed to cover its conversation.
    var anchorIsVisible: Bool {
        phase == .landing
    }

    /// A quick Anchor tap is navigational only on the archive list.
    var anchorTapIsNavigational: Bool {
        phase == .landing
    }

    /// A quick tap summons the writing device from anywhere in the world
    /// (device split, 2026-07-22): the device is not the top of a scroll, so
    /// there is no living-edge condition — the tap is the summons itself.
    var anchorTapEntersWriting: Bool {
        phase == .landing
    }

    /// An offering is standing and may travel: a channel closed with an unsent
    /// session resting above it, or a late offering armed over an open day.
    /// The Geshtu does not carry empty offerings (spec §2). Sending is a tap
    /// (crossroads redesign, 2026-07-24 — the hold and its electric register
    /// are gone).
    var offeringStands: Bool {
        (phase == .channelClosed || (phase == .entryOpen && reOffering)) && pendingSession != nil
    }

    /// A faint vertical filament rises from the Anchor over an armed late
    /// offering — the hint that this day can still travel.
    var showsFilament: Bool {
        phase == .entryOpen && reOffering
    }

    // MARK: - Transitions

    /// Open the front door — a fresh writing session (app launch, or beginning
    /// again from the landing surface).
    func openWriting() {
        openedEntry = nil
        selectedQuote = nil
        reOffering = false
        sessionToResume = nil
        withAnimation(.easeInOut(duration: 0.45)) { phase = .writing }
    }

    /// The sentinel fired: the channel closes, the keyboard falls, the Anchor
    /// is revealed above the resting session (spec §4). Driven by
    /// WriteViewModel's seal completion.
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

    /// The offering travels — one tap, straight to the reflection surface
    /// (crossroads redesign + simplicity pass, 2026-07-24: no vigil, no
    /// electric interlude). Guarded by the grammar: no empty offerings.
    /// Asking ends the session; the spiral listens until the words arrive.
    func sendOffering() {
        guard offeringStands else { return }
        withAnimation(.easeInOut(duration: 0.55)) { phase = .reflection }
    }

    /// Scroll past the reflection's last line, or walk away from the closed
    /// channel: the day settles into the strata as the newest layer (spec §7).
    func settleToLanding() {
        pendingSession = nil
        selectedQuote = nil
        reOffering = false
        withAnimation(.easeInOut(duration: 0.55)) { phase = .landing }
    }

    /// The grey geshtu at the base of an unreflected day was taken and
    /// gravity carried it into the Anchor: the day stands as the offering.
    /// From here the ordinary vigil grammar takes over — hold to send, lift
    /// to drain back to the open day.
    func armReOffering(_ session: SavedAnky) {
        guard phase == .entryOpen else { return }
        pendingSession = session
        withAnimation(.easeInOut(duration: 0.45)) { reOffering = true }
    }

    /// The Anchor was tapped on a warm surface: show the device as a new
    /// frontmost screen. The world holds its place beneath for the return.
    func anchorTapped() {
        switch phase {
        case .landing:
            openWriting()
        case .entryOpen:
            closeEntry()
            openWriting()
        default:
            break
        }
    }

    /// Open a past entry to read in full (spec §7). Memory brightens — and it
    /// brightens NOW: a snappy spring, not a slow dissolve (user decision,
    /// 2026-07-17).
    func openEntry(_ anky: SavedAnky) {
        selectedQuote = nil
        if reOffering {
            reOffering = false
            pendingSession = nil
        }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
            openedEntry = anky
            phase = .entryOpen
        }
    }

    func closeEntry() {
        selectedQuote = nil
        if reOffering {
            reOffering = false
            pendingSession = nil
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            openedEntry = nil
            phase = .landing
        }
    }

    /// The seed at the base of the past — settings and identity (spec §7).
    func openSeed() {
        withAnimation(.easeInOut(duration: 0.4)) { phase = .seed }
    }

    func closeSeed() {
        withAnimation(.easeInOut(duration: 0.4)) { phase = .landing }
    }

    #if DEBUG
    /// Dev-only: force the landing surface to re-read the archive after seeding.
    @Published private(set) var debugReloadTick = 0
    func debugReloadLanding() { debugReloadTick &+= 1 }

    /// Dev-only escape hatch: step the machine directly while the phase
    /// surfaces are still Phase-1 scaffolds. Removed in Phase 8 once every
    /// transition is driven by real wiring (writing seal, held Anchor, scroll).
    func debugSetPhase(_ next: Phase) {
        withAnimation(.easeInOut(duration: 0.4)) { phase = next }
    }

    /// Dev-only: stand a session at the closed channel so the awaiting-vigil
    /// anchor (glow, sparks, filament) is screenshot-verifiable without
    /// typing a real session. The grammar (`offeringStands`) needs a
    /// pending session; `debugSetPhase(.channelClosed)` alone shows none.
    func debugSetPendingSession(_ session: SavedAnky?) {
        pendingSession = session
    }
    #endif
}
