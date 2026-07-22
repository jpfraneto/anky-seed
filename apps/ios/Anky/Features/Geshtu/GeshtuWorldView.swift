//
//  GeshtuWorldView.swift
//  Anky — the Geshtu Redesign (spec §1, §11).
//
//  The container of the vertical world: it renders whatever surface the
//  current GeshtuState.Phase calls for, with the Anchor overlaid above the
//  entire hierarchy at its fixed, eternal position. The registers switch here
//  — warm lazure for the human world, electric indigo only during the vigil.
//
//  Phase 1 note: the per-phase surfaces below are lazure scaffolds. Real
//  surfaces arrive in later phases — the strata (§2), the reveal keyboard-fall
//  (§3), the electric vigil (§4), the reflection descent (§5). The state
//  machine and the Anchor are permanent; only the surfaces get replaced.
//

import RevenueCat
import SwiftUI

struct GeshtuWorldView: View {
    @StateObject private var axis = GeshtuState()
    /// The axis world owns one writing engine — the real WriteViewModel, with
    /// its 62.5Hz ticker, per-keystroke atomic writes, and the 8s sentinel. The
    /// axis only listens for the seal; it never reimplements the mechanics.
    @StateObject private var writeViewModel = WriteViewModel()
    /// The send vigil's charge/haptics, driven by the continuous Anchor press.
    @StateObject private var vigil = VigilController()
    /// Fires the reflection request at the sentinel so the vigil hides latency.
    @StateObject private var reflection = GeshtuReflectionCoordinator()
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
    /// The global y of the keyboard's top edge, held past dismissal — the line
    /// the sealed writing rests on and the reflection unrolls from.
    @State private var sealedKeyboardTop: CGFloat = UIScreen.main.bounds.height - 336
    /// Share leaving the sealed surfaces (channel closed, reflection).
    @State private var shareRequest: GeshtuShareRequest?
    // In-place recording (user decision, 2026-07-16): the record act summons
    // a selfie bubble onto the current viewport; the geshtu starts and stops
    // the capture; the same top-right button — now feeling active — dismisses
    // the camera. No separate recording screen exists anymore.
    @StateObject private var selfie = SelfieCameraController()
    @StateObject private var screenRecorder = GeshtuScreenRecorder()
    @State private var cameraActive = false
    // The bubble is the writer's to place (user request, 2026-07-17): drag
    // moves it, pinch resizes it — before or during a take. Committed values
    // survive dismissal so the bubble returns where it was left.
    @State private var bubbleOffset: CGSize = .zero
    @GestureState private var bubbleDragDelta: CGSize = .zero
    @State private var bubbleScale: CGFloat = 1
    @GestureState private var bubblePinchDelta: CGFloat = 1

