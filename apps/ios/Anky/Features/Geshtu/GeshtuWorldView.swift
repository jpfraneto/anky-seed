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
    /// its 62.5Hz ticker, per-keystroke atomic writes, and the stillness
    /// sentinel. The axis only listens for the seal; it never reimplements
    /// the mechanics.
    @StateObject private var writeViewModel = WriteViewModel()
    /// Owns the reflection request for the pending session.
    @StateObject private var reflection = GeshtuReflectionCoordinator()
    /// The one-time onboarding rehearsal (spec §9): the first session gets a
    /// shortened sentinel so the crossroads is discovered quickly. Set true
    /// once the first reflection lands.
    @AppStorage("anky.axisRehearsalDone") private var rehearsalDone = false
    @StateObject private var entitlements = EntitlementStore()
    @State private var showsPaywall = false
    @State private var showsAgeSetup = false
    @State private var hasBirthDate = WriterProfileStore().birthDate() != nil
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

    var body: some View {
        ZStack {
            register
                .ignoresSafeArea()

            // The world — always mounted beneath, holding its scroll position
            // and an opened day while the device is up (device split,
            // 2026-07-22).
            worldSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The device — the writing machine, a sovereign frontmost screen
            // outside the world. It appears over the whole display when the
            // Anchor is tapped; the world keeps its exact place underneath.
            if axis.isDeviceSpace {
                deviceSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The device carries its own ground so it is opaque while
                    // rising and receding — the world never bleeds through.
                    .background(register.ignoresSafeArea())
                    // Putting a blank device down remains a vertical flick.
                    // Finished sessions own vertical scrolling now, so their
                    // drag can never leak through and reveal the archive.
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 40)
                            .onEnded { value in
                                guard putDownAllowed,
                                      abs(value.translation.height) > 70,
                                      abs(value.translation.height) > abs(value.translation.width) else {
                                    return
                                }
                                AnkyHaptics.light()
                                axis.settleToLanding()
                            },
                        including: putDownAllowed ? .all : .subviews
                    )
                    // The writing machine is a new frontmost screen, not a
                    // sheet rising out of the Geshtu. A restrained fade keeps
                    // the world in place while making the page feel mounted
                    // over the whole display.
                    .transition(.opacity)
                    .zIndex(10)
            }

            // The Anchor lives in the world only (crossroads redesign,
            // 2026-07-24): the door into writing from the strata or an opened
            // day. Inside the device it is hidden — except while the camera
            // is up, where it wears the record face.
            if axis.anchorIsVisible || cameraActive {
                AnchorView(
                    axis: axis,
                    sendAllowed: hasBirthDate,
                    onNeedsPaywall: {
                        showsAgeSetup = true
                    },
                    // The explicit outward gesture: only here do the exact
                    // writing bytes leave the device (outwards pivot §4.1).
                    onSendBegan: { reflection.beginUpload() },
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
                    shareIsSelection: axis.selectedQuote?.isEmpty == false,
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
        // Every warm Geshtu surface owns a parchment register and dark ink.
        // Pinning its appearance keeps system materials, text fields, status
        // chrome, and translucent meshes from inheriting device dark mode.
        .preferredColorScheme(.light)
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
        .sheet(isPresented: $showsAgeSetup) {
            AgeAttunementSheet {
                hasBirthDate = true
                showsAgeSetup = false
                beginReflectionRequest()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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
            hasBirthDate = WriterProfileStore().birthDate() != nil
            enterWritingPhase()
        }
        // A late offering armed (the grey geshtu of an unreflected day was
        // taken): stand the view model up now — memory only. The upload
        // itself fires at the send tap, the writer's explicit outward
        // gesture (outwards pivot §4.1).
        .onChange(of: axis.reOffering) { armed in
            if armed, let session = axis.pendingSession {
                reflection.prepare(for: session)
            }
        }
        .onChange(of: axis.phase) { newPhase in
            switch newPhase {
            case .writing:
                enterWritingPhase()
            case .reflection:
                // The offering was sent. Only now does the held reflection
                // reach the store (addendum A3 / Q4) — an unsent session's
                // reflection is never persisted.
                reflection.commit()
                // The rehearsal (if this was it) is over and never
                // explained again.
                if !rehearsalDone {
                    rehearsalDone = true
                    writeViewModel.terminalSilenceOverrideMs = nil
                }
            case .channelClosed:
                // Prepare only — NO network call (outwards pivot §4.1). The
                // writing leaves the device at the explicit outward gesture:
                // the crossroads' reflection tap. Walking away from a closed
                // channel means the words never traveled at all.
                if let session = axis.pendingSession {
                    reflection.prepare(for: session)
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

    /// The "keep writing" option: reopen the sealed session as a
    /// continuation — same words, same day. The reseal replaces the artifact.
    private func resumeSameSession() {
        AnkyHaptics.light()
        axis.resumeWriting()
    }

    /// The "get anky's reflection" option: the writer's explicit outward
    /// gesture. Only here do the exact writing bytes leave the device
    /// (outwards pivot §4.1). Free writers receive zero-cost inference;
    /// subscribers receive supported inference. Asking ends the session.
    private func requestReflection() {
        guard axis.pendingSession != nil else { return }
        guard hasBirthDate else {
            showsAgeSetup = true
            return
        }
        beginReflectionRequest()
    }

    /// The archive is a separate list, but opening one of its sessions lands
    /// on the same finished-session document. An unreflected archived session
    /// can begin its thread directly from that document; no floating Anchor is
    /// placed over the conversation composer.
    private func requestReflection(for archivedSession: SavedAnky) {
        axis.armReOffering(archivedSession)
        reflection.prepare(for: archivedSession)
        requestReflection()
    }

    private func beginReflectionRequest() {
        guard axis.pendingSession != nil else { return }
        AnkyHaptics.light()
        reflection.beginUpload()
        axis.sendOffering()
    }

    /// The front door opens: prime the writing engine. A "keep writing" from
    /// the crossroads carries its sealed session across the phase change and
    /// reopens it as a continuation; otherwise the page is fresh. The
    /// rehearsal shortens the sentinel so the reveal is discoverable quickly
    /// (spec §9); set it before the reset so the first session picks it up.
    private func enterWritingPhase() {
        guard axis.phase == .writing else { return }
        writeViewModel.terminalSilenceOverrideMs = rehearsalDone ? nil : 4000
        if let session = axis.consumeSessionToResume(),
           writeViewModel.continueSession(from: session, allowCompleted: true) {
            // The same words are back on the page; the next keystroke
            // resumes the clock and the sentinel.
        } else {
            writeViewModel.beginBlankSessionFromWriteTab()
        }
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
        case "seed":       axis.debugSetPhase(.seed)
        default:           break
        }
    }
    #endif

    // MARK: - Register (the ground the world is painted on)

    private var register: some View {
        LazureWall(mood: .dawn)
    }

    /// Only a blank writing page can be put down with a drag. A finished
    /// session is a document with its own scroll and explicit ways out.
    private var putDownAllowed: Bool {
        axis.phase == .writing && !writeViewModel.hasStarted
    }

    // MARK: - The fixed top chrome (share / record / settings)

    /// The chrome lives on every warm surface after the keyboard has fallen.
    /// The writing surface keeps its timer; the electric register stays bare.
    private var showsTopChrome: Bool {
        switch axis.phase {
        case .channelClosed, .reflection, .landing, .entryOpen:
            return true
        case .writing, .seed:
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

    // The writing page of the device (device split, 2026-07-22): no longer
    // the top of any scroll. It mounts only while the channel is open; sealing
    // swaps it for the canonical finished-session document.
    private var writingSurface: some View {
        WriteView(
            viewModel: writeViewModel,
            // Focus belongs to an open channel only; at the landing the page
            // is scenery above the strata and must never summon a keyboard —
            // and never while the onboarding animatic still owns the screen
            // (the system keyboard would rise ABOVE the overlay).
            shouldFocus: axis.phase == .writing && !showsNameOnboarding,
            axisMode: true,
            onCompleted: { saved in
                // Prepare the canonical finished-session surface before the
                // phase flips, so the writing never flashes through a second
                // recap or the archive underneath it.
                reflection.prepare(for: saved)
                axis.channelDidClose(session: saved)
            },
            // The pre-keystroke back arrow: leave the blank page and
            // settle onto the strata. Once writing has started the arrow
            // is gone and only the sentinel closes the channel.
            onCloseToMap: { axis.settleToLanding() }
        )
    }

    // MARK: - The two spaces (device split, 2026-07-22)

    /// The world: the strata, an opened day, the seed. Always mounted — it
    /// holds its scroll position and any opened entry beneath the device, so
    /// putting the device down returns exactly where the writer left off.
    private var worldSurface: some View {
        LandingStrataView(
            axis: axis,
            onRequestReflection: requestReflection(for:)
        )
    }

    /// The device: the live editor or the canonical finished-session document.
    /// Which face it wears is the phase.
    @ViewBuilder
    private var deviceSurface: some View {
        switch axis.phase {
        case .writing:
            writingSurface
        case .landing, .entryOpen, .seed:
            // World phases never mount the device (guarded by isDeviceSpace).
            EmptyView()
        case .channelClosed, .reflection:
            if let vm = reflection.viewModel,
               let artifact = axis.pendingSession {
                FinishedSessionView(
                    viewModel: vm,
                    axis: axis,
                    artifact: artifact,
                    keyboardTop: sealedKeyboardTop,
                    stage: axis.phase == .channelClosed ? .awaitingChoice : .conversation,
                    onKeepWriting: resumeSameSession,
                    onRequestReflection: requestReflection,
                    onClose: {
                        AnkyHaptics.light()
                        axis.settleToLanding()
                    },
                    onNeedsGate: { presentGate() }
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

private struct AgeAttunementSheet: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Text(AnkyLocalization.ui("before anky answers"))
                    .font(.ankyTitle)
                    .foregroundStyle(Color.ankyInk)

                Text(AnkyLocalization.ui("When were you born? Anky uses your age to meet you with the right language, pace, and boundaries."))
                    .font(.ankyProse)
                    .foregroundStyle(Color.ankyInkSoft)
                    .lineSpacing(4)

                DatePicker(
                    AnkyLocalization.ui("Birth date"),
                    selection: $birthDate,
                    in: oldestBirthDate...Date(),
                    displayedComponents: .date
                )
                .font(.ankyLabel)
                .tint(Color.ankyViolet)

                Text(AnkyLocalization.ui("The exact date stays in this device's keychain. Only your age in whole years travels with an Anky request."))
                    .font(.ankyCaption)
                    .foregroundStyle(Color.ankyInkSoft)
                    .lineSpacing(3)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.ankyCaption)
                        .foregroundStyle(Color.ankyUmber)
                }

                Button {
                    do {
                        try WriterProfileStore().saveBirthDate(birthDate)
                        AnkyHaptics.success()
                        onSaved()
                        dismiss()
                    } catch {
                        errorMessage = (error as? LocalizedError)?.errorDescription
                    }
                } label: {
                    Text(AnkyLocalization.ui("continue to anky"))
                        .font(.fraunces(16, weight: .regular))
                        .foregroundStyle(Color.ankyPaper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.ankyViolet, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(26)
        }
    }

    private var oldestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? .distantPast
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
    /// Native text selection promotes Share from a whole-writing action to
    /// an action on the exact selected range.
    let shareIsSelection: Bool
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
                chromeButton(
                    label: shareIsSelection ? "Share selected text" : "Share writing",
                    selected: shareIsSelection
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(shareIsSelection ? Color.ankyGold : Color.ankyInkSoft)
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
        selected: Bool = false,
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
                        .fill(pressed || selected ? Color.ankyPaperDeep.opacity(0.95) : Color.ankyPaper.opacity(0.55))
                        .overlay(Circle().strokeBorder(
                            selected ? Color.ankyGold.opacity(0.72) : (pressed ? Color.ankyInk.opacity(0.22) : Color.ankyInk.opacity(0.08)),
                            lineWidth: pressed || selected ? 1 : 0.5
                        ))
                        .shadow(
                            color: pressed || selected ? .clear : Color.ankyViolet.opacity(0.10),
                            radius: 5, y: 2
                        )
                }
                .scaleEffect(pressed || selected ? 0.94 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.3), value: pressed)
        .animation(.easeInOut(duration: 0.2), value: selected)
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

/// The gate, extremely lean: no trial, no benefits list, no store furniture.
/// One line from anky and the approved yearly plan. The reflection prompt is
/// already on the clipboard by the time this rises.
private struct GeshtuGateSheet: View {
    @ObservedObject var store: EntitlementStore
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasingAnnual = false

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
                    yearlyGateLine
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.ankyPaper.opacity(0.88))
                )
                .padding(.horizontal, 30)

                if let line = store.purchaseErrorLine ?? store.offeringsErrorLine {
                    Text(AnkyLocalization.ui(line))
                        .font(.fraunces(12, weight: .light))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 14)
                        .transition(.opacity)
                }

                // The unpaid path, named plainly (user decision, 2026-07-24):
                // the writing is portable — the copy button's long-press wraps
                // it in the reflection prompt for any LLM. (It is already on
                // the clipboard by the time this sheet rises.)
                Text(AnkyLocalization.ui("don't want to pay? long-press the copy button and take your writing to your favorite llm"))
                    .font(.fraunces(13, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 18)

                Spacer(minLength: 30)
            }
        }
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.hidden)
        .task { await store.loadPackages() }
        .onChange(of: store.isEntitledForGating) { entitled in
            if entitled { dismiss() }
        }
    }

    /// One option: a word and the StoreKit-localized yearly price.
    private var yearlyGateLine: some View {
        let package = store.annualPackage
        let availability = package?.localizedPriceString
            ?? AnkyLocalization.ui(store.isLoadingPackages ? "Loading" : "Plan unavailable")
        return Button {
            guard let package else {
                Task { await store.loadPackages() }
                return
            }
            isPurchasingAnnual = true
            Task {
                let entitled = await store.purchase(package)
                isPurchasingAnnual = false
                if entitled { dismiss() }
            }
        } label: {
            HStack {
                Text(AnkyLocalization.ui("yearly"))
                    .font(.fraunces(16, weight: .light))
                    .foregroundStyle(Color.ankyInk.opacity(0.85))
                Spacer()
                if isPurchasingAnnual || (store.isLoadingPackages && package == nil) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.ankyInkSoft)
                } else {
                    Text(availability)
                        .font(.fraunces(14, weight: .light))
                        .foregroundStyle(Color.ankyInkSoft)
                }
            }
            .padding(.vertical, 15)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPurchasingAnnual || store.isPurchasing || (package == nil && store.isLoadingPackages))
        .opacity(package == nil && !store.isLoadingPackages ? 0.62 : 1)
        .accessibilityLabel(Text(AnkyLocalization.ui("yearly")))
        .accessibilityValue(Text(availability))
        .accessibilityHint(Text(package == nil ? AnkyLocalization.ui("Try again") : ""))
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
