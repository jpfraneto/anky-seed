//
//  GeshtuWorldView.swift
//  Anky
//
//  The whole app: one page, and a drawer of memories beside it.
//
//  With no session open, the page is the threshold — an invitation to walk
//  or stay, and to express. During a session it is whichever medium the
//  person is in: the writing page (unchanged), voice, camera, or presence.
//  A past writing chosen from the drawer stands on the writing page exactly
//  as it was written.
//

import SwiftUI

struct GeshtuWorldView: View {
    @StateObject private var axis = GeshtuState()
    /// The one writing engine. The world only listens for the seal and hands
    /// it past writings to put on the page.
    @StateObject private var writeViewModel = WriteViewModel()
    @StateObject private var youViewModel = YouViewModel()
    @StateObject private var gateViewModel = WriteBeforeScrollSpikeViewModel()
    /// The open session, its mediums and recorders.
    @StateObject private var expression = ExpressionController()
    @ObservedObject private var access = AccessController.shared
    @State private var showsPaywall = false
    @State private var memorySheet: ExpressionSession?
    /// A past writing chosen from the drawer while a session is open: read in
    /// a sheet, so the session's page is never replaced.
    @State private var readingWriting: SavedAnky?
    @State private var reflectionFor: SavedAnky?
    @State private var exportURL: URL?
    @State private var isExportingAll = false
    @State private var confirmsEnd = false
    @State private var showsGateSetup = false
    /// One quiet line after the shield's emergency button opened the apps.
    @State private var gateLine: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsDeleteConfirmation = false

    /// The first-launch animatic. The world waits fully covered beneath it.
    @State private var showsOnboarding = OnboardingAnimaticLedger.needsOnboarding()

