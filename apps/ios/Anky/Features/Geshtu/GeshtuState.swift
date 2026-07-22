//
//  GeshtuState.swift
//  Anky — the Geshtu Redesign (spec §1, §2, §11).
//
//  The app is no longer a set of screens. It is one vertical world
//  organized around a single fixed point: the Anchor. This is the state
//  machine of that world — it replaces AppRoot's selectedTab / writeSurface
//  router. Every surface the app can show is one Phase below.
//
//  Cosmological grammar (spec §1):
//    words rise from the Anchor to be heard  (writing → channelClosed → vigil)
//    days settle around it to be kept        (reflection → landing)
//  Cold ascent, warm descent.
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
        /// The sentinel fired (8s of silence). The keyboard fell and the
        /// Anchor is revealed in its eternal position, a filament rising from
        /// it. Hold to send, or walk away to settle unsent (spec §4).
        case channelClosed
        /// The send vigil: the electric register, the seven-stop spine, the
        /// writing climbing to the spiral ear. Held from the Anchor (spec §5).
        case vigil
        /// The offering was carried: the words hold at the crown — the glow at
        /// the top — until Anky's response is ready, then the same movement
        /// runs back down the spine, the words traveling down to the Anchor
        /// (product decision, 2026-07-15).
        case descent
        /// The descent landed: the register warms and Anky's reflection unrolls
        /// beneath the writing, from the space where the keyboard stood,
        /// downward (spec §6, reshaped 2026-07-15). Finite, received, no reply.
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

    /// The just-sealed session awaiting its fate at `channelClosed`: held into
    /// a vigil, or settled unsent into the strata. Nil once resolved. Unsent is
    /// still saved locally — unsent ≠ lost (spec §4).
    @Published private(set) var pendingSession: SavedAnky?

    /// A past session opened from the strata (`entryOpen`).
    @Published private(set) var openedEntry: SavedAnky?

    /// A past, unreflected day armed for a late offering (user idea,
    /// 2026-07-17): the grey geshtu at the day's base was taken, gravity
    /// pulled it into the Anchor, and now the Anchor awaits the hold while
    /// the entry stays open. The vigil grammar is identical to a fresh
    /// channel close — only the origin differs. Cleared whenever the entry
    /// closes or the world moves on.
    @Published private(set) var reOffering = false

    /// The paragraph the writer has chosen on a warm surface (the reflection
    /// canvas or an opened entry). The fixed top chrome's share honors it;
    /// with nothing chosen, share carries the whole writing. Cleared on every
    /// phase transition — a choice never outlives its surface.
    @Published var selectedQuote: String? {
        didSet { if selectedQuote == nil { selectedQuoteIsAnky = false } }
    }

    /// Whose words the chosen paragraph is: false = the writer's (YOU card),
    /// true = Anky's reflection (ANKY card). Set alongside `selectedQuote` by
    /// whichever tappable surface made the choice; resets with it.
    @Published var selectedQuoteIsAnky = false

    // MARK: - Landing surface scroll position (addendum A1)

    /// The living edge: true when the strata rests at — or within ~half a screen
    /// of — the newest entry at the top of the column. Updated by the landing
    /// surface's scroll sentinel. Tap resolution reads it: a writing session is
    /// only ever launched from a person who has arrived at now, never from deep
    /// in memory. "At rest at the top" has tolerance; no pixel-hunting.
    @Published var landingAtTop: Bool = true

    /// A monotonic signal the landing surface observes to surface-to-now: come
    /// up for air, fast, with a slight overshoot that settles at the newest
    /// entry. Incremented by `requestSurface()`; never chained to writing.
    @Published private(set) var surfaceTick: Int = 0

    func requestSurface() {
        surfaceTick &+= 1
    }

    /// A monotonic signal the landing surface observes to carry the strata up
    /// into the writing approach: the smooth scroll that brings the reserved
    /// keyboard footprint into view, locks it at the base of the screen, and
    /// opens the keyboard. The geshtu tap and the writer's own scroll travel
    /// the identical road.
    @Published private(set) var approachTick: Int = 0

    func requestApproach() {
        approachTick &+= 1
    }

    // MARK: - Vigil duration (spec §5)

    private let vigilDurationKey = "anky.vigilDurationSeconds"

    /// The hold required to send. User-configurable at the seed, but never
    /// below the hard floor of 3 seconds. Defaults to 8 — deliberately
    /// mirroring the sentinel: the channel closes through 8s of absence; the
    /// writing sends through 8s of presence.
    static let vigilFloorSeconds: TimeInterval = 3
    static let vigilDefaultSeconds: TimeInterval = 8

    var vigilDuration: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: vigilDurationKey)
        guard stored > 0 else { return Self.vigilDefaultSeconds }
        return max(Self.vigilFloorSeconds, stored)
    }

    func setVigilDuration(_ seconds: TimeInterval) {
        UserDefaults.standard.set(max(Self.vigilFloorSeconds, seconds), forKey: vigilDurationKey)
        objectWillChange.send()
    }

    // MARK: - The Anchor's grammar (spec §2)

    /// The Anchor only mounts once the channel has closed — while writing, the
    /// keyboard covers its position and the state machine keeps it inert, so
    /// you cannot send while the channel is open (spec §3). It is also present
    /// on every warm surface below.
    var anchorIsVisible: Bool {
        phase != .writing
    }

    /// A quick Anchor tap is navigational on the warm surfaces where the strata
    /// lives — the landing column and an opened entry (addendum A1). Elsewhere a
    /// tap is suspended or, at `channelClosed`, at most a soft pulse (spec §2).
    var anchorTapIsNavigational: Bool {
        phase == .landing || phase == .entryOpen
    }

    /// A quick tap would begin a writing session only when at rest at the living
    /// edge (spec §2, refined by addendum A1). Scrolled deep in the strata, the
    /// same tap surfaces to now instead — writing never launches from momentum.
    var anchorTapEntersWriting: Bool {
        phase == .landing && landingAtTop
    }

    /// The long-press vigil is available only when a channel has closed with an
    /// unsent session resting above it. The Geshtu does not carry empty
    /// offerings (spec §2).
    var anchorSupportsVigil: Bool {
        (phase == .channelClosed || (phase == .entryOpen && reOffering)) && pendingSession != nil
    }

    /// The electric register is shown during the send vigil and the descent
    /// that answers it (spec §1, §5).
    var isElectricRegister: Bool {
        phase == .vigil || phase == .descent
    }

    /// A faint vertical filament rises from the Anchor once revealed, the hint
    /// of the base of the spine (spec §4).
    var showsFilament: Bool {
        phase == .channelClosed || (phase == .entryOpen && reOffering)
    }

    // MARK: - Transitions

    /// Open the front door — a fresh writing session (app launch, or beginning
    /// again from the landing surface).
    func openWriting() {
        openedEntry = nil
        selectedQuote = nil
        reOffering = false
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

    /// Begin the send vigil from a held Anchor (spec §5). Guarded by the
    /// grammar — no empty offerings.
    func beginVigil() {
        guard anchorSupportsVigil else { return }
        withAnimation(.easeInOut(duration: 0.4)) { phase = .vigil }
    }

    /// The thumb lifted before completion: the energy drained fully back down
    /// the spine. Return to where the offering stood — the closed channel, or
    /// the opened day of a late offering; the next attempt starts from zero
    /// (spec §5).
    func vigilDrained() {
        guard phase == .vigil else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = reOffering ? .entryOpen : .channelClosed
        }
    }

    /// The hold completed: the offering was carried to the crown. The words
    /// hold there — the glow at the top — until the response is ready, then
    /// travel back down the spine (the descent surface drives that motion).
    func vigilCompleted() {
        guard phase == .vigil else { return }
        withAnimation(.easeInOut(duration: 0.4)) { phase = .descent }
    }

    /// The descent reached the Anchor: the register warms back to lazure and
    /// the reflection unrolls beneath the writing.
    func descentLanded() {
        guard phase == .descent else { return }
        withAnimation(.easeInOut(duration: 0.7)) { phase = .reflection }
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

    /// The Anchor was tapped on a warm surface. One tap carries you home to
    /// the blank page, wherever you are in memory (user decision, 2026-07-16,
    /// superseding addendum A1's never-chain rule): the strata surfaces to
    /// now, and then the writing surface scrolls into view above it — the top
    /// of the whole vertical thing IS the writing interface.
    func anchorTapped() {
        switch phase {
        case .landing:
            if landingAtTop {
                requestApproach()
            } else {
                requestSurface()
                openWritingAfterSurfacing()
            }
        case .entryOpen:
            closeEntry()
            requestSurface()
            openWritingAfterSurfacing()
        default:
            break
        }
    }

    /// The second half of the tap's journey: give the surfacing spring its
    /// beat, then open the front door — unless the writer moved somewhere
    /// else in the meantime.
    private func openWritingAfterSurfacing() {
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard phase == .landing else { return }
            requestApproach()
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
    /// typing a real session. The grammar (`anchorSupportsVigil`) needs a
    /// pending session; `debugSetPhase(.channelClosed)` alone shows none.
    func debugSetPendingSession(_ session: SavedAnky?) {
        pendingSession = session
    }
    #endif
}
