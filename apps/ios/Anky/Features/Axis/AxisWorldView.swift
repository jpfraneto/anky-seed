//
//  AxisWorldView.swift
//  Anky — the Axis Redesign (spec §1, §11).
//
//  The container of the vertical world: it renders whatever surface the
//  current AxisState.Phase calls for, with the Anchor overlaid above the
//  entire hierarchy at its fixed, eternal position. The registers switch here
//  — warm lazure for the human world, electric indigo only during the vigil.
//
//  Phase 1 note: the per-phase surfaces below are lazure scaffolds. Real
//  surfaces arrive in later phases — the strata (§2), the reveal keyboard-fall
//  (§3), the electric vigil (§4), the reflection descent (§5). The state
//  machine and the Anchor are permanent; only the surfaces get replaced.
//

import SwiftUI

struct AxisWorldView: View {
    @StateObject private var axis = AxisState()
    /// The axis world owns one writing engine — the real WriteViewModel, with
    /// its 62.5Hz ticker, per-keystroke atomic writes, and the 8s sentinel. The
    /// axis only listens for the seal; it never reimplements the mechanics.
    @StateObject private var writeViewModel = WriteViewModel()
    /// The send vigil's charge/haptics, driven by the continuous Anchor press.
    @StateObject private var vigil = VigilController()
    /// Fires the reflection request at the sentinel so the vigil hides latency.
    @StateObject private var reflection = AxisReflectionCoordinator()
    /// The one-time onboarding rehearsal (spec §9): the first channel-close
    /// shows the hint and the Anchor's single inhale, and the first vigil is the
    /// first real offering. Set true once the writer completes it.
    @AppStorage("anky.axisRehearsalDone") private var rehearsalDone = false
    /// Writing is free; the vigil is the paid act. The first vigil is free so
    /// the rehearsal completes with a real reflection and the paywall is first
    /// met on day two (product decision, ratified).
    ///
    /// TODO(server-reconcile): this is device-side (@AppStorage → UserDefaults),
    /// so a reinstall grants a second free vigil (verification Q1). Before ship
    /// it must key to account identity — the RevenueCat appUserID or the writer's
    /// wallet address — reconciled server-side, so the free vigil is spent once
    /// per person, not once per install.
    @AppStorage("anky.axisFirstVigilUsed") private var firstVigilUsed = false
    @StateObject private var entitlements = EntitlementStore()
    @State private var showsPaywall = false
    // The seed (spec §7): identity, subscription, recovery phrase, account
    // deletion, and the gate — the real settings, reached by scrolling to the
    // base of the past.
    @StateObject private var youViewModel = YouViewModel()
    @StateObject private var gateViewModel = WriteBeforeScrollSpikeViewModel()
    @State private var showsGateSetup = false

    private var showRehearsalHint: Bool {
        axis.phase == .channelClosed && !rehearsalDone
    }

    private var vigilAllowed: Bool {
        entitlements.isEntitledForGating || !firstVigilUsed
    }