    /// The first-launch animatic → live name entry (implementation pack,
    /// 2026-07-17). True until the newborn writer has given (or declined) a
    /// name; the world waits fully covered beneath it.
    @State private var showsNameOnboarding = OnboardingAnimaticLedger.needsOnboarding()

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
                    onNeedsPaywall: { presentGate() },
                    recordArmed: cameraActive,
                    isRecordingTake: screenRecorder.isRecording,
                    onRecordToggle: { toggleRecording() }
                )
                .zIndex(1000)
            }

            // The selfie bubble on the current viewport — part of the screen,
            // therefore part of the recording. The writer scrolls the archive
            // freely around it, drags it anywhere, and pinches it smaller or
            // bigger (user request, 2026-07-17); it starts bottom-leading and
            // remembers where it was left.
            if cameraActive {
                VStack {
                    Spacer()
                    HStack {
                        SelfieBubble(session: selfie.session, isRecording: screenRecorder.isRecording)
                            .scaleEffect(bubbleScale * bubblePinchDelta)
                            .offset(
                                x: bubbleOffset.width + bubbleDragDelta.width,
                                y: bubbleOffset.height + bubbleDragDelta.height
                            )
                            .gesture(bubbleGesture)
                        Spacer()
                    }
                }
                .padding(.leading, 18)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1400)
            }

            // The end card is being stitched onto the finished take.
            if screenRecorder.isProcessing {
                VStack {
                    HStack(spacing: 8) {
                        ProgressView().tint(Color.ankyInkSoft)
                        Text(AnkyLocalization.ui("weaving your clip…"))
                            .font(.fraunces(14, weight: .light, italic: true))
                            .foregroundStyle(Color.ankyInkSoft)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.ankyPaper.opacity(0.9)))
                    .shadow(color: Color.ankyViolet.opacity(0.15), radius: 8, y: 2)
                    .padding(.top, 14)
                    Spacer()
                }
                .transition(.opacity)
                .zIndex(1600)
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

            // The fixed top-right chrome of the warm surfaces (product
            // decision, 2026-07-15): share / record / settings hold the exact
            // spot the timer holds during writing. Always there — never
            // inline in the content, never below an opened day.
            // The animatic owns the screen until the name lands; when it
            // fades, the writing surface is already waiting underneath.
            if showsNameOnboarding {
                OnboardingAnimaticView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        showsNameOnboarding = false
                    }
                    // The world opens on the writing page: summon its keyboard
                    // now that the overlay has released the screen.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        writeViewModel.focusWritingKeyboard()
                    }
                }
                .zIndex(3000)
                .transition(.opacity)
            }

            if showsTopChrome {
                GeshtuTopChrome(
                    shareText: chromeShareText,
                    copyText: chromeShareText,
                    promptSource: chromeWritingText,
                    showsRecord: chromeShowsRecord,
                    cameraActive: cameraActive,
                    showsSettings: chromeShowsSettings,
                    onShare: { shareRequest = GeshtuShareRequest(quote: $0, voice: chromeShareVoice) },
                    onToggleCamera: { toggleCamera() },
                    onSettings: { axis.openSeed() }
                )
                .zIndex(1500)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showsTopChrome)
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
        // The gate (user decision, 2026-07-17 — supersedes PaywallSheet and
        // every trial): an unentitled hold makes the phone vibrate and anky
        // says one thing — "skin in the game opens the gate" — over three
        // quiet lines. Dismissing returns to the closed channel; the session
        // settles unsent and is never lost.
        .sheet(isPresented: $showsPaywall) {
            GeshtuGateSheet(store: entitlements)
        }
        // The seed rises from the bottom (user decision, 2026-07-16): a sheet,
        // so leaving it is the intuition it deserves — swipe down. The world
        // waits beneath. The gate setup stacks on top of it.
        .sheet(isPresented: Binding(
            get: { axis.phase == .seed },
            set: { if !$0 { axis.closeSeed() } }
        )) {
            AnkySettingsView(
                viewModel: youViewModel,
                onGateSetupRequested: { showsGateSetup = true }
            )
            .environmentObject(entitlements)
            .presentationDragIndicator(.visible)
            .sheet(isPresented: $showsGateSetup) {
                GateSetupView(viewModel: gateViewModel, onDone: { showsGateSetup = false })
            }
        }
        .sheet(item: $shareRequest) { request in
            ShareCardPreviewView(quote: request.quote, voice: request.voice)
        }
        // The finished take: the clip and its contained actions.
        .sheet(item: $screenRecorder.finished) { finished in
            RecordingShareSheet(url: finished.url) { screenRecorder.finished = nil }
        }
        .alert(
            AnkyLocalization.ui("Recording"),
            isPresented: Binding(
                get: { selfie.errorMessage != nil || screenRecorder.errorMessage != nil },
                set: { if !$0 { selfie.errorMessage = nil; screenRecorder.errorMessage = nil } }
            )
        ) {
            Button(AnkyLocalization.ui("OK"), role: .cancel) {}
        } message: {
            Text(selfie.errorMessage ?? screenRecorder.errorMessage ?? "")
        }
        // Remember where the keyboard's top edge stands, so the sealed
        // surfaces can keep the writing on that exact line.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  UIScreen.main.bounds.maxY - frame.minY > 0 else { return }
            sealedKeyboardTop = frame.minY
        }
        // The state machine is born in `.writing`, and SwiftUI's onChange never
        // observes an initial value — so the very first session (the rehearsal,
        // where the fast sentinel matters most) would miss its writing-phase
        // setup. Prime it once on first appearance.
        .onAppear {
            // The free vigil is spent by a delivered reflection, not by the
            // send alone (feedback 2026-07-18): a vigil whose reflection is
            // lost keeps the credit, so its re-offer never meets the gate.
            reflection.onPersisted = { firstVigilUsed = true }
            enterWritingPhase()
        }
        // A late offering armed (the grey geshtu of an unreflected day was
        // taken): fire the reflection now, exactly as the sentinel does at a
        // fresh channel close, so the vigil hides the latency (spec §12).
        .onChange(of: axis.reOffering) { armed in
            if armed, let session = axis.pendingSession {
                reflection.begin(for: session)
            }
        }
        .onChange(of: axis.phase) { newPhase in
            switch newPhase {
            case .writing:
                enterWritingPhase()
            case .reflection:
                // A vigil completed: the offering was carried. Only now does the
                // held reflection reach the store (addendum A3 / Q4) — an unsent
                // session's reflection is never persisted.
                reflection.commit()
                // The free vigil is spent only when a reflection actually
                // persists (the coordinator's onPersisted, wired in onAppear) —
                // a send whose reflection never arrives keeps the credit
                // (feedback 2026-07-18). The rehearsal (if this was it) is
                // over and never explained again.
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

    /// The gate rises (user decision, 2026-07-17): the phone vibrates — a
    /// message from anky, not a store — and, before anything is asked, the
    /// exact reflection prompt anky would send is placed on the clipboard.
    /// The writing is portable: paste it into any tool and do the inference
    /// anywhere. Never announced; learned over time.
    private func presentGate() {
        AnkyHaptics.warning()
        if let writing = axis.pendingSession?.reconstructedText, !writing.isEmpty {
            ClipboardClient().copy(AnkyReflectionPrompt.build(from: writing))
        }
        showsPaywall = true
    }

    /// The front door opens: prime the writing engine for a fresh session. The
    /// rehearsal shortens the sentinel so the reveal — and the long-press vigil
    /// — is discoverable quickly (spec §9); set it before the reset so the first
    /// session picks it up. A previous day is already sealed, so the engine can
    /// reset, and any unsent in-flight reflection is dropped.
    private func enterWritingPhase() {
        guard axis.phase == .writing else { return }
        writeViewModel.terminalSilenceOverrideMs = rehearsalDone ? nil : 4000
        writeViewModel.beginBlankSessionFromWriteTab()
        reflection.discard()
    }

    #if DEBUG
    private func applyDebugLaunchEnv() {
        let env = ProcessInfo.processInfo.environment
        switch env["AXIS_DEBUG_SEED"] {
        case "showcase": GeshtuDebugSeed.seedShowcase()
        case "bulk":     GeshtuDebugSeed.seedBulk(500)
        default:         break
        }
        if env["AXIS_DEBUG_OPEN_FIRST"] == "1", let first = LocalAnkyArchive().list().first {
            axis.openEntry(first)
            return
        }
        if env["AXIS_DEBUG_OPEN_UNSENT"] == "1",
           let unsent = LocalAnkyArchive().list().first(where: { ReflectionStore().load(hash: $0.hash) == nil }) {
            axis.openEntry(unsent)
            // Stand the late offering armed (gravity pull already landed), so
            // the awaiting anchor + filament over an open day is verifiable
            // without a tap tool.
            if env["AXIS_DEBUG_ARM_REOFFER"] == "1" {
                axis.armReOffering(unsent)
            }
            return
        }
        // Stand the lean gate ("skin in the game opens the gate") for
        // screenshots without a tap tool. Prices need an Xcode-launched run
        // (simctl bypasses .storekit injection).
        if env["AXIS_DEBUG_GATE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { presentGate() }
        }
        switch env["AXIS_DEBUG_PHASE"] {
        case "landing":    axis.debugSetPhase(.landing)
        case "entry":      axis.debugSetPhase(.entryOpen)
        case "reflection": axis.debugSetPhase(.reflection)
        case "closed":
            // The closed channel is only itself with an offering standing on
            // it — seed the newest archive entry as the pending session so
            // the awaiting anchor (glow, sparks, filament) is verifiable.
            axis.debugSetPendingSession(LocalAnkyArchive().list().first)
            axis.debugSetPhase(.channelClosed)
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

    // MARK: - The fixed top chrome (share / record / settings)

    /// The chrome lives on every warm surface after the keyboard has fallen.
    /// The writing surface keeps its timer; the electric register stays bare.
    private var showsTopChrome: Bool {
        switch axis.phase {
        case .channelClosed, .reflection, .landing, .entryOpen:
            return true
        case .writing, .vigil, .descent, .seed:
            return false
        }
    }

    /// What share would carry: the chosen paragraph if one is chosen,
    /// otherwise the whole writing of the surface's day.
    private var chromeShareText: String? {
        if let selected = axis.selectedQuote, !selected.isEmpty {
            return selected
        }
        return chromeWritingText
    }

    /// The writer's full writing of the surface's day — what copy's tap
    /// carries when nothing is chosen, and what its long-press wraps in the
    /// reflection prompt for the writer's own AI tool (restored from the old
    /// reveal bar, user request 2026-07-17).
    private var chromeWritingText: String? {
        let text: String?
        switch axis.phase {
        case .channelClosed, .reflection:
            text = axis.pendingSession?.reconstructedText
        case .entryOpen:
            text = axis.openedEntry?.reconstructedText
        default:
            text = nil
        }
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// Whose card the chrome's share signs: ANKY when the chosen paragraph is
    /// from a reflection, YOU otherwise (including the whole-writing fallback).
    private var chromeShareVoice: ShareCardVoice {
        axis.selectedQuote != nil && axis.selectedQuoteIsAnky ? .anky : .you
    }

    /// Record appears only when a piece of writing — the writer's or Anky's —
    /// is on the viewport (user decision, 2026-07-16), and stays while the
    /// camera is up so the same button can always dismiss it.
    private var chromeShowsRecord: Bool {
        cameraActive || chromeShareText != nil
    }

    /// Summon or dismiss the selfie camera — the top-right record button's
    /// act. Dismissing while a take is running stops it first; the finished
    /// clip still arrives.
    private func toggleCamera() {
        if cameraActive {
            if screenRecorder.isRecording { screenRecorder.stop() }
            selfie.stop()
            withAnimation(.easeInOut(duration: 0.35)) { cameraActive = false }
        } else {
            selfie.start()
            withAnimation(.easeInOut(duration: 0.35)) { cameraActive = true }
        }
    }

    /// Drag to place, pinch to size — one simultaneous gesture on the bubble.
    /// The scale is clamped so the face can neither vanish nor swallow the
    /// screen; the offset is clamped so the bubble can never be lost offscreen.
    private var bubbleGesture: some Gesture {
        SimultaneousGesture(
            DragGesture()
                .updating($bubbleDragDelta) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    // Clamp by the bubble's CENTER: its resting center sits at
                    // (76, height - 102) — bottom-leading padding plus half the
                    // 116×156 face — and scaling happens around that center.
                    let bounds = UIScreen.main.bounds
                    let halfW = 58 * bubbleScale
                    let halfH = 78 * bubbleScale
                    let restCenter = CGPoint(x: 76, y: bounds.height - 102)
                    let proposed = CGSize(
                        width: bubbleOffset.width + value.translation.width,
                        height: bubbleOffset.height + value.translation.height
                    )
                    bubbleOffset = CGSize(
                        width: min(max(proposed.width, halfW - restCenter.x),
                                   bounds.width - halfW - restCenter.x),
                        height: min(max(proposed.height, 70 + halfH - restCenter.y),
                                    bounds.height - 12 - halfH - restCenter.y)
                    )
                },
            MagnificationGesture()
                .updating($bubblePinchDelta) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    bubbleScale = min(2.0, max(0.55, bubbleScale * value))
                }
        )
    }

    /// The geshtu's act while the camera is up: start and stop the take.
    private func toggleRecording() {
        if screenRecorder.isRecording {
            screenRecorder.stop()
        } else {
            screenRecorder.start()
        }
    }

    /// Settings joins the cluster only where leaving for the seed and coming
    /// back to the landing is the right round trip. From a closed channel or a
    /// fresh reflection, a detour would discard the moment.
    private var chromeShowsSettings: Bool {
        axis.phase == .landing || axis.phase == .entryOpen
    }

    // The writing surface, persistent across every warm phase — it is the
    // literal top of the world scroll (unified-scroll refactor, 2026-07-17),
    // so entering and leaving it is actual scrolling with native physics,
    // never a surface swap. The old scroll-away gestures are gone: the world
    // scroll settles the day, the sentinels in LandingStrataView lock and
    // release the page, and a session in progress locks the scroll shut.
    private var writingSurface: some View {
        WriteView(
            viewModel: writeViewModel,
            // Focus belongs to an open channel only; at the landing the page
            // is scenery above the strata and must never summon a keyboard —
            // and never while the onboarding animatic still owns the screen
            // (the system keyboard would rise ABOVE the overlay).
            shouldFocus: (axis.phase == .writing || axis.phase == .channelClosed) && !showsNameOnboarding,
            axisMode: true,
            onCompleted: { saved in axis.channelDidClose(session: saved) },
            // The pre-keystroke back arrow: leave the blank page and
            // settle onto the strata. Once writing has started the arrow
            // is gone and only the sentinel closes the channel.
            onCloseToMap: { axis.settleToLanding() }
        )
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
        case .writing, .channelClosed, .landing, .entryOpen, .seed:
            // The warm world is ONE mounted surface (unified-scroll refactor,
            // 2026-07-17): the real writing page is the top of the strata's
            // own scroll, so the front door, the closed channel, the landing,
            // an opened day, and the seed are all positions in a single
            // scroll space. The seal still never re-renders the page — the
            // page never unmounts across these phases at all. Only the
            // electric ritual (vigil, descent) and the reflection replace
            // the world.
            LandingStrataView(
                axis: axis,
                writingPage: { writingSurface },
                writingLocked: axis.phase == .writing && writeViewModel.hasStarted,
                onWritingSettled: {
                    // The page scrolled out of the world: blank it for the
                    // next arrival. (Sealed words are already in the archive;
                    // a blank page has nothing to lose.)
                    writeViewModel.beginBlankSessionFromWriteTab()
                }
            )
            .transition(.asymmetric(
                // Rising into the vigil, the whole world slides up and away;
                // returning from the reflection it settles back quietly.
                insertion: .opacity,
                removal: .move(edge: .top).combined(with: .opacity)
            ))
        case .vigil:
            vigilSurface
        case .descent:
            // The offering was carried; the words hold at the glowing crown
            // until the response is ready, then travel back down the spine.
            VigilDescentView(
                text: axis.pendingSession?.reconstructedText ?? "",
                isReady: { [weak reflection] in
                    guard let vm = reflection?.viewModel else { return true }
                    return vm.reflection != nil || !vm.isAskingAnky
                },
                onLanded: { axis.descentLanded() }
            )
        case .reflection:
            if let vm = reflection.viewModel {
                AxisReflectionCanvas(
                    viewModel: vm,
                    axis: axis,
                    writingText: axis.pendingSession?.reconstructedText ?? "",
                    keyboardTop: sealedKeyboardTop,
                    onShare: { shareRequest = GeshtuShareRequest(quote: $0, voice: .you) },
                    onShareReflection: { shareRequest = GeshtuShareRequest(quote: $0, voice: .anky) }
                )
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
        }
    }
}

/// The fixed top-right chrome of the warm surfaces: share, record, settings —
/// on the same spot the timer holds during writing (product decision,
/// 2026-07-15). Share and record exist only while a piece of writing — the
/// writer's or Anky's — is on the viewport (user decision, 2026-07-16); they
/// come and go subtly, never adding noise to the bare strata. The record
/// button turns active while the camera is up, and tapping it then dismisses
/// the camera.
private struct GeshtuTopChrome: View {
    let shareText: String?
    /// Copy rides with share: whatever writing is on the viewport. Tap
    /// copies it; long-press copies `promptSource` wrapped in the reflection
    /// prompt for the writer's own AI tool — the old reveal bar's affordance,
    /// restored (user request, 2026-07-17).
    let copyText: String?
    let promptSource: String?
    let showsRecord: Bool
    let cameraActive: Bool
    let showsSettings: Bool
    let onShare: (String) -> Void
    let onToggleCamera: () -> Void
    let onSettings: () -> Void

    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 10) {
            if let copyText {
                copyButton(copyText)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
            if let shareText {
                chromeButton(label: "Share") {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.ankyInkSoft)
                } action: { onShare(shareText) }
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
            if showsRecord {
                // The camera button only summons and dismisses; the RECORD
                // face lives on the geshtu (user decision, 2026-07-16). While
                // the camera is up this button reads as *pressed* — sunken
                // paper, no shadow — never as the record button itself.
                chromeButton(
                    label: cameraActive ? "Dismiss camera" : "Record",
                    pressed: cameraActive
                ) {
                    Image(systemName: cameraActive ? "video.fill" : "video")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(cameraActive ? Color.ankyInk : Color.ankyInkSoft)
                } action: { onToggleCamera() }
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
            if showsSettings {
                chromeButton(label: "Settings") {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.ankyInkSoft)
                } action: { onSettings() }
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: shareText != nil)
        .animation(.easeInOut(duration: 0.3), value: copyText != nil)
        .animation(.easeInOut(duration: 0.3), value: showsRecord)
        .animation(.easeInOut(duration: 0.3), value: showsSettings)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(true)
    }

    private func chromeButton(
        label: String,
        pressed: Bool = false,
        @ViewBuilder icon: () -> some View,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            AnkyHaptics.light()
            action()
        } label: {
            icon()
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(pressed ? Color.ankyPaperDeep.opacity(0.95) : Color.ankyPaper.opacity(0.55))
                        .overlay(Circle().strokeBorder(
                            pressed ? Color.ankyInk.opacity(0.22) : Color.ankyInk.opacity(0.08),
                            lineWidth: pressed ? 1 : 0.5
                        ))
                        .shadow(
                            color: pressed ? .clear : Color.ankyViolet.opacity(0.10),
                            radius: 5, y: 2
                        )
                }
                .scaleEffect(pressed ? 0.94 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.3), value: pressed)
        .accessibilityLabel(AnkyLocalization.ui(label))
    }

    /// Not a Button — the long-press (reflection prompt) has to coexist with
    /// the tap (writing), exactly as on the old reveal bar.
    private func copyButton(_ text: String) -> some View {
        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(didCopy ? Color.ankySage : Color.ankyInkSoft)
            .frame(width: 40, height: 40)
            .background {
                Circle()
                    .fill(Color.ankyPaper.opacity(0.55))
                    .overlay(Circle().strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: Color.ankyViolet.opacity(0.10), radius: 5, y: 2)
            }
            .contentShape(Circle())
            .onTapGesture { performCopy(text) }
            .onLongPressGesture(minimumDuration: 0.55) {
                guard let promptSource else { return }
                performCopy(AnkyReflectionPrompt.build(from: promptSource))
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(AnkyLocalization.ui(didCopy ? "Copied" : "Copy writing"))
            .accessibilityHint(AnkyLocalization.ui("Long press to copy the reflection prompt for your own AI tool."))
    }

    private func performCopy(_ text: String) {
        ClipboardClient().copy(text)
        withAnimation(.easeInOut(duration: 0.2)) { didCopy = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { didCopy = false }
        }
    }
}

/// The gate, extremely lean (user decision, 2026-07-17): no trial, no
/// benefits list, no store furniture. One line from anky and three options
/// that are barely more than lines — weekly, monthly, yearly. The reflection
/// prompt is already on the clipboard by the time this rises.
private struct GeshtuGateSheet: View {
    @ObservedObject var store: EntitlementStore
    @Environment(\.dismiss) private var dismiss

    @State private var purchasingPlan: AnkySubscriptionPlan?

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text(AnkyLocalization.ui("skin in the game opens the gate"))
                    .font(.fraunces(21, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 48)

                Spacer(minLength: 26)

                // The lines rest on a paper scrim: the wall's violet lower
                // register sat directly beneath the ink and swallowed it
                // (feedback 2026-07-18). Paper under ink, always.
                VStack(spacing: 0) {
                    gateLine(.weekly, label: "weekly")
                    gateLine(.monthly, label: "monthly")
                    gateLine(.annual, label: "yearly")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.ankyPaper.opacity(0.88))
                )
                .padding(.horizontal, 30)

                if let line = store.purchaseErrorLine {
                    Text(line)
                        .font(.fraunces(12, weight: .light))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 14)
                        .transition(.opacity)
                }

                Spacer(minLength: 40)
            }
        }
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.hidden)
        .task { await store.loadPackages() }
        .onChange(of: store.isEntitledForGating) { entitled in
            if entitled { dismiss() }
        }
    }

    private func package(for plan: AnkySubscriptionPlan) -> Package? {
        switch plan {
        case .weekly: return store.weeklyPackage
        case .monthly: return store.monthlyPackage
        case .annual: return store.annualPackage
        }
    }

    /// One option: a hairline, a word, a price. Nothing else.
    private func gateLine(_ plan: AnkySubscriptionPlan, label: String) -> some View {
        let package = package(for: plan)
        return Button {
            guard let package else {
                Task { await store.loadPackages() }
                return
            }
            purchasingPlan = plan
            Task {
                let entitled = await store.purchase(package)
                purchasingPlan = nil
                if entitled { dismiss() }
            }
        } label: {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.ankyInk.opacity(0.12))
                    .frame(height: 0.5)
                HStack {
                    Text(AnkyLocalization.ui(label))
                        .font(.fraunces(16, weight: .light))
                        .foregroundStyle(Color.ankyInk.opacity(0.85))
                    Spacer()
                    if purchasingPlan == plan {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.ankyInkSoft)
                    } else {
                        Text(package?.localizedPriceString ?? "")
                            .font(.fraunces(14, weight: .light))
                            .foregroundStyle(Color.ankyInkSoft)
                    }
                }
                .padding(.vertical, 15)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(purchasingPlan != nil)
        .opacity(package == nil ? 0.4 : 1)
        .accessibilityLabel(Text(AnkyLocalization.ui(label)))
        .accessibilityValue(Text(package?.localizedPriceString ?? ""))
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

// The DEBUG phase stepper and seed/wipe buttons that floated at the top are
// gone (user decision, 2026-07-16: noise, and they blocked real testing).
// Deterministic debug entry remains via launch env (applyDebugLaunchEnv);
// destructive seeding is env-only and never one tap away.