    /// The drawer follows the finger; released, it springs open or shut.
    @GestureState(reset: { _, transaction in
        transaction.animation = GeshtuState.drawerSpring
    }) private var drawerDrag: CGFloat = 0

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
                        currentHash: writeViewModel.completedArtifact?.hash,
                        activeSessionID: expression.session?.id,
                        onNewWriting: returnToPageFromDrawer
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
        // The parchment register is pinned light so system materials never
        // inherit device dark mode.
        .preferredColorScheme(.light)
        .onChange(of: axis.drawerIsOpen) { isOpen in
            if isOpen { dismissKeyboard() }
        }
        .onChange(of: drawerDrag != 0) { dragging in
            if dragging {
                dismissKeyboard()
            } else {
                // A pull let go short of opening: the keyboard comes back.
                DispatchQueue.main.async {
                    if !axis.drawerIsOpen, writeViewModel.canAcceptInput {
                        writeViewModel.focusWritingKeyboard()
                    }
                }
            }
        }
        .onChange(of: axis.entryRequest?.hash) { _ in
            guard let entry = axis.consumeEntryRequest() else { return }
            if expression.isActive {
                readingWriting = entry
            } else {
                writeViewModel.showFinishedSession(entry)
            }
        }
        .onChange(of: axis.sessionRequest?.id) { _ in
            guard let past = axis.consumeSessionRequest() else { return }
            memorySheet = past
        }
        .onChange(of: expression.memoryToShow?.id) { _ in
            if let memory = expression.memoryToShow {
                memorySheet = memory
                expression.memoryToShow = nil
            }
        }
    }

    /// The drawer can be pulled out from the leading edge whenever the menu
    /// button would be offered — never across a live writing.
    private var drawerAllowed: Bool {
        if showsOnboarding { return false }
        if expression.isActive, expression.medium != .write {
            return !expression.isCapturing
        }
        return !writeViewModel.hasStarted || writeViewModel.completedArtifact != nil
    }

    private func drawerOpenDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drawerDrag) { value, state, _ in
                guard !axis.drawerIsOpen, drawerAllowed, value.startLocation.x < 30 else { return }
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

    /// A fresh writing inside the session (a new passage), or — outside a
    /// session — back to the threshold.
    private func startNewWriting() {
        if expression.isActive {
            guard expression.canContinueWriting() else { return }
            writeViewModel.beginBlankSessionFromWriteTab()
            writeViewModel.focusWritingKeyboard()
        } else {
            writeViewModel.beginBlankSessionFromWriteTab()
        }
        axis.closeDrawer()
    }

    /// The drawer's floating button: back to the open session, or to the
    /// threshold to begin one.
    private func returnToPageFromDrawer() {
        if !expression.isActive, writeViewModel.completedArtifact != nil {
            writeViewModel.beginBlankSessionFromWriteTab()
        }
        axis.closeDrawer()
        if expression.isActive, expression.medium == .write, writeViewModel.canAcceptInput {
            writeViewModel.focusWritingKeyboard()
        }
    }

    private func endSession() {
        Task {
            await expression.end()
            writeViewModel.beginBlankSessionFromWriteTab()
            dismissKeyboard()
        }
    }

    private func connectWritingToSessions() {
        expression.enterWriting = { [weak writeViewModel] in
            guard let writeViewModel else { return }
            if writeViewModel.hasStarted || writeViewModel.completedArtifact != nil {
                writeViewModel.beginBlankSessionFromWriteTab()
            }
            DispatchQueue.main.async { writeViewModel.focusWritingKeyboard() }
        }
        expression.leaveWriting = { [weak writeViewModel] in
            writeViewModel?.endWriting()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        expression.restoreOnLaunch(
            writingInProgress: writeViewModel.hasStarted && writeViewModel.completedArtifact == nil
        )
    }

    private func exportEverything() {
        guard !isExportingAll else { return }
        isExportingAll = true
        Task {
            defer { isExportingAll = false }
            exportURL = try? await MemoryExporter.makeArchive(.everything)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// What the page shows right now.
    private enum PageMode: Equatable {
        case threshold
        case writing
        case voice
        case video
        case presence
    }

    private var pageMode: PageMode {
        if expression.isActive {
            switch expression.medium {
            case .write: return .writing
            case .voice: return .voice
            case .video: return .video
            case .rest, .silence: return .presence
            }
        }
        if writeViewModel.completedArtifact != nil || writeViewModel.hasStarted {
            return .writing
        }
        return .threshold
    }

    private var page: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            switch pageMode {
            case .threshold:
                ThresholdView(
                    expression: expression,
                    access: access,
                    onOpenDrawer: { axis.openDrawer() },
                    onSubscribe: { showsPaywall = true },
                    onExport: exportEverything
                )
                .transition(.opacity)
            case .writing:
                writingPage
            case .voice:
                VoiceSurface(expression: expression, onOpenDrawer: { axis.openDrawer() }, onEnd: { confirmsEnd = true })
                    .transition(.opacity)
            case .video:
                CameraSurface(expression: expression, onOpenDrawer: { axis.openDrawer() }, onEnd: { confirmsEnd = true })
                    .transition(.opacity)
            case .presence:
                PresenceSurface(expression: expression, onOpenDrawer: { axis.openDrawer() }, onEnd: { confirmsEnd = true })
                    .transition(.opacity)
            }

            if let refusal = expression.refusal, expression.isActive {
                refusalBanner(refusal)
                    .zIndex(1700)
            }

            if let gateLine {
                Text(gateLine)
                    .font(.fraunces(14, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .ankyGlass(in: Capsule(), interactive: false)
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(1600)
            }

            if showsOnboarding {
                OnboardingAnimaticView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        showsOnboarding = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        writeViewModel.focusWritingKeyboard()
                    }
                }
                .zIndex(3000)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: writeViewModel.completedArtifact?.hash)
        .animation(.easeInOut(duration: 0.4), value: gateLine)
        .animation(.easeInOut(duration: 0.35), value: pageMode)
        .onAppear(perform: connectWritingToSessions)
        .onAppear(perform: startWriteBeforeScroll)
        .onReceive(NotificationCenter.default.publisher(for: .writeBeforeScrollNotificationTapped)) { _ in
            routeFromShield()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                Task { await access.refresh() }
                gateViewModel.reconcileOnAppActive(hasCurrentVerifiedPro: true)
                gateViewModel.handlePendingInterventionIfNeeded(showWrite: openWritingFromShield)
                routeFromShield()
            case .background:
                expression.persistOnBackground()
                // A Quick Pass's minutes belong to the app the writer was
                // reaching for, so its window starts on the way out — and a
                // pass earned mid-sentence seals the writing as they leave.
                gateViewModel.startPendingQuickPassWindowIfNeeded()
                writeViewModel.sealIfLeftInMotion()
            default:
                break
            }
        }
        #if DEBUG
        .onAppear {
            if ScreenshotMode.isActive {
                ScreenshotStage.apply(axis: axis, writeViewModel: writeViewModel)
            }
        }
        #endif
        .sheet(isPresented: $axis.settingsIsOpen) {
            AnkySettingsView(
                viewModel: youViewModel,
                onGateSetupRequested: { showsGateSetup = true }
            )
            .presentationDragIndicator(.visible)
            .sheet(isPresented: $showsGateSetup) {
                GateSetupView(viewModel: gateViewModel)
            }
        }
        .sheet(isPresented: $axis.statsIsOpen) {
            WritingStatsView()
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .sheet(item: $memorySheet) { memory in
            SessionMemoryView(
                session: memory,
                onDelete: { expression.delete($0) },
                onSubscribe: { showsPaywall = true }
            )
        }
        .sheet(item: $readingWriting) { writing in
            PastWritingSheet(writing: writing, onReflect: {
                readingWriting = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { reflectionFor = writing }
            })
        }
        .sheet(item: $reflectionFor) { writing in
            ReflectionSheet(writing: writing, onSubscribe: { showsPaywall = true })
        }
        .sheet(item: $exportURL) { url in
            ActivityShareSheet(items: [url])
        }
        .alert(AnkyLocalization.ui("End this session?"), isPresented: $confirmsEnd) {
            Button(AnkyLocalization.ui("End session")) { endSession() }
            Button(AnkyLocalization.ui("Not yet"), role: .cancel) {}
        } message: {
            Text(AnkyLocalization.ui("Everything you expressed is saved on this iPhone."))
        }
        .alert(
            AnkyLocalization.ui("Delete writing session?"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(AnkyLocalization.ui("Delete"), role: .destructive) { deleteFinishedWriting() }
            Button(AnkyLocalization.ui("Cancel"), role: .cancel) {}
        } message: {
            Text(AnkyLocalization.ui("This permanently deletes this writing session. This cannot be undone."))
        }
    }

    // MARK: - Write before you scroll

    /// The gate listens to the writing: a finished sentence from the shield
    /// opens a Quick Pass, reaching the day's minutes opens the day. Both
    /// apply the moment they are earned, with no button.
    private func startWriteBeforeScroll() {
        writeViewModel.bindWriteBeforeScrollUnlockAvailabilityHandler { _ in
            gateViewModel.refresh()
        }
        writeViewModel.bindWriteBeforeScrollPassiveUnlockHandler { grant in
            gateViewModel.applyUnlock(grant, startsCountingOnExit: grant.tier == .quick)
            if writeViewModel.isGateOriginatedSession {
                FirstGateStore().markFirstGateCompleted()
            }
        }
        gateViewModel.reconcileOnAppActive(hasCurrentVerifiedPro: true)
        gateViewModel.handlePendingInterventionIfNeeded(showWrite: openWritingFromShield)
        routeFromShield()
    }

    /// A sealed writing hands over whatever unlock it earned and was not
    /// already applied mid-session.
    private func grantWriteBeforeScrollUnlock() {
        guard let grant = writeViewModel.consumeWriteBeforeScrollAvailableUnlockGrant() else { return }
        if writeViewModel.isGateOriginatedSession {
            FirstGateStore().markFirstGateCompleted()
        }
        if grant.tier == .quick, writeViewModel.hasAppliedPassiveQuickUnlock { return }
        if grant.tier == .daily, writeViewModel.hasAppliedPassiveDailyUnlockUpgrade { return }
        gateViewModel.applyUnlock(grant)
    }

    /// The shield's two buttons each leave a notification; tapping it lands
    /// here. "Write" opens a blank page; "Emergency unlock" opens the apps
    /// for the rest of the day, no writing asked.
    private func routeFromShield() {
        guard let route = WriteBeforeScrollAppRouteResolver().pendingRoute() else { return }
        let bridge = WriteBeforeScrollLaunchBridgeStore()
        switch route {
        case .emergencyBreathFromShield(let intentID):
            let now = Date()
            let endOfDay = Calendar.current.date(
                byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
            ) ?? now.addingTimeInterval(24 * 60 * 60)
            gateViewModel.applyUnlock(
                UnlockGrant(tier: .daily, unlockedUntil: endOfDay, grantedAt: now),
                source: .emergency
            )
            bridge.markConsumed(intentID: intentID)
            showGateLine(AnkyLocalization.ui("Your apps are unlocked."))
        case .writeBeforeScrollFromShield(let intentID):
            guard expression.isActive || access.can(.startSession) else {
                // Writing to unlock needs access now. The gate never traps
                // anyone behind a subscription: the apps open for the day.
                let now = Date()
                let endOfDay = Calendar.current.date(
                    byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
                ) ?? now.addingTimeInterval(24 * 60 * 60)
                gateViewModel.applyUnlock(
                    UnlockGrant(tier: .daily, unlockedUntil: endOfDay, grantedAt: now),
                    source: .emergency
                )
                bridge.markConsumed(intentID: intentID)
                openWritingFromShield()
                showGateLine(AnkyLocalization.ui("Your apps are open for today."))
                return
            }
            openWritingFromShield()
            writeViewModel.markGateOriginatedSession(appDisplayName: bridge.lastAttemptedAppDisplayName())
            bridge.markConsumed(intentID: intentID)
        }
    }

    /// The writer came from a blocked app: the page is in front, ready —
    /// inside the open session, or a new one that begins with writing.
    private func openWritingFromShield() {
        axis.settingsIsOpen = false
        axis.statsIsOpen = false
        axis.closeDrawer()
        guard expression.isActive || access.can(.startSession) else { return }
        Task {
            if expression.isActive {
                if expression.isCapturing { return }
                await expression.switchTo(.write)
            } else {
                await expression.begin(setting: nil, medium: .write)
            }
            if writeViewModel.completedArtifact != nil {
                writeViewModel.beginBlankSessionFromWriteTab()
            }
            writeViewModel.openWritingPortal()
        }
    }

    // MARK: - The writing page

    private var writingPage: some View {
        ZStack {
            WriteView(
                viewModel: writeViewModel,
                shouldFocus: !showsOnboarding && !axis.drawerIsOpen && pageMode == .writing,
                onCompleted: { artifact in
                    grantWriteBeforeScrollUnlock()
                    expression.recordWriting(artifact, replacing: writeViewModel.lastSealReplacedHash)
                },
                onOpenMenu: { axis.openDrawer() },
                canReopen: {
                    if expression.canContinueWriting() { return true }
                    // Outside a session there is no banner to explain it.
                    if !expression.isActive { showsPaywall = true }
                    return false
                },
                topCenter: expression.isActive
                    ? AnyView(SessionRibbon(
                        medium: expression.medium,
                        onChoose: { next in Task { await expression.switchTo(next) } },
                        onEnd: { confirmsEnd = true }
                    ))
                    : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let finished = writeViewModel.completedArtifact {
                FinishedWritingChrome(
                    writing: finished.reconstructedText,
                    inSession: expression.isActive,
                    onNewWriting: startNewWriting,
                    onReflect: { reflectionFor = finished },
                    onDelete: {
                        AnkyHaptics.warning()
                        showsDeleteConfirmation = true
                    }
                )
                .transition(.opacity)
                .zIndex(1500)
            }
        }
    }

    private func refusalBanner(_ refusal: AccessDenial) -> some View {
        VStack(spacing: 10) {
            Text(refusal == .needsVerification
                 ? AnkyLocalization.ui("Anky couldn't confirm your access. Connect to the internet to keep creating. Everything so far is saved.")
                 : AnkyLocalization.ui("Your free days ended during this session. Everything so far is saved. Subscribe to keep creating."))
                .font(.fraunces(15, weight: .light, italic: true))
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Button(AnkyLocalization.ui("Subscribe")) { showsPaywall = true }
                Button(AnkyLocalization.ui("End session")) { confirmsEnd = true }
                Button(AnkyLocalization.ui("Dismiss")) { expression.refusal = nil }
            }
            .font(.fraunces(15, weight: .regular))
            .foregroundStyle(Color.ankyInk)
        }
        .padding(16)
        .ankyGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.opacity)
    }

    private func showGateLine(_ line: String) {
        gateLine = line
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if gateLine == line { gateLine = nil }
        }
    }

    /// Deleting leaves nothing to stand on: the page becomes a blank writing.
    private func deleteFinishedWriting() {
        guard let finished = writeViewModel.completedArtifact else { return }
        do {
            try LocalAnkyArchive().delete(finished)
            try? ReflectionStore().delete(hash: finished.hash)
            try? SessionIndexStore().delete(hash: finished.hash)
            expression.forgetWriting(hash: finished.hash)
        } catch {
            return
        }
        writeViewModel.beginBlankSessionFromWriteTab()
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

/// The top-right of a finished writing, where the clock stood: one glass
/// capsule with "new writing" and a menu — copy the writing, copy it wrapped
/// in the reflection prompt for any AI, or delete it.
private struct FinishedWritingChrome: View {
    let writing: String
    let inSession: Bool
    let onNewWriting: () -> Void
    let onReflect: () -> Void
    let onDelete: () -> Void

    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                AnkyHaptics.light()
                onNewWriting()
            } label: {
                Image(systemName: inSession ? "square.and.pencil" : "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(inSession ? AnkyLocalization.ui("New writing") : AnkyLocalization.ui("Close"))

            Menu {
                Button {
                    performCopy(writing)
                } label: {
                    Label(AnkyLocalization.ui("Copy writing"), systemImage: "doc.on.doc")
                }
                Button {
                    onReflect()
                } label: {
                    Label(AnkyLocalization.ui("Reflect with Anky"), systemImage: "sparkles")
                }
                Button {
                    performCopy(AnkyReflectionPrompt.build(from: writing))
                } label: {
                    Label(AnkyLocalization.ui("Copy prompt + writing"), systemImage: "text.badge.plus")
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

/// The reflection prompt the menu wraps a writing in, for any AI the writer
/// chooses to take it to.
enum AnkyReflectionPrompt {
    static func build(from reconstructedText: String) -> String {
        """
        Take a look at this stream-of-consciousness journal entry.

        Respond with deep insight that feels personal, casual, and alive, not clinical. Be a sharp mirror: part close friend, part mentor, part pattern-recognizer.

        Help the writer see the emotional undercurrents, hidden loops, deeper meaning, contradictions, longings, and connections they might be missing.

        Comfort what is real. Validate without flattering. Challenge gently where needed. Reframe the surface topic into what the writer may really be seeking underneath.

        Do not force introspection for its own sake. Help the writer recognize something true about who they are and move toward a more honest, positive loop in life.

        Use vivid metaphors and powerful imagery when they reveal something real. Don't diagnose, don't sound like therapy, and don't give generic advice.

        Write in the same language and vibe as the entry.

        Reply with pure markdown, and use headings for different sections. At the top of the reply add a max 4 word title.

        ---

        \(reconstructedText)
        """
    }
}

/// A past writing, read while a session is open (so the session's page is
/// never replaced).
private struct PastWritingSheet: View {
    let writing: SavedAnky
    let onReflect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(writing.createdAt.formatted(date: .complete, time: .shortened))
                        .font(.fraunces(15, weight: .regular))
                        .foregroundStyle(Color.ankyInkSoft)
                    Text(writing.reconstructedText)
                        .font(.fraunces(19, weight: .light))
                        .foregroundStyle(Color.ankyInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onReflect) {
                        Label(AnkyLocalization.ui("Reflect with Anky"), systemImage: "sparkles")
                            .font(.fraunces(15, weight: .regular))
                            .foregroundStyle(Color.ankyInkSoft)
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.ankyPaper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AnkyLocalization.ui("Done")) { dismiss() }
                        .foregroundStyle(Color.ankyInk)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