    var body: some View {
        ZStack {
            register
                .ignoresSafeArea()

            surface
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if axis.anchorIsVisible {
                AnchorView(
                    axis: axis,
                    vigil: vigil,
                    rehearsalInhale: showRehearsalHint,
                    vigilAllowed: vigilAllowed,
                    onNeedsPaywall: { showsPaywall = true }
                )
                .zIndex(1000)
            }

            // The one-time rehearsal hint, resting just above the Anchor.
            if showRehearsalHint {
                VStack(spacing: 0) {
                    Spacer()
                    Text("hold, and don't let go")
                        .font(.fraunces(17, weight: .light, italic: true))
                        .foregroundStyle(Color.ankyInkSoft)
                        .padding(.bottom, 170)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
                .zIndex(1001)
            }

            #if DEBUG
            DebugAxisStepper(axis: axis)
                .zIndex(2000)
            #endif
        }
        .environmentObject(axis)
        .preferredColorScheme(axis.isElectricRegister ? .dark : nil)
        .animation(.easeInOut(duration: 0.5), value: axis.isElectricRegister)
        #if DEBUG
        // Deterministic launch-driven seeding + navigation, so the addendum
        // surfaces can be screenshot-verified without a tap tool. Env keys:
        //   AXIS_DEBUG_SEED = showcase | bulk
        //   AXIS_DEBUG_PHASE = landing | entry | reflection | ...
        //   AXIS_DEBUG_OPEN_FIRST = 1   (open the newest strata entry)
        .onAppear(perform: applyDebugLaunchEnv)
        #endif
        // The paid act: a quiet lazure paywall rises from the bottom when an
        // unentitled writer holds. Dismissing returns to the closed channel;
        // the session settles unsent and is never lost.
        .sheet(isPresented: $showsPaywall) {
            PaywallSheet(store: entitlements, origin: "vigil")
        }
        .sheet(isPresented: $showsGateSetup) {
            GateSetupView(viewModel: gateViewModel, onDone: { showsGateSetup = false })
        }
        .onChange(of: axis.phase) { newPhase in
            switch newPhase {
            case .writing:
                // The rehearsal shortens the sentinel so the reveal — and the
                // long-press vigil — is discoverable quickly (spec §9). Set
                // before the reset so the first session picks it up.
                writeViewModel.terminalSilenceOverrideMs = rehearsalDone ? nil : 4000
                // Tapping the Anchor to write begins a fresh session; the
                // previous day is already sealed, so the engine can reset.
                writeViewModel.beginBlankSessionFromWriteTab()
                reflection.discard()
            case .reflection:
                // A vigil completed: the offering was carried. Only now does the
                // held reflection reach the store (addendum A3 / Q4) — an unsent
                // session's reflection is never persisted.
                reflection.commit()
                // The free one is spent, and the rehearsal (if this was it) is
                // over and never explained again.
                firstVigilUsed = true
                if !rehearsalDone {
                    rehearsalDone = true
                    writeViewModel.terminalSilenceOverrideMs = nil
                }
            case .channelClosed:
                // Fire the reflection at the sentinel — the vigil will hide the
                // latency (spec §12). Safe even if the writer never sends; it is
                // discarded below if they walk away.
                if let session = axis.pendingSession {
                    reflection.begin(for: session)
                }
            case .landing:
                // Walked away, or the reflection settled: drop any unsent
                // in-flight result.
                reflection.discard()
            default:
                break
            }
        }
    }

    #if DEBUG
    private func applyDebugLaunchEnv() {
        let env = ProcessInfo.processInfo.environment
        switch env["AXIS_DEBUG_SEED"] {
        case "showcase": AxisDebugSeed.seedShowcase()
        case "bulk":     AxisDebugSeed.seedBulk(500)
        default:         break
        }
        if env["AXIS_DEBUG_OPEN_FIRST"] == "1", let first = LocalAnkyArchive().list().first {
            axis.openEntry(first)
            return
        }
        if env["AXIS_DEBUG_OPEN_UNSENT"] == "1",
           let unsent = LocalAnkyArchive().list().first(where: { ReflectionStore().load(hash: $0.hash) == nil }) {
            axis.openEntry(unsent)
            return
        }
        switch env["AXIS_DEBUG_PHASE"] {
        case "landing":    axis.debugSetPhase(.landing)
        case "entry":      axis.debugSetPhase(.entryOpen)
        case "reflection": axis.debugSetPhase(.reflection)
        case "closed":     axis.debugSetPhase(.channelClosed)
        case "vigil":      axis.debugSetPhase(.vigil)
        case "seed":       axis.debugSetPhase(.seed)
        default:           break
        }
    }
    #endif

    // MARK: - Register (the ground the world is painted on)

    @ViewBuilder
    private var register: some View {
        if axis.isElectricRegister {
            ElectricRegister()
        } else {
            LazureWall(mood: .dawn)
        }
    }

    // The electric vigil surface — a pure function of the controller's charge.
    @ViewBuilder
    private var vigilSurface: some View {
        #if DEBUG
        let sample = "tonight i sat with the kind of quiet that has weight not empty but full in a way i cannot always explain i stayed i kept choosing life love is quieter than fear"
        VigilView(charge: vigil.charge, text: axis.pendingSession?.reconstructedText ?? sample)
            .onAppear { if vigil.stage == .idle { vigil.debugDemo() } }
        #else
        VigilView(charge: vigil.charge, text: axis.pendingSession?.reconstructedText ?? "")
        #endif
    }

    // MARK: - Per-phase surface (scaffolds until later phases)

    @ViewBuilder
    private var surface: some View {
        switch axis.phase {
        case .writing:
            // The front door: the real writing engine, keyboard up, only the
            // sentinel can close it. On seal the channel closes and the axis
            // swaps away — the post-session beat never mounts (spec §3).
            WriteView(
                viewModel: writeViewModel,
                shouldFocus: true,
                axisMode: true,
                onCompleted: { saved in axis.channelDidClose(session: saved) },
                onCloseToMap: {}
            )
        case .channelClosed:
            ChannelClosedView(
                session: axis.pendingSession,
                onSettle: { axis.settleToLanding() }
            )
        case .vigil:
            vigilSurface
        case .reflection:
            if let vm = reflection.viewModel {
                ReflectionSettleView(viewModel: vm, axis: axis)
            } else {
                #if DEBUG
                // Debug stepper reached this without a live request: preview the
                // descent layout with a sample blessing.
                ReflectionLinesView(lines: [
                    "you stayed.",
                    "and the room stayed with you.",
                    "love is quieter than fear.",
                    "take this warmth with you.",
                    "begin again from here."
                ])
                #else
                ScaffoldSurface(line: "the ear is listening", detail: "")
                #endif
            }
        case .landing, .entryOpen:
            // Landing and an opened entry are the same surface — the entry
            // decompresses in place within the strata (addendum A2). The map
            // never stops being a map; there is no pushed read screen.
            LandingStrataView(axis: axis)
        case .seed:
            InteractiveBackSwipeContainer(onBack: { axis.closeSeed() }) {
                AnkySettingsView(
                    viewModel: youViewModel,
                    onGateSetupRequested: { showsGateSetup = true }
                )
                .environmentObject(entitlements)
            }
        }
    }
}

/// The channel is closed (spec §4): the keyboard has fallen and the session's
/// writing rests above, settled on the parchment, fading toward the Anchor
/// revealed at the base. From here there are exactly two moves — hold the
/// Anchor to send (handled by the overlay), or swipe up to let the day settle
/// unsent into the strata. No buttons, no "Send to Anky" label.
struct ChannelClosedView: View {
    let session: SavedAnky?
    let onSettle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(session?.reconstructedText ?? "")
                // The sealed writing at rest — ore (addendum A4).
                .oreVoice()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.top, 40)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The writing thins as it nears the Anchor — the day is already spoken.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.55),
                    .init(color: .clear, location: 0.82)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .contentShape(Rectangle())
        // Swipe up: walk away. The day settles into the strata, still saved —
        // unsent ≠ lost.
        .highPriorityGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.height < -70 {
                        AnkyHaptics.light()
                        onSettle()
                    }
                }
        )
    }
}

