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
    // The seed (spec §7): identity, subscription, recovery phrase, account
    // deletion, and the gate — the real settings, reached by scrolling to the
    // base of the past.
    @StateObject private var youViewModel = YouViewModel()
    @StateObject private var gateViewModel = WriteBeforeScrollSpikeViewModel()
    @State private var showsGateSetup = false
    @State private var showsDeleteConfirmation = false
    // In-place recording (user decision, 2026-07-16): the record act summons
    // a selfie bubble onto the current viewport; the record button starts and stops
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

    /// The first-launch animatic. The world waits fully covered beneath it.
    @State private var showsOnboarding = OnboardingAnimaticLedger.needsOnboarding()

    /// The drawer follows the finger; released, it springs open or shut.
    @GestureState(reset: { _, transaction in
        transaction.animation = GeshtuState.drawerSpring
    }) private var drawerDrag: CGFloat = 0

    /// One surface with a drawer beside it (user decision, 2026-10-08): the
    /// page — the writing, or one written session — is always in front, and
    /// the history slides in from the leading edge, pushing the page aside.
    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(geometry.size.width * 0.82, 340)
            let progress = min(1, max(0, (axis.drawerIsOpen ? 1 : 0) + drawerDrag / drawerWidth))

            ZStack(alignment: .leading) {
                Color.ankyPaperDeep
                    .ignoresSafeArea()

                // Mounted only while it can be seen: the archive is not read
                // at launch, and never while the writer is writing.
                if progress > 0 {
                    SessionDrawerView(
                        axis: axis,
                        currentHash: axis.openedEntry?.hash ?? axis.pendingSession?.hash,
                        onNewWriting: startNewWriting
                    )
                    .frame(width: drawerWidth)
                    .offset(x: (progress - 1) * 44)
                    .opacity(Double(progress))
                    .simultaneousGesture(drawerCloseDrag(width: drawerWidth))
                }

                page
                    .simultaneousGesture(drawerOpenDrag(width: drawerWidth))
                    .overlay {
                        if progress > 0 {
                            // The page set aside: it dims, wears the corners
                            // of a card, and any touch on it brings it back.
                            ZStack {
                                Color.ankyInk.opacity(0.10 * Double(progress))
                                LeadingCornerCutouts(radius: 40 * min(1, progress * 2.5))
                                    .fill(Color.ankyPaperDeep)
                            }
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { axis.closeDrawer() }
                            .gesture(drawerCloseDrag(width: drawerWidth))
                            .accessibilityLabel(Text(AnkyLocalization.ui("Close menu")))
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .offset(x: progress * drawerWidth)
            }
        }
        .environmentObject(axis)
        // Every warm Geshtu surface owns a parchment register and dark ink.
        // Pinning its appearance keeps system materials, text fields, status
        // chrome, and translucent meshes from inheriting device dark mode.
        .preferredColorScheme(.light)
        .onChange(of: axis.drawerIsOpen) { isOpen in
            if isOpen { dismissKeyboard() }
        }
        .onChange(of: drawerDrag != 0) { dragging in
            if dragging {
                dismissKeyboard()
            } else {
                // A pull that was let go short of opening: the page is the
                // writing again, and its keyboard comes back.
                DispatchQueue.main.async {
                    if !axis.drawerIsOpen, axis.phase == .writing {
                        writeViewModel.focusWritingKeyboard()
                    }
                }
            }
        }
    }

    /// The drawer can be pulled out from the leading edge whenever the menu
    /// button would be offered — never across a live writing session.
    private var drawerAllowed: Bool {
        if showsOnboarding { return false }
        if axis.phase == .writing {
            return !writeViewModel.hasStarted && !writeViewModel.bottomSurfaceStands
        }
        return true
    }

    private func drawerOpenDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drawerDrag) { value, state, _ in
                guard !axis.drawerIsOpen, drawerAllowed, value.startLocation.x < 30 else { return }
                // Engage only once the drag is clearly horizontal, so
                // edge-adjacent scrolls stay scrolls.
                guard state > 0 || value.translation.width > abs(value.translation.height) else { return }
                state = max(0, value.translation.width)
            }
            .onEnded { value in
                guard !axis.drawerIsOpen, drawerAllowed, value.startLocation.x < 30,
                      value.translation.width > abs(value.translation.height) else { return }
                if value.translation.width > width * 0.3
                    || value.predictedEndTranslation.width > width * 0.6 {
                    AnkyHaptics.light()
                    axis.openDrawer()
                }
            }
    }

    private func drawerCloseDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drawerDrag) { value, state, _ in
                guard axis.drawerIsOpen else { return }
                guard state < 0 || -value.translation.width > abs(value.translation.height) else { return }
                state = min(0, value.translation.width)
            }
            .onEnded { value in
                guard axis.drawerIsOpen,
                      -value.translation.width > abs(value.translation.height) else { return }
                if value.translation.width < -width * 0.25
                    || value.predictedEndTranslation.width < -width * 0.5 {
                    axis.closeDrawer()
                }
            }
    }

    /// The drawer's "new writing": a fresh page, unless the page already is
    /// the writing.
    private func startNewWriting() {
        if axis.phase != .writing {
            axis.openWriting()
        }
        axis.closeDrawer()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// The page: the writing machine or one written session, with the fixed
    /// controls that float over it.
    private var page: some View {
        ZStack {
            register
                .ignoresSafeArea()

            // The page itself. Which face it wears is the phase; there is no
            // list underneath it and nothing is ever pushed over it.
            deviceSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(10)

            // The base of the page is empty except while the camera is up,
            // when the record button stands there to start and stop the take.
            if cameraActive {
                RecordButton(
                    isRecording: screenRecorder.isRecording,
                    onToggle: { toggleRecording() }
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
                        SelfieBubble(camera: selfie)
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

            // The take is already in the camera roll — this only says so.
            if screenRecorder.justSaved {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ankySage)
                        Text(AnkyLocalization.ui("saved to your camera roll"))
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
            // The animatic owns the screen until it ends; when it fades, the
            // writing surface is already waiting underneath.
            if showsOnboarding {
                OnboardingAnimaticView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        showsOnboarding = false
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
                    writing: chromeWritingText,
                    offersPrompt: sessionOnPageIsFullAnky,
                    cameraActive: cameraActive,
                    onNewWriting: { axis.openWriting() },
                    onToggleCamera: { toggleCamera() },
                    onDelete: {
                        AnkyHaptics.warning()
                        showsDeleteConfirmation = true
                    }
                )
                .opacity(topChromeIsVisible ? 1 : 0)
                .offset(y: topChromeIsVisible ? 0 : -7)
                .allowsHitTesting(topChromeIsVisible)
                .animation(.easeInOut(duration: 0.24), value: topChromeIsVisible)
                .zIndex(1500)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showsTopChrome)
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
            GeshtuGateSheet(store: entitlements, offersPrompt: sessionOnPageIsFullAnky)
        }
        // Settings rise from the bottom (user decision, 2026-07-16): a sheet,
        // so leaving it is the intuition it deserves — swipe down. Whatever
        // was standing waits beneath. The gate setup stacks on top of it.
        .sheet(isPresented: $axis.settingsIsOpen) {
            AnkySettingsView(
                viewModel: youViewModel,
                onGateSetupRequested: { showsGateSetup = true }
            )
            .environmentObject(entitlements)
            .presentationDragIndicator(.visible)
            .sheet(isPresented: $showsGateSetup) {
                GateSetupView(viewModel: gateViewModel)
            }
        }
        .alert(
            AnkyLocalization.ui("Delete writing session?"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(AnkyLocalization.ui("Delete"), role: .destructive) { deleteSessionOnPage() }
            Button(AnkyLocalization.ui("Cancel"), role: .cancel) {}
        } message: {
            Text(AnkyLocalization.ui("This permanently deletes this writing session. This cannot be undone."))
        }
        .sheet(isPresented: $axis.statsIsOpen) {
            WritingStatsView()
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
        // The state machine is born in `.writing`, and SwiftUI's onChange never
        // observes an initial value — so the very first session (the rehearsal,
        // where the fast sentinel matters most) would miss its writing-phase
        // setup. Prime it once on first appearance.
        .onAppear {
            enterWritingPhase()
            #if DEBUG
            if ScreenshotMode.isActive {
                if ScreenshotStage.stagesRecording {
                    cameraActive = true
                    screenRecorder.debugStandRecordingTake()
                }
                ScreenshotStage.apply(axis: axis, writeViewModel: writeViewModel)
            }
            #endif
        }
        .onChange(of: axis.phase) { newPhase in
            switch newPhase {
            case .writing:
                enterWritingPhase()
            case .reflection:
                // Entering is not sending. The weathered, incomplete Geshtu
                // now holds the privacy seam until the three-second vigil.
                AnkyHaptics.selection()
            case .channelClosed:
                // Prepare only — NO network call (outwards pivot §4.1). The
                // writing leaves the device at the explicit outward gesture:
                // the crossroads' reflection tap. Walking away from a closed
                // channel means the words never traveled at all.
                if let session = axis.pendingSession {
                    reflection.prepare(for: session)
                }
            case .entryOpen:
                // Another session took the page: drop any unsent in-flight
                // result of the one that was standing.
                reflection.discard()
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
        if sessionOnPageIsFullAnky,
           let writing = axis.pendingSession?.reconstructedText, !writing.isEmpty {
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

    /// "ask anky for reflection" is the ask (user decision, 2026-10-08): the
    /// tap opens the session's document and sends the writing in the same
    /// act. The words on the key are the consent; there is no second gesture.
    private func requestReflection() {
        guard axis.pendingSession != nil else { return }
        AnkyHaptics.medium()
        axis.openReflectionChannel()
        beginReflectionRequest()
    }

    /// The archive is a separate list, but opening one of its sessions lands
    /// on the same finished-session document. An unreflected archived session
    /// can request its reflection directly from that document.
    private func requestReflection(
        for archivedSession: SavedAnky,
        viewModel: RevealViewModel
    ) {
        beginArchivedReflection(archivedSession, viewModel: viewModel)
    }

    /// Archive reflections stream into the already-open document. The world
    /// and its scroll position stay mounted; only the tail below the writing
    /// changes from the full-width ask button to the listening/stream state.
    private func beginArchivedReflection(
        _ archivedSession: SavedAnky,
        viewModel: RevealViewModel
    ) {
        guard viewModel.reflection == nil, !viewModel.isAskingAnky else { return }
        AnkyHaptics.medium()
        Task { await viewModel.askAnkyForSealedSession() }
    }

    private func beginReflectionRequest() {
        guard axis.phase == .reflection, axis.pendingSession != nil else { return }
        reflection.beginUpload()
        if !rehearsalDone {
            rehearsalDone = true
            writeViewModel.terminalSilenceOverrideMs = nil
        }
    }

    /// The front door opens: prime the writing engine. A "keep writing" from
    /// the crossroads carries its sealed session across the phase change and
    /// reopens it as a continuation; otherwise the page is fresh. The
    /// rehearsal shortens the sentinel so the reveal is discoverable quickly
    /// (spec §9); set it before the reset so the first session picks it up.
    private func enterWritingPhase() {
        guard axis.phase == .writing else { return }
        writeViewModel.terminalSilenceOverrideMs = rehearsalDone ? nil : 4000
        #if DEBUG
        // A staged writing scene owns the engine; a blank session here would
        // wipe the draft the screenshot is of.
        if ScreenshotStage.stagesWritingSurface { return }
        #endif
        if let session = axis.consumeSessionToResume(),
           writeViewModel.continueSession(from: session, allowCompleted: true) {
            // The same words are back on the page; the next keystroke
            // resumes the clock and the sentinel.
        } else if writeViewModel.hasStarted, writeViewModel.completedArtifact == nil {
            // A session the writer stepped out of (the menu) is still standing,
            // frozen. Coming back finds it exactly as it was left.
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
            return
        }
        // Stand the lean gate ("skin in the game opens the gate") for
        // screenshots without a tap tool. Prices need an Xcode-launched run
        // (simctl bypasses .storekit injection).
        if env["AXIS_DEBUG_GATE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { presentGate() }
        }
        switch env["AXIS_DEBUG_PHASE"] {
        case "landing":    axis.openDrawer()
        case "entry":      axis.debugSetPhase(.entryOpen)
        case "reflection": axis.debugSetPhase(.reflection)
        case "closed":
            // The closed channel is only itself with an offering standing on
            // it — seed the newest archive entry as the pending session so
            // the awaiting anchor (glow, sparks, filament) is verifiable.
            axis.debugSetPendingSession(LocalAnkyArchive().list().first)
            axis.debugSetPhase(.channelClosed)
        case "seed":       axis.settingsIsOpen = true
        case "stats":      axis.statsIsOpen = true
        case "blocked":
            // The blocked-apps sheet stands on top of settings.
            axis.settingsIsOpen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showsGateSetup = true }
        default:           break
        }
    }
    #endif

    // MARK: - Register (the ground the world is painted on)

    private var register: some View {
        LazureWall(mood: .dawn)
    }

    // MARK: - The fixed top chrome (share / record / settings)

    /// The chrome lives on every warm surface after the keyboard has fallen.
    /// The writing surface keeps its timer; the electric register stays bare.
    private var showsTopChrome: Bool {
        switch axis.phase {
        case .channelClosed, .reflection, .entryOpen:
            return true
        case .writing:
            return false
        }
    }

    /// Reading controls briefly get out of the text's way while the reader
    /// moves deeper, then return on the first deliberate move upward. Keep
    /// the camera control reachable whenever its live preview is present.
    private var topChromeIsVisible: Bool {
        if cameraActive { return true }
        switch axis.phase {
        case .reflection, .entryOpen:
            return axis.revealChromeIsVisible
        default:
            return true
        }
    }

    /// The session standing on the page, whichever way it got there.
    private var sessionOnPage: SavedAnky? {
        switch axis.phase {
        case .channelClosed, .reflection:
            return axis.pendingSession
        case .entryOpen:
            return axis.openedEntry
        case .writing:
            return nil
        }
    }

    /// Taking the reflection prompt elsewhere is offered only for a full
    /// anky: eight minutes or more (user decision, 2026-10-08).
    private var sessionOnPageIsFullAnky: Bool {
        (sessionOnPage?.durationMs ?? 0) >= AnkyDuration.completeRitualMs
    }

    /// The writer's full writing of the session on the page — what the menu
    /// copies, bare or wrapped in the reflection prompt for the writer's own
    /// AI tool.
    private var chromeWritingText: String? {
        guard let text = sessionOnPage?.reconstructedText, !text.isEmpty else { return nil }
        return text
    }

    /// Deleting leaves nothing to stand on: the page returns to the writing.
    private func deleteSessionOnPage() {
        guard let session = sessionOnPage else { return }
        // A just-sealed session already has its reveal model prepared; one
        // opened from the drawer is deleted through a model of its own.
        let viewModel = (axis.phase == .entryOpen ? nil : reflection.viewModel)
            ?? RevealViewModel(artifact: session)
        viewModel.deleteSession()
        guard viewModel.isDeleted else { return }
        if cameraActive { toggleCamera() }
        axis.openWriting()
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
                    // Clamp by the bubble's CENTER: its resting center is the
                    // bottom-leading padding plus half the face, and scaling
                    // happens around that center.
                    let bounds = UIScreen.main.bounds
                    let halfW = SelfieBubble.size.width / 2 * bubbleScale
                    let halfH = SelfieBubble.size.height / 2 * bubbleScale
                    let restCenter = CGPoint(
                        x: 18 + SelfieBubble.size.width / 2,
                        y: bounds.height - 24 - SelfieBubble.size.height / 2
                    )
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

    /// The record button's act while the camera is up: start and stop the take.
    private func toggleRecording() {
        if screenRecorder.isRecording {
            screenRecorder.stop()
        } else {
            screenRecorder.start()
        }
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
            shouldFocus: axis.phase == .writing && !showsOnboarding && !axis.drawerIsOpen,
            axisMode: true,
            onCompleted: { saved in
                // Prepare the reflection view model before the phase flips —
                // no network yet (outwards pivot §4.1). The surface itself
                // does not change: the writing stays exactly where it is and
                // the machine around it becomes the finished-writing machine.
                reflection.prepare(for: saved)
                axis.channelDidClose(session: saved)
            },
            // The menu: before the first keystroke, or once the writing has
            // ended, it slides the drawer in beside the page.
            onCloseToMap: { axis.openDrawer() },
            onReflect: requestReflection,
            onContinueWriting: resumeSameSession
        )
    }

    // MARK: - The page

    /// The live editor or the finished-session document. A session that was
    /// just written and one opened from the drawer are the same document.
    @ViewBuilder
    private var deviceSurface: some View {
        switch axis.phase {
        case .writing, .channelClosed:
            // The same surface, before and after the writing ends. Sealing is
            // NOT a navigation (in-place completion, 2026-08-18): the words
            // hold their exact place, the keyboard withdraws, and the controls
            // around them change. Only asking Anky mounts another surface.
            writingSurface
        case .entryOpen:
            if let entry = axis.openedEntry {
                ArchivedFinishedSessionView(
                    artifact: entry,
                    axis: axis,
                    onOpenMenu: { axis.openDrawer() },
                    onLateOffer: ReflectionStore().load(hash: entry.hash) == nil
                        ? { session, viewModel in requestReflection(for: session, viewModel: viewModel) }
                        : nil
                )
                // Each session is its own document with its own reveal model.
                .id(entry.hash)
            }
        case .reflection:
            if let vm = reflection.viewModel,
               let artifact = axis.pendingSession {
                FinishedSessionView(
                    viewModel: vm,
                    axis: axis,
                    artifact: artifact,
                    // A sealed session and an archived session are the same
                    // document. Do not retain a keyboard-specific layout for
                    // one entrance and a natural document layout for another.
                    keyboardTop: nil,
                    stage: .conversation,
                    onRequestReflection: requestReflection,
                    onOpenMenu: { axis.openDrawer() },
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

/// The page's leading corners while it stands aside for the drawer: the two
/// slivers outside a rounded card, painted in the drawer's own ground.
private struct LeadingCornerCutouts: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard radius > 0 else { return path }
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true
        )
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

/// The fixed top-right chrome of a written session (2026-10-08): one glass
/// capsule holding "new writing" and a "more" menu, on the same spot the timer
/// holds during writing. Everything a session can have done to it — record,
/// copy, copy with the reflection prompt, delete — lives in that menu.
private struct GeshtuTopChrome: View {
    /// The whole writing of the session on the page.
    let writing: String?
    /// The prompt travels only with a full anky — eight minutes or more.
    let offersPrompt: Bool
    let cameraActive: Bool
    let onNewWriting: () -> Void
    let onToggleCamera: () -> Void
    let onDelete: () -> Void

    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                AnkyHaptics.light()
                onNewWriting()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("New writing"))

            Menu {
                Button {
                    onToggleCamera()
                } label: {
                    Label(
                        AnkyLocalization.ui(cameraActive ? "Dismiss camera" : "Record"),
                        systemImage: cameraActive ? "video.slash" : "video"
                    )
                }
                if let writing {
                    Button {
                        performCopy(writing)
                    } label: {
                        Label(AnkyLocalization.ui("Copy Anky"), systemImage: "doc.on.doc")
                    }
                }
                if let writing, offersPrompt {
                    Button {
                        performCopy(AnkyReflectionPrompt.build(from: writing))
                    } label: {
                        Label(AnkyLocalization.ui("Copy Prompt + Anky"), systemImage: "text.badge.plus")
                    }
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(AnkyLocalization.ui("Delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(didCopy ? Color.ankySage : Color.ankyInkSoft)
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(AnkyLocalization.ui("More"))
        }
        .padding(.horizontal, 4)
        .ankyGlass(in: Capsule(), interactive: false)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func performCopy(_ text: String) {
        ClipboardClient().copy(text)
        AnkyHaptics.light()
        withAnimation(.easeInOut(duration: 0.2)) { didCopy = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { didCopy = false }
        }
    }
}

/// The reflection gate says exactly what Pro does and offers the same two
/// simple durations as the full paywall.
private struct GeshtuGateSheet: View {
    @ObservedObject var store: EntitlementStore
    /// Whether "copy prompt + anky" is on the menu for the session this gate
    /// rose over — the line below must not promise what is not there.
    var offersPrompt = true
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

                Text(AnkyLocalization.ui("Better reflections from Anky's strongest available model"))
                    .font(.fraunces(15, weight: .light))
                    .foregroundStyle(Color.ankyInkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 12)

                Spacer(minLength: 26)

                // The lines rest on a paper scrim: the wall's violet lower
                // register sat directly beneath the ink and swallowed it
                // (feedback 2026-07-18). Paper under ink, always.
                VStack(spacing: 0) {
                    gateLine(.annual)
                    Rectangle()
                        .fill(Color.ankyInk.opacity(0.10))
                        .frame(height: 0.5)
                    gateLine(.monthly)
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
                // the writing is portable — the menu's "copy prompt + anky"
                // wraps it in the reflection prompt for any LLM. (It is already on
                // the clipboard by the time this sheet rises.)
                if offersPrompt {
                    Text(AnkyLocalization.ui("don't want to pay? copy prompt + anky from the menu and take your writing to your favorite llm"))
                        .font(.fraunces(13, weight: .light, italic: true))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 18)
                }

                Spacer(minLength: 30)
            }
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.hidden)
        .task { await store.loadPackages() }
        .onChange(of: store.isEntitledForGating) { entitled in
            if entitled { dismiss() }
        }
    }

    /// One plain line per duration, using StoreKit's localized price.
    private func gateLine(_ plan: AnkySubscriptionPlan) -> some View {
        let package = plan == .annual ? store.annualPackage : store.monthlyPackage
        let availability = package?.localizedPriceString
            ?? AnkyLocalization.ui(store.isLoadingPackages ? "Loading" : "Plan unavailable")
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
            HStack {
                Text(AnkyLocalization.ui(plan == .annual ? "yearly" : "monthly"))
                    .font(.fraunces(16, weight: .light))
                    .foregroundStyle(Color.ankyInk.opacity(0.85))
                Spacer()
                if purchasingPlan == plan || (store.isLoadingPackages && package == nil) {
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
        .disabled(purchasingPlan != nil || store.isPurchasing || (package == nil && store.isLoadingPackages))
        .opacity(package == nil && !store.isLoadingPackages ? 0.62 : 1)
        .accessibilityLabel(Text(AnkyLocalization.ui(plan == .annual ? "yearly" : "monthly")))
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