/// The electric register: the Geshtu interior as X-ray — deep indigo-black,
/// faint blue wood-grain density (spec §1, §10). Rendered fully in Phase 4;
/// this is the ground it sits on.
struct ElectricRegister: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.displayP3, red: 0.03, green: 0.04, blue: 0.10),
                Color(.displayP3, red: 0.05, green: 0.07, blue: 0.16),
                Color(.displayP3, red: 0.02, green: 0.03, blue: 0.08)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// A quiet lazure (or electric) placeholder for a phase whose real surface
/// arrives in a later phase. Deliberately spare — no chrome, in register.
private struct ScaffoldSurface: View {
    let line: String
    var detail: String = ""
    var electric: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            Text(line)
                .font(.fraunces(24, weight: .regular, italic: true))
                .foregroundStyle(electric ? Color(.displayP3, red: 0.70, green: 0.82, blue: 1.0) : Color.ankyInk)
                .multilineTextAlignment(.center)
            if !detail.isEmpty {
                Text(detail)
                    .font(.fraunces(14, weight: .light))
                    .foregroundStyle((electric ? Color.white : Color.ankyInkSoft).opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 160)
    }
}

#if DEBUG
/// Dev-only phase stepper so the whole machine is walkable while surfaces are
/// scaffolds (Phase 1). Removed in Phase 8.
private struct DebugAxisStepper: View {
    @ObservedObject var axis: AxisState

    private let order: [(String, AxisState.Phase)] = [
        ("write", .writing),
        ("closed", .channelClosed),
        ("vigil", .vigil),
        ("reflect", .reflection),
        ("land", .landing),
        ("entry", .entryOpen),
        ("seed", .seed)
    ]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(order, id: \.0) { label, phase in
                    Button(label) { axis.debugSetPhase(phase) }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.vertical, 4).padding(.horizontal, 7)
                        .background(axis.phase == phase ? Color.ankyGold.opacity(0.9) : Color.ankyInk.opacity(0.35))
                        .foregroundStyle(axis.phase == phase ? Color.ankyInk : Color.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 4)
            // Seed synthetic strata so the landing/opened-entry/surfacing paths
            // can be seen and measured (addendum A1–A3, Q6). Dev-only.
            HStack(spacing: 6) {
                ForEach(["seed", "seed500", "wipe"], id: \.self) { action in
                    Button(action) {
                        switch action {
                        case "seed":    AxisDebugSeed.seedShowcase()
                        case "seed500": AxisDebugSeed.seedBulk(500)
                        default:        AxisDebugSeed.wipe()
                        }
                        axis.debugSetPhase(.landing)
                        axis.debugReloadLanding()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.vertical, 4).padding(.horizontal, 7)
                    .background(Color.ankyViolet.opacity(0.55))
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }
}
#endif
